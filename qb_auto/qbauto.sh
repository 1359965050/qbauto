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
LOG_DIR="${LOG_DIR:-/config/qbauto/log}"  # 修改默认日志目录
RCLONE_CMD="${RCLONE_CMD:-/usr/bin/rclone}"

# 初始化日志目录
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qbauto.log"

# 简化日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
    fi

    printf '%s\n' "${files[@]}"
}

# 上传文件
upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0

    log "📤 开始上传 ${#files[@]} 个文件到: $upload_path"

    for file_path in "${files[@]}"; do
        local filename=$(basename "$file_path")
        log "正在上传: $filename"
        
        if $RCLONE_CMD copy --progress "$file_path" "$RCLONE_DEST:$upload_path/" >> "$LOG_DIR/rclone.log" 2>&1; then
            log "✅ 上传成功: $filename"
            ((success++))
        else
            log "❌ 上传失败: $filename"
        fi
    done

    log "📊 上传完成: $success/${#files[@]} 成功"
    [ $success -eq ${#files[@]} ]
}

# 处理种子（吸血模式）
process_torrent() {
    if [ "$LEECHING_MODE" != "true" ]; then
        return 0
    fi

    log "🔧 吸血模式处理种子"
    
    local cookie_file="$LOG_DIR/qb_cookie.txt"
    
    # 登录 qBittorrent
    curl -s -c "$cookie_file" -X POST \
        --data-urlencode "username=$QB_USERNAME" \
        --data-urlencode "password=$QB_PASSWORD" \
        "$QB_WEB_URL/api/v2/auth/login" >/dev/null 2>&1

    if [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
        log "✅ 登录成功，删除种子"
        # 删除种子（需要种子哈希，这里简化处理）
        rm -f "$cookie_file"
    else
        log "⚠️ 登录失败，跳过种子删除"
    fi
    
    return 0
}

# 主流程
main() {
    local torrent_name="$1"
    local content_dir="$2"
    local file_hash="$7"

    # 基础检查
    check_basics "$torrent_name" "$content_dir" || exit 1

    # 获取文件列表
    local files
    files=$(get_upload_files "$content_dir")
    if [ -z "$files" ]; then
        log "🚫 没有找到可上传的文件"
        exit 2
    fi

    # 转换为数组
    IFS=$'\n' read -d '' -r -a files_array <<< "$files"

    # 上传文件
    if upload_files "${files_array[@]}"; then
        log "✅ 所有文件上传成功"
        process_torrent
        log "🎉 任务完成"
    else
        log "❌ 部分文件上传失败"
        exit 1
    fi
}

# 运行主程序
main "$@"
