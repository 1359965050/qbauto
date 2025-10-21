#!/bin/bash

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

# 设置默认值
LOG_DIR="${LOG_DIR:-/config/qbauto/log}"
RCLONE_CMD="${RCLONE_CMD:-/usr/bin/rclone}"
LEECHING_MODE="${LEECHING_MODE:-false}"

# 初始化日志目录
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qbauto.log"

# 简化日志函数
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    echo "$message" >&2
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

    # 检查 rclone
    if [ ! -x "$RCLONE_CMD" ]; then
        log "❌ rclone 不可执行: $RCLONE_CMD"
        return 1
    fi

    # 检查必要配置
    if [ -z "$RCLONE_DEST" ] || [ -z "$UPLOAD_PATH" ]; then
        log "❌ 缺少 RCLONE_DEST 或 UPLOAD_PATH 配置"
        return 1
    fi

    # 测试 rclone 连接
    if ! $RCLONE_CMD lsd "$RCLONE_DEST:" >/dev/null 2>&1; then
        log "❌ rclone 连接失败"
        return 1
    fi

    log "✅ 基础检查通过"
    log "📋 配置信息: LEECHING_MODE=$LEECHING_MODE, RCLONE_DEST=$RCLONE_DEST, UPLOAD_PATH=$UPLOAD_PATH"
    return 0
}

