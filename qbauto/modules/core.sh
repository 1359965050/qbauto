#!/bin/bash

# =============================================================================
# 核心功能模块
# 功能：提供基础工具函数和共享变量
# =============================================================================

# 全局变量声明
declare -g SCRIPT_DIR MODULES_DIR CONFIG_FILE
declare -g LOG_DIR LOG_FILE RCLONE_CMD RCLONE_CONFIG
declare -g RCLONE_DEST UPLOAD_PATH LEECHING_MODE
declare -g QB_WEB_URL QB_USERNAME QB_PASSWORD

# 计算文件大小
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

# 基础检查函数
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
    
    # 确保 RCLONE_CONFIG 环境变量已设置
    if [ -z "$RCLONE_CONFIG" ]; then
        log "❌ RCLONE_CONFIG 环境变量未设置"
        return 1
    fi
    
    # 使用显式的 --config 参数
    rclone_test_output=$($RCLONE_CMD --config "$RCLONE_CONFIG" lsd "$RCLONE_DEST:" 2>&1)
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