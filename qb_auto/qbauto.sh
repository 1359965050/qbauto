#!/bin/bash

# qBittorrent 自动上传脚本
# 功能：自动上传完成的文件到云存储并删除种子（吸血模式）

# 配置文件路径
CONFIG_FILE="/config/qbauto/qbauto.conf"

# 加载配置
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件不存在: $CONFIG_FILE" >&2
    exit 1
fi

# 清理配置文件中的回车符并加载
sed 's/\r$//' "$CONFIG_FILE" > "/tmp/qbauto_clean.conf"
source "/tmp/qbauto_clean.conf"

# 设置 rclone 配置文件路径
if [ -n "$RCLONE_CONFIG" ] && [ -f "$RCLONE_CONFIG" ]; then
    export RCLONE_CONFIG
    
    # 自动查找 rclone 配置文件
    find_rclone_config() {
        local possible_paths=(
            "/config/rclone/rclone.conf"
            "/etc/rclone/rclone.conf" 
            "/home/qbittorrent/.config/rclone/rclone.conf"
            "/root/.config/rclone/rclone.conf"
            "$(rclone config file 2>/dev/null || echo '')"
        )
        
        for path in "${possible_paths[@]}"; do
            if [ -f "$path" ]; then
                echo "$path"
                return 0
            fi
        done
        
        local found_path=$(find / -name "rclone.conf" 2>/dev/null | head -1)
        if [ -n "$found_path" ]; then
            echo "$found_path"
            return 0
        fi
        
        return 1
    }

    RCLONE_CONFIG_AUTO=$(find_rclone_config)
    if [ -n "$RCLONE_CONFIG_AUTO" ]; then
        export RCLONE_CONFIG="$RCLONE_CONFIG_AUTO"
    else
        echo "错误：未找到 rclone 配置文件" >&2
        exit 1
    fi
fi

# 设置默认值
LOG_DIR="${LOG_DIR:-/config/qbauto/log}"
RCLONE_CMD="${RCLONE_CMD:-/usr/bin/rclone}"
LEECHING_MODE="${LEECHING_MODE:-false}"
RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
RCLONE_RETRY_DELAY="${RCLONE_RETRY_DELAY:-10s}"
BLACKLIST_KEYWORDS="${BLACKLIST_KEYWORDS:-}"
VERIFY_UPLOAD="${VERIFY_UPLOAD:-true}"
UPLOAD_STATS_FILE="${UPLOAD_STATS_FILE:-$LOG_DIR/upload_stats.json}"
DELETE_BLACKLISTED="${DELETE_BLACKLISTED:-true}"  # 新增：是否删除黑名单文件

# 初始化日志目录
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qbauto.log"

# 日志函数
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    echo "$message" >&2
}

# =============================================================================
# 配置管理增强
# =============================================================================