# 获取要上传的文件列表
get_upload_files() {
    local content_path="$1"
    local files=()

    if [ -f "$content_path" ]; then
        # 单个文件
        files=("$content_path")
        log "📄 单个文件: $(basename "$content_path")"
    elif [ -d "$content_path" ]; then
        # 目录中的所有文件
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

# 上传文件
upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0
    local total=${#files[@]}

    log "📤 开始上传 $total 个文件到: $upload_path"

    for file_path in "${files[@]}"; do
        # 检查文件是否存在
        if [ ! -f "$file_path" ]; then
            log "❌ 文件不存在，跳过: $file_path"
            continue
        fi
        
        local filename=$(basename "$file_path")
        log "正在上传: $filename"
        
        if $RCLONE_CMD copy --progress "$file_path" "$RCLONE_DEST:$upload_path/" >> "$LOG_DIR/rclone.log" 2>&1; then
            log "✅ 上传成功: $filename"
            ((success++))
        else
            log "❌ 上传失败: $filename"
        fi
    done

    log "📊 上传完成: $success/$total 成功"
    [ $success -eq $total ]
}

# 获取十六进制哈希值 - 简化版本
get_hex_hash() {
    local torrent_name="$1"
    local content_dir="$2"
    shift 2  # 移除前两个参数，剩下的就是额外参数
    
    log "🔍 开始获取种子哈希值"
    log "🔍 种子名称: $torrent_name"
    log "🔍 内容路径: $content_dir"
    log "🔍 剩余参数数量: $#"
    
    # 输出所有剩余参数用于调试
    local i=1
    for arg in "$@"; do
        log "🔍 参数$i: $arg"
        ((i++))
    done

    # 方法1: 直接检查第6个参数（索引从0开始，现在是第3个参数）
    if [ $# -ge 6 ] && [ -n "${6}" ]; then
        local param_hash="${6}"
        log "🔑 检查第6个参数的哈希值: $param_hash"
        # 检查是否是有效的十六进制字符串（40字符的SHA1哈希）
        if [[ "$param_hash" =~ ^[a-fA-F0-9]{40}$ ]]; then
            log "✅ 从参数获取到十六进制哈希: $param_hash"
            echo "$param_hash"
            return 0
        else
            log "❌ 第6个参数不是有效的40位十六进制哈希"
        fi
    fi

    # 方法2: 遍历所有参数寻找哈希值
    local i=1
    for arg in "$@"; do
        if [[ "$arg" =~ ^[a-fA-F0-9]{40}$ ]]; then
            log "✅ 从参数$i获取到十六进制哈希: $arg"
            echo "$arg"
            return 0
        fi
        ((i++))
    done

    # 方法3: 尝试从qBittorrent API获取哈希值
    if [ -n "$QB_WEB_URL" ] && [ -n "$QB_USERNAME" ] && [ -n "$QB_PASSWORD" ]; then
        log "🔑 尝试通过API获取哈希值"
        local cookie_file="$LOG_DIR/qb_cookie.txt"
        
        # 登录qBittorrent
        if curl -s -c "$cookie_file" -X POST \
            --data-urlencode "username=$QB_USERNAME" \
            --data-urlencode "password=$QB_PASSWORD" \
            "$QB_WEB_URL/api/v2/auth/login" >/dev/null 2>&1; then
            
            log "✅ API登录成功"
            
            # 获取种子列表并查找匹配的种子
            local torrent_list=$(curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/torrents/info")
            local hex_hash=$(echo "$torrent_list" | \
                jq -r --arg name "$torrent_name" --arg path "$content_dir" \
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
            log "❌ API登录失败"
        fi
    else
        log "⚠️ 缺少API配置信息，跳过API获取"
    fi
    
    # 方法4: 如果以上都失败，生成基于名称和路径的伪哈希
    local fallback_hash=$(echo -n "${torrent_name}${content_dir}" | sha1sum | cut -d' ' -f1)
    log "⚠️ 所有方法失败，使用回退哈希: $fallback_hash"
    echo "$fallback_hash"
}

# 处理种子（吸血模式）
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
    
    # 登录 qBittorrent
    log "🔑 尝试登录qBittorrent..."
    local login_response=$(curl -s -c "$cookie_file" -X POST \
        --data-urlencode "username=$QB_USERNAME" \
        --data-urlencode "password=$QB_PASSWORD" \
        "$QB_WEB_URL/api/v2/auth/login")
    
    if [ $? -eq 0 ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
        log "✅ 登录成功，准备删除种子"
        
        # 删除种子（使用十六进制哈希）
        log "🗑️ 发送删除请求，哈希: $torrent_hash"
        local delete_response=$(curl -s -b "$cookie_file" -X POST \
            --data-urlencode "hashes=$torrent_hash" \
            --data-urlencode "deleteFiles=true" \
            "$QB_WEB_URL/api/v2/torrents/delete")
        
        local curl_exit_code=$?
        
        if [ $curl_exit_code -eq 0 ]; then
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
            log "❌ 种子删除请求失败，curl退出码: $curl_exit_code"
        fi
        
        # 登出
        curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/auth/logout" >/dev/null 2>&1
        rm -f "$cookie_file"
    else
        log "❌ 登录失败"
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
    
    # 基础检查
    if ! check_basics "$torrent_name" "$content_dir"; then
        log "❌ 基础检查失败"
        exit 1
    fi

    # 获取十六进制哈希值 - 传递所有参数
    log "🔍 正在获取哈希值..."
    local torrent_hash
    torrent_hash=$(get_hex_hash "$torrent_name" "$content_dir" "$@")
    
    # 检查哈希值是否为空
    if [ -z "$torrent_hash" ]; then
        log "❌ 错误：获取到的哈希值为空"
        exit 3
    fi
    
    log "🔐 使用的哈希值: $torrent_hash"

    # 获取文件列表
    local files
    mapfile -d '' files < <(get_upload_files "$content_dir")
    
    if [ ${#files[@]} -eq 0 ]; then
        log "🚫 没有找到可上传的文件"
        exit 2
    fi

    log "📋 实际文件列表:"
    for file in "${files[@]}"; do
        log "  - $file"
    done

    # 上传文件
    if upload_files "${files[@]}"; then
        log "✅ 所有文件上传成功"
        log "🔄 开始处理种子..."
        if process_torrent "$torrent_hash"; then
            log "🎉 任务完成 - 种子已删除"
        else
            log "⚠️ 任务完成 - 但种子删除失败"
        fi
    else
        log "❌ 部分文件上传失败，跳过种子处理"
        exit 1
    fi
}

# 运行主程序
main "$@"