# 配置验证函数
validate_config() {
    local errors=0
    local warnings=0
    
    log "🔧 开始配置验证..."
    
    # 检查必要配置
    if [ -z "$RCLONE_DEST" ]; then
        log "❌ 配置错误: RCLONE_DEST 未设置"
        ((errors++))
    else
        log "✅ RCLONE_DEST: $RCLONE_DEST"
    fi
    
    if [ -z "$UPLOAD_PATH" ]; then
        log "❌ 配置错误: UPLOAD_PATH 未设置"
        ((errors++))
    else
        log "✅ UPLOAD_PATH: $UPLOAD_PATH"
    fi
    
    # 验证路径格式
    if [[ "$UPLOAD_PATH" == /* ]]; then
        log "⚠️ 配置警告: UPLOAD_PATH 不应以 / 开头，建议使用相对路径"
        ((warnings++))
    fi
    
    # 检查吸血模式配置
    if [ "$LEECHING_MODE" = "true" ]; then
        log "🔧 吸血模式已启用，检查相关配置..."
        if [ -z "$QB_WEB_URL" ]; then
            log "❌ 配置错误: 吸血模式需要设置 QB_WEB_URL"
            ((errors++))
        else
            log "✅ QB_WEB_URL: $QB_WEB_URL"
        fi
        
        if [ -z "$QB_USERNAME" ]; then
            log "❌ 配置错误: 吸血模式需要设置 QB_USERNAME"
            ((errors++))
        else
            log "✅ QB_USERNAME: $QB_USERNAME"
        fi
        
        if [ -z "$QB_PASSWORD" ]; then
            log "❌ 配置错误: 吸血模式需要设置 QB_PASSWORD"
            ((errors++))
        else
            log "✅ QB_PASSWORD: [已设置]"
        fi
    else
        log "ℹ️ 吸血模式未启用"
    fi
    
    # 检查日志目录
    if [ ! -d "$LOG_DIR" ]; then
        log "⚠️ 日志目录不存在，尝试创建: $LOG_DIR"
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            log "❌ 无法创建日志目录: $LOG_DIR"
            ((errors++))
        fi
    fi
    
    # 检查 rclone 命令
    if [ ! -x "$RCLONE_CMD" ]; then
        log "❌ rclone 不可执行: $RCLONE_CMD"
        ((errors++))
    else
        log "✅ RCLONE_CMD: $RCLONE_CMD"
    fi
    
    # 检查 rclone 配置
    if [ ! -f "$RCLONE_CONFIG" ]; then
        log "❌ rclone 配置文件不存在: $RCLONE_CONFIG"
        ((errors++))
    else
        log "✅ RCLONE_CONFIG: $RCLONE_CONFIG"
    fi
    
    # 验证重试配置
    if [ "$RCLONE_RETRIES" -lt 1 ]; then
        log "⚠️ 配置警告: RCLONE_RETRIES 应该至少为1，当前值: $RCLONE_RETRIES"
        ((warnings++))
    fi
    
    # 输出验证结果
    if [ $errors -gt 0 ]; then
        log "❌ 配置验证失败: $errors 个错误, $warnings 个警告"
        return 1
    else
        log "✅ 配置验证通过: $errors 个错误, $warnings 个警告"
        return 0
    fi
}

# =============================================================================
# 黑名单检查函数（增强版，支持删除黑名单文件）
# =============================================================================

# 安全删除文件或目录
safe_delete() {
    local path="$1"
    local reason="$2"
    
    if [ ! -e "$path" ]; then
        log "⚠️ 要删除的路径不存在: $path"
        return 0
    fi
    
    # 安全检查：确保路径在预期的下载目录内
    local safe_pattern="/downloads/"
    if [[ "$path" != *"$safe_pattern"* ]]; then
        log "❌ 安全警告: 尝试删除非下载目录内的文件: $path"
        return 1
    fi
    
    if [ -f "$path" ]; then
        if rm -f "$path"; then
            log "🗑️ 已删除文件 ($reason): $(basename "$path")"
            return 0
        else
            log "❌ 删除文件失败: $path"
            return 1
        fi
    elif [ -d "$path" ]; then
        # 对于目录，先检查是否为空
        if [ -z "$(ls -A "$path")" ]; then
            if rmdir "$path"; then
                log "🗑️ 已删除空目录 ($reason): $(basename "$path")"
                return 0
            else
                log "❌ 删除空目录失败: $path"
                return 1
            fi
        else
            log "⚠️ 目录非空，跳过删除: $path"
            return 0
        fi
    else
        log "⚠️ 未知类型的路径: $path"
        return 1
    fi
}

# 删除黑名单文件或目录
delete_blacklisted() {
    local path="$1"
    
    if [ "$DELETE_BLACKLISTED" != "true" ]; then
        log "ℹ️ 黑名单文件删除功能已禁用，跳过删除: $path"
        return 0
    fi
    
    log "🚫 开始删除黑名单内容: $path"
    
    if [ -f "$path" ]; then
        # 单个文件
        safe_delete "$path" "黑名单文件"
    elif [ -d "$path" ]; then
        # 目录 - 删除整个目录
        safe_delete "$path" "黑名单目录"
    fi
}

check_blacklist() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # 如果没有设置黑名单关键词，直接通过
    if [ -z "$BLACKLIST_KEYWORDS" ]; then
        return 1
    fi
    
    # 将关键词转换为小写进行比较（不区分大小写）
    local lower_filename=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
    local lower_keywords=$(echo "$BLACKLIST_KEYWORDS" | tr '[:upper:]' '[:lower:]')
    
    # 分割关键词为数组
    IFS=',' read -ra keywords <<< "$lower_keywords"
    
    for keyword in "${keywords[@]}"; do
        # 去除关键词前后的空格
        keyword_clean=$(echo "$keyword" | xargs)
        if [ -n "$keyword_clean" ] && [[ "$lower_filename" == *"$keyword_clean"* ]]; then
            log "🚫 文件包含黑名单关键词 '$keyword_clean': $filename"
            
            # 立即删除黑名单文件
            delete_blacklisted "$file_path"
            
            return 0  # 包含黑名单关键词
        fi
    done
    
    return 1  # 不包含黑名单关键词
}

# 检查文件夹是否包含黑名单文件
check_folder_blacklist() {
    local folder_path="$1"
    local has_blacklisted=false
    
    # 如果没有设置黑名单关键词，直接通过
    if [ -z "$BLACKLIST_KEYWORDS" ]; then
        return 1
    fi
    
    # 检查文件夹中的所有文件
    while IFS= read -r -d '' file; do
        if check_blacklist "$file"; then
            log "🚫 文件夹包含黑名单文件: $(basename "$file")"
            has_blacklisted=true
        fi
    done < <(find "$folder_path" -type f -print0 2>/dev/null)
    
    # 如果文件夹中有黑名单文件，删除整个文件夹
    if [ "$has_blacklisted" = true ] && [ "$DELETE_BLACKLISTED" = "true" ]; then
        log "🚫 文件夹包含黑名单文件，删除整个文件夹: $(basename "$folder_path")"
        delete_blacklisted "$folder_path"
        return 0  # 文件夹包含黑名单文件
    fi
    
    return 1  # 文件夹不包含黑名单文件
}

# 处理黑名单内容
process_blacklisted_content() {
    local content_path="$1"
    
    if [ -z "$BLACKLIST_KEYWORDS" ] || [ "$DELETE_BLACKLISTED" != "true" ]; then
        return 0
    fi
    
    log "🔍 检查黑名单内容: $content_path"
    
    if [ -f "$content_path" ]; then
        # 单个文件
        check_blacklist "$content_path"
    elif [ -d "$content_path" ]; then
        # 目录
        check_folder_blacklist "$content_path"
    fi
}

# =============================================================================
# 上传后验证和统计
# =============================================================================

# 初始化统计文件
init_stats_file() {
    if [ ! -f "$UPLOAD_STATS_FILE" ]; then
        cat > "$UPLOAD_STATS_FILE" << EOF
{
    "total_uploads": 0,
    "successful_uploads": 0,
    "failed_uploads": 0,
    "total_files_uploaded": 0,
    "total_size_uploaded": 0,
    "blacklisted_deleted": 0,
    "last_successful_upload": "",
    "last_failed_upload": "",
    "upload_history": []
}
EOF
        log "📊 初始化统计文件: $UPLOAD_STATS_FILE"
    fi
}

# 计算文件大小函数（兼容不同系统）
get_file_size() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        if command -v stat >/dev/null 2>&1; then
            # Linux
            stat -c%s "$file_path" 2>/dev/null || echo "0"
        elif command -v gstat >/dev/null 2>&1; then
            # macOS with gstat
            gstat -c%s "$file_path" 2>/dev/null || echo "0"
        else
            # 使用 ls 作为备选
            ls -l "$file_path" | awk '{print $5}' 2>/dev/null || echo "0"
        fi
    else
        echo "0"
    fi
}

# 格式化文件大小
format_size() {
    local size="$1"
    if command -v bc >/dev/null 2>&1 && [ "$size" -ge 1099511627776 ]; then
        echo "$(echo "scale=2; $size/1099511627776" | bc) TB"
    elif command -v bc >/dev/null 2>&1 && [ "$size" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $size/1073741824" | bc) GB"
    elif command -v bc >/dev/null 2>&1 && [ "$size" -ge 1048576 ]; then
        echo "$(echo "scale=2; $size/1048576" | bc) MB"
    elif command -v bc >/dev/null 2>&1 && [ "$size" -ge 1024 ]; then
        echo "$(echo "scale=2; $size/1024" | bc) KB"
    else
        echo "$size bytes"
    fi
}

# 上传验证函数
verify_upload() {
    local local_file="$1"
    local remote_path="$2"
    local filename=$(basename "$local_file")
    
    if [ "$VERIFY_UPLOAD" != "true" ]; then
        log "ℹ️ 上传验证已禁用，跳过验证: $filename"
        return 0
    fi
    
    log "🔍 开始验证上传文件: $filename"
    
    # 检查远程文件是否存在
    if ! $RCLONE_CMD ls "$RCLONE_DEST:$remote_path/$filename" >/dev/null 2>&1; then
        log "❌ 验证失败: 远程文件不存在 - $filename"
        return 1
    fi
    
    # 比较文件大小
    local local_size=$(get_file_size "$local_file")
    local remote_size=$($RCLONE_CMD size "$RCLONE_DEST:$remote_path/$filename" --json 2>/dev/null | jq -r '.bytes' 2>/dev/null || echo "0")
    
    if [ -z "$remote_size" ] || [ "$remote_size" = "null" ] || [ "$remote_size" -eq 0 ]; then
        log "⚠️ 无法获取远程文件大小，跳过大小验证: $filename"
        return 0
    fi
    
    if [ "$local_size" != "$remote_size" ]; then
        log "❌ 验证失败: 文件大小不匹配 - $filename"
        log "❌ 本地大小: $local_size, 远程大小: $remote_size"
        return 1
    fi
    
    log "✅ 验证通过: $filename (大小: $(format_size $local_size))"
    return 0
}

# 更新上传统计
update_upload_stats() {
    local torrent_name="$1"
    local file_count="$2"
    local total_size="$3"
    local status="$4"  # success, failed, partial, blacklisted
    local message="$5"
    
    # 确保统计文件存在
    init_stats_file
    
    # 读取当前统计
    local current_stats
    if [ -f "$UPLOAD_STATS_FILE" ]; then
        current_stats=$(cat "$UPLOAD_STATS_FILE")
    else
        current_stats='{
            "total_uploads": 0,
            "successful_uploads": 0,
            "failed_uploads": 0,
            "total_files_uploaded": 0,
            "total_size_uploaded": 0,
            "blacklisted_deleted": 0,
            "last_successful_upload": "",
            "last_failed_upload": "",
            "upload_history": []
        }'
    fi
    
    # 更新统计信息
    local new_stats=$(echo "$current_stats" | jq \
        --arg timestamp "$(date -Iseconds)" \
        --arg name "$torrent_name" \
        --argjson count "$file_count" \
        --argjson size "$total_size" \
        --arg status "$status" \
        --arg message "$message" \
        '.total_uploads += 1 |
         if $status == "success" then 
             .successful_uploads += 1 |
             .last_successful_upload = $timestamp |
             .total_files_uploaded += ($count | tonumber) |
             .total_size_uploaded += ($size | tonumber)
         elif $status == "failed" then 
             .failed_uploads += 1 |
             .last_failed_upload = $timestamp
         elif $status == "blacklisted" then
             .blacklisted_deleted += 1
         else . end |
         .upload_history += [{
             timestamp: $timestamp,
             name: $name,
             file_count: $count,
             total_size: $size,
             status: $status,
             message: $message
         }] |
         # 只保留最近100条历史记录
         if (.upload_history | length) > 100 then 
             .upload_history = .upload_history[-100:] 
         else . end')
    
    # 保存更新后的统计
    echo "$new_stats" > "$UPLOAD_STATS_FILE"
    
    # 记录统计信息
    local success_count=$(echo "$new_stats" | jq -r '.successful_uploads')
    local fail_count=$(echo "$new_stats" | jq -r '.failed_uploads')
    local blacklist_count=$(echo "$new_stats" | jq -r '.blacklisted_deleted')
    local total_files=$(echo "$new_stats" | jq -r '.total_files_uploaded')
    local total_size=$(echo "$new_stats" | jq -r '.total_size_uploaded')
    
    log "📈 统计信息已更新 - 成功: $success_count, 失败: $fail_count, 黑名单: $blacklist_count, 总文件: $total_files, 总大小: $(format_size $total_size)"
}

# 显示统计摘要
show_stats_summary() {
    if [ -f "$UPLOAD_STATS_FILE" ]; then
        local stats=$(cat "$UPLOAD_STATS_FILE")
        local total_uploads=$(echo "$stats" | jq -r '.total_uploads')
        local successful=$(echo "$stats" | jq -r '.successful_uploads')
        local failed=$(echo "$stats" | jq -r '.failed_uploads')
        local blacklisted=$(echo "$stats" | jq -r '.blacklisted_deleted')
        local total_files=$(echo "$stats" | jq -r '.total_files_uploaded')
        local total_size=$(echo "$stats" | jq -r '.total_size_uploaded')
        local success_rate=0
        
        if [ "$total_uploads" -gt 0 ]; then
            success_rate=$((successful * 100 / total_uploads))
        fi
        
        log "📊 统计摘要:"
        log "  📤 总处理任务: $total_uploads"
        log "  ✅ 成功上传: $successful"
        log "  ❌ 上传失败: $failed"
        log "  🚫 黑名单删除: $blacklisted"
        log "  📈 成功率: $success_rate%"
        log "  📄 总文件数: $total_files"
        log "  💾 总上传大小: $(format_size $total_size)"
    else
        log "ℹ️ 暂无统计信息"
    fi
}

# 主日志记录开始
log "🚀 开始处理: $1"

# 基础检查
check_basics() {
    # 检查必要参数
    if [ -z "$1" ] || [ -z "$2" ]; then
        log "❌ 缺少种子名称或内容路径"
        return 1
    fi

    # 检查路径是否存在
    if [ ! -e "$2" ]; then
        log "❌ 路径不存在: $2"
        return 1
    fi

    # 测试 rclone 连接
    log "🔧 测试 rclone 连接..."
    local rclone_test_output
    rclone_test_output=$($RCLONE_CMD lsd "$RCLONE_DEST:" 2>&1)
    local rclone_exit_code=$?
    
    if [ $rclone_exit_code -eq 0 ]; then
        log "✅ rclone 连接成功"
    else
        log "❌ rclone 连接失败，退出码: $rclone_exit_code"
        log "❌ 错误输出: $rclone_test_output"
        return 1
    fi

    log "✅ 基础检查通过"
    log "📋 配置信息: LEECHING_MODE=$LEECHING_MODE, RCLONE_DEST=$RCLONE_DEST, UPLOAD_PATH=$UPLOAD_PATH"
    log "📋 黑名单关键词: ${BLACKLIST_KEYWORDS:-无}"
    log "📋 上传验证: ${VERIFY_UPLOAD:-true}"
    log "📋 删除黑名单: ${DELETE_BLACKLISTED:-true}"
    return 0
}

# 获取要上传的文件列表（应用黑名单过滤）
get_upload_files() {
    local content_path="$1"
    local files=()

    # 首先处理黑名单内容
    process_blacklisted_content "$content_path"
    
    # 检查内容是否已被删除（由于黑名单）
    if [ ! -e "$content_path" ]; then
        log "ℹ️ 内容已被删除（黑名单）: $content_path"
        return 1
    fi

    if [ -f "$content_path" ]; then
        # 单个文件 - 检查黑名单
        if check_blacklist "$content_path"; then
            log "🚫 跳过黑名单文件: $(basename "$content_path")"
            return 1
        else
            files=("$content_path")
            log "📄 单个文件: $(basename "$content_path")"
        fi
    elif [ -d "$content_path" ]; then
        # 目录 - 先检查整个文件夹是否包含黑名单文件
        if check_folder_blacklist "$content_path"; then
            log "🚫 跳过包含黑名单文件的文件夹: $(basename "$content_path")"
            return 1
        fi
        
        # 文件夹中没有黑名单文件，获取所有文件
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$content_path" -type f -print0 2>/dev/null)
        log "📁 目录文件数: ${#files[@]}"
    else
        log "❌ 路径既不是文件也不是目录: $content_path"
        return 1
    fi

    # 正确返回文件数组
    printf '%s\0' "${files[@]}"
}

# 上传文件（带重试机制和验证）
upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0
    local total=${#files[@]}
    local total_size=0

    log "📤 开始上传 $total 个文件到: $upload_path"

    # 计算总大小
    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            local file_size=$(get_file_size "$file_path")
            total_size=$((total_size + file_size))
        fi
    done

    log "💾 总上传大小: $(format_size $total_size)"

    for file_path in "${files[@]}"; do
        # 检查文件是否存在
        if [ ! -f "$file_path" ]; then
            log "❌ 文件不存在，跳过: $file_path"
            continue
        fi
        
        local filename=$(basename "$file_path")
        local retry_count=0
        local upload_success=false
        
        while [ $retry_count -lt $RCLONE_RETRIES ]; do
            log "🔄 尝试上传 ($((retry_count+1))/$RCLONE_RETRIES): $filename"
            
            if $RCLONE_CMD copy --progress "$file_path" "$RCLONE_DEST:$upload_path/" >> "$LOG_DIR/rclone.log" 2>&1; then
                # 上传成功，进行验证
                if verify_upload "$file_path" "$upload_path"; then
                    log "✅ 上传成功: $filename"
                    upload_success=true
                    ((success++))
                    break
                else
                    log "❌ 上传验证失败: $filename"
                    upload_success=false
                fi
            else
                log "❌ 上传失败: $filename (尝试 $((retry_count+1))/$RCLONE_RETRIES)"
                upload_success=false
            fi
            
            ((retry_count++))
            if [ $retry_count -lt $RCLONE_RETRIES ]; then
                log "⏳ 等待 $RCLONE_RETRY_DELAY 后重试..."
                sleep $RCLONE_RETRY_DELAY
            fi
        done
        
        if [ "$upload_success" = "false" ]; then
            log "💥 最终上传失败: $filename"
        fi
    done

    log "📊 上传完成: $success/$total 成功"
    [ $success -eq $total ]
}

# 获取十六进制哈希值
get_hex_hash() {
    local torrent_name="$1"
    local content_dir="$2"
    shift 2

    log "🔍 开始获取种子哈希值"
    
    # 方法1: 遍历所有参数寻找40位十六进制哈希
    local i=1
    for arg in "$@"; do
        if [[ "$arg" =~ ^[a-fA-F0-9]{40}$ ]]; then
            log "✅ 从参数$i获取到十六进制哈希: $arg"
            echo "$arg"
            return 0
        fi
        ((i++))
    done

    # 方法2: 尝试从qBittorrent API获取哈希值
    if [ -n "$QB_WEB_URL" ] && [ -n "$QB_USERNAME" ] && [ -n "$QB_PASSWORD" ]; then
        log "🔑 尝试通过API获取哈希值"
        local cookie_file="$LOG_DIR/qb_cookie.txt"
        
        # 登录qBittorrent
        local login_result
        login_result=$(curl -s -c "$cookie_file" -X POST \
            --data-urlencode "username=$QB_USERNAME" \
            --data-urlencode "password=$QB_PASSWORD" \
            "$QB_WEB_URL/api/v2/auth/login" 2>&1)
        
        local login_exit_code=$?
        
        if [ $login_exit_code -eq 0 ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
            log "✅ API登录成功"
            
            # 获取种子列表并查找匹配的种子
            local torrent_list=$(curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/torrents/info" 2>&1)
            local hex_hash=$(echo "$torrent_list" | \
                jq -r --arg name "$torrent_name" --arg path "$(dirname "$content_dir")" \
                '.[] | select(.name == $name and .save_path == $path) | .hash' 2>/dev/null)
            
            rm -f "$cookie_file"
            
            if [ -n "$hex_hash" ] && [ "$hex_hash" != "null" ]; then
                log "✅ 通过API获取到哈希值: $hex_hash"
                echo "$hex_hash"
                return 0
            else
                log "❌ API未找到匹配的种子"
            fi
        else
            log "❌ API登录失败，退出码: $login_exit_code"
            log "❌ 登录响应: $login_result"
        fi
    else
        log "⚠️ 缺少API配置信息，跳过API获取"
    fi
    
    # 方法3: 生成基于名称和路径的伪哈希
    local fallback_hash=$(echo -n "${torrent_name}${content_dir}" | sha1sum | cut -d' ' -f1)
    log "⚠️ 所有方法失败，使用回退哈希: $fallback_hash"
    echo "$fallback_hash"
}

# 处理种子（吸血模式）- 增强版本
process_torrent() {
    if [ "$LEECHING_MODE" != "true" ]; then
        log "ℹ️ 吸血模式未启用，跳过种子处理"
        return 0
    fi

    local torrent_hash="$1"
    
    if [ -z "$torrent_hash" ]; then
        log "❌ 吸血模式需要种子哈希值，但获取到的哈希值为空"
        return 1
    fi
    
    log "🔧 开始吸血模式处理，种子哈希: $torrent_hash"
    
    # 检查必要的API配置
    if [ -z "$QB_WEB_URL" ] || [ -z "$QB_USERNAME" ] || [ -z "$QB_PASSWORD" ]; then
        log "❌ 吸血模式需要设置 QB_WEB_URL, QB_USERNAME, QB_PASSWORD"
        return 1
    fi

    local cookie_file="$LOG_DIR/qb_cookie.txt"
    
    # 登录 qBittorrent - 增强错误处理
    log "🔑 尝试登录qBittorrent..."
    local login_response
    login_response=$(curl -s -w "%{http_code}" -c "$cookie_file" -X POST \
        --data-urlencode "username=$QB_USERNAME" \
        --data-urlencode "password=$QB_PASSWORD" \
        "$QB_WEB_URL/api/v2/auth/login" 2>&1)
    
    local http_code="${login_response: -3}"
    local response_body="${login_response%???}"
    
    log "🔧 登录响应状态码: $http_code"
    
    if [ "$http_code" = "200" ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
        log "✅ 登录成功，准备删除种子"
        
        # 删除种子（使用十六进制哈希）
        log "🗑️ 发送删除请求，哈希: $torrent_hash"
        local delete_response
        delete_response=$(curl -s -w "%{http_code}" -b "$cookie_file" -X POST \
            --data-urlencode "hashes=$torrent_hash" \
            --data-urlencode "deleteFiles=true" \
            "$QB_WEB_URL/api/v2/torrents/delete" 2>&1)
        
        local delete_http_code="${delete_response: -3}"
        
        log "🔧 删除响应状态码: $delete_http_code"
        
        if [ "$delete_http_code" = "200" ]; then
            log "✅ 种子删除请求发送成功"
            
            # 验证种子是否真的被删除
            sleep 2
            local verify_response=$(curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/torrents/info")
            if echo "$verify_response" | jq -e --arg hash "$torrent_hash" '.[] | select(.hash == $hash)' >/dev/null 2>&1; then
                log "❌ 种子仍然存在，删除可能失败"
            else
                log "✅ 种子确认已删除"
            fi
        else
            log "❌ 种子删除请求失败，HTTP状态码: $delete_http_code"
            log "❌ 删除响应: ${delete_response%???}"
        fi
        
        # 登出
        curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/auth/logout" >/dev/null 2>&1
        rm -f "$cookie_file"
    else
        log "❌ 登录失败，HTTP状态码: $http_code"
        log "❌ 登录响应: $response_body"
        log "🔧 检查项目:"
        log "  - QB_WEB_URL: $QB_WEB_URL"
        log "  - QB_USERNAME: $QB_USERNAME"
        log "  - QB_PASSWORD: [已设置]"
        log "  - WebUI是否启用: 请检查qBittorrent设置"
        return 1
    fi
    
    log "🔧 吸血模式处理完成"
    return 0
}

# 主流程
main() {
    local torrent_name="$1"
    local content_dir="$2"
    
    log "🎯 主流程开始"
    log "📝 输入参数: 名称='$torrent_name', 路径='$content_dir'"
    
    # 配置验证
    if ! validate_config; then
        log "❌ 配置验证失败，请检查配置文件"
        exit 1
    fi
    
    # 显示当前统计摘要
    show_stats_summary

    # 基础检查
    if ! check_basics "$torrent_name" "$content_dir"; then
        log "❌ 基础检查失败"
        update_upload_stats "$torrent_name" "0" "0" "failed" "基础检查失败"
        exit 1
    fi

    # 获取十六进制哈希值
    log "🔍 正在获取哈希值..."
    local torrent_hash
    torrent_hash=$(get_hex_hash "$torrent_name" "$content_dir" "$@")
    
    # 检查哈希值是否为空
    if [ -z "$torrent_hash" ]; then
        log "❌ 错误：获取到的哈希值为空"
        update_upload_stats "$torrent_name" "0" "0" "failed" "获取哈希值失败"
        exit 3
    fi
    
    log "🔐 使用的哈希值: $torrent_hash"

    # 获取文件列表（已应用黑名单过滤）
    local files
    mapfile -d '' files < <(get_upload_files "$content_dir")
    
    # 检查内容是否因黑名单而被完全删除
    if [ ! -e "$content_dir" ]; then
        log "🚫 内容已被完全删除（黑名单）: $torrent_name"
        update_upload_stats "$torrent_name" "0" "0" "blacklisted" "内容包含黑名单关键词，已删除"
        
        # 即使没有文件上传，如果是吸血模式且获取到了哈希值，仍然删除种子
        if [ "$LEECHING_MODE" = "true" ] && [ -n "$torrent_hash" ]; then
            log "🔄 内容已被黑名单删除，但吸血模式已启用，尝试删除种子..."
            if process_torrent "$torrent_hash"; then
                log "🎉 种子已删除（黑名单内容）"
            else
                log "⚠️ 种子删除失败（黑名单内容）"
            fi
        fi
        exit 0
    fi
    
    if [ ${#files[@]} -eq 0 ]; then
        log "🚫 没有找到可上传的文件（可能被黑名单过滤）"
        update_upload_stats "$torrent_name" "0" "0" "blacklisted" "没有找到可上传的文件（黑名单过滤）"
        # 即使没有文件上传，如果是吸血模式且获取到了哈希值，仍然删除种子
        if [ "$LEECHING_MODE" = "true" ] && [ -n "$torrent_hash" ]; then
            log "🔄 没有文件需要上传，但吸血模式已启用，尝试删除种子..."
            if process_torrent "$torrent_hash"; then
                log "🎉 种子已删除（无文件上传）"
            else
                log "⚠️ 种子删除失败（无文件上传）"
            fi
        fi
        exit 0
    fi

    # 计算总文件大小
    local total_size=0
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local size=$(get_file_size "$file")
            total_size=$((total_size + size))
        fi
    done

    # 上传文件
    if upload_files "${files[@]}"; then
        log "✅ 所有文件上传成功"
        update_upload_stats "$torrent_name" "${#files[@]}" "$total_size" "success" "所有文件上传成功"
        log "🔄 开始处理种子..."
        if process_torrent "$torrent_hash"; then
            log "🎉 任务完成 - 种子已删除"
        else
            log "⚠️ 任务完成 - 但种子删除失败"
        fi
    else
        log "❌ 部分文件上传失败，跳过种子处理"
        update_upload_stats "$torrent_name" "${#files[@]}" "$total_size" "failed" "部分文件上传失败"
        exit 1
    fi
    
    # 显示更新后的统计
    show_stats_summary
}

# 运行主程序
main "$@"
