#!/bin/bash

# =============================================================================
# 配置管理模块
# 功能：加载、验证和管理配置文件
# =============================================================================

# 清理和验证配置文件
clean_config_file() {
    local input_file="$1"
    local output_file="$2"
    
    # 删除注释行和空行，只保留有效的变量赋值
    grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$input_file" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$output_file"
    
    # 检查是否提取到了有效的配置
    if [ ! -s "$output_file" ]; then
        log "❌ 配置文件中没有找到有效的变量赋值"
        return 1
    fi
    
    log "✅ 配置文件清理完成，找到 $(wc -l < "$output_file") 个有效配置项"
    return 0
}

# 加载配置
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误：配置文件不存在: $CONFIG_FILE" >&2
        return 1
    fi

    # 清理配置文件，只保留有效的变量赋值
    local clean_config="/tmp/qbauto_clean.conf"
    if ! clean_config_file "$CONFIG_FILE" "$clean_config"; then
        return 1
    fi

    # 加载清理后的配置
    source "$clean_config"

    # 设置默认值
    LOG_DIR="${LOG_DIR:-/config/qbauto/log}"
    RCLONE_CMD="${RCLONE_CMD:-/usr/bin/rclone}"
    LEECHING_MODE="${LEECHING_MODE:-false}"
    RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
    RCLONE_RETRY_DELAY="${RCLONE_RETRY_DELAY:-10s}"
    BLACKLIST_KEYWORDS="${BLACKLIST_KEYWORDS:-}"
    VERIFY_UPLOAD="${VERIFY_UPLOAD:-true}"
    UPLOAD_STATS_FILE="${UPLOAD_STATS_FILE:-$LOG_DIR/upload_stats.json}"
    DELETE_BLACKLISTED="${DELETE_BLACKLISTED:-true}"

    # 智能重试配置
    ADAPTIVE_RETRY="${ADAPTIVE_RETRY:-true}"
    MAX_RETRY_DELAY="${MAX_RETRY_DELAY:-300s}"
    RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"

    # 网络质量检测配置
    NETWORK_CHECK_TIMEOUT="${NETWORK_CHECK_TIMEOUT:-30}"
    MIN_UPLOAD_SPEED="${MIN_UPLOAD_SPEED:-1}"
    ENABLE_NETWORK_CHECK="${ENABLE_NETWORK_CHECK:-true}"

    # 存储空间管理配置
    LOCAL_MIN_FREE="${LOCAL_MIN_FREE:-1G}"
    REMOTE_MIN_FREE="${REMOTE_MIN_FREE:-5G}"
    ENABLE_SPACE_CHECK="${ENABLE_SPACE_CHECK:-true}"

    # 性能监控配置
    PERFORMANCE_LOG="${PERFORMANCE_LOG:-$LOG_DIR/performance.csv}"
    ENABLE_PERFORMANCE_MONITORING="${ENABLE_PERFORMANCE_MONITORING:-true}"

    # 系统健康检查配置
    MAX_LOG_FILES="${MAX_LOG_FILES:-10}"
    ENABLE_HEALTH_CHECK="${ENABLE_HEALTH_CHECK:-true}"
    # 通知配置
    NOTIFY_ENABLE="${NOTIFY_ENABLE:-false}"
    NOTIFY_TITLE="${NOTIFY_TITLE:-qBittorrent 自动上传}"
    NOTIFY_STATS_ENABLE="${NOTIFY_STATS_ENABLE:-false}"
    TELEGRAM_ENABLE="${TELEGRAM_ENABLE:-false}"
    TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
    TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
    SERVERCHAN_ENABLE="${SERVERCHAN_ENABLE:-false}"
    SERVERCHAN_SCKEY="${SERVERCHAN_SCKEY:-}"

    # 文件类型过滤配置
    FILE_FILTER_ENABLE="${FILE_FILTER_ENABLE:-false}"
    FILE_FILTER_MODE="${FILE_FILTER_MODE:-allow}"
    FILE_FILTER_TYPES="${FILE_FILTER_TYPES:-mp4,mkv,avi,mov,flv,webm,mp3,flac,wav,aac}"

    # 初始化日志目录
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/qbauto.log"

    # 记录加载的配置
    log "✅ 配置加载完成"
    log "📋 主要配置: RCLONE_DEST=$RCLONE_DEST, UPLOAD_PATH=$UPLOAD_PATH, LEECHING_MODE=$LEECHING_MODE"

    return 0
}

# API 连接测试函数
test_qbittorrent_api() {
    local cookie_file="$LOG_DIR/test_cookie.txt"
    local test_result
    
    rm -f "$cookie_file"
    
    test_result=$(curl -s -w "%{http_code}" -c "$cookie_file" -X POST \
        --data-urlencode "username=$QB_USERNAME" \
        --data-urlencode "password=$QB_PASSWORD" \
        "$QB_WEB_URL/api/v2/auth/login" 2>&1)
    
    local http_code="${test_result: -3}"
    
    if [ "$http_code" = "200" ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file" ]; then
        # 登出
        curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/auth/logout" >/dev/null 2>&1
        rm -f "$cookie_file"
        log "✅ qBittorrent API 连接成功"
        return 0
    else
        log "❌ qBittorrent API 连接失败，HTTP状态码: $http_code"
        return 1
    fi
}

# Rclone 配置测试函数
test_rclone_config() {
    log "🔧 测试 Rclone 配置..."
    
    # 检查配置文件是否存在
    if [ ! -f "$RCLONE_CONFIG" ]; then
        log "❌ Rclone 配置文件不存在: $RCLONE_CONFIG"
        return 1
    fi
    
    # 检查配置文件中是否包含指定的远程存储
    if ! grep -q "^\[$RCLONE_DEST\]" "$RCLONE_CONFIG"; then
        log "❌ Rclone 配置文件中未找到远程存储: $RCLONE_DEST"
        log "🔍 配置文件 $RCLONE_CONFIG 中可用的远程存储:"
        grep "^\[.*\]" "$RCLONE_CONFIG" | sed 's/\[//g' | sed 's/\]//g' | while read remote; do
            log "  - $remote"
        done
        return 1
    fi
    
    # 测试连接
    local test_result
    test_result=$($RCLONE_CMD --config "$RCLONE_CONFIG" lsd "$RCLONE_DEST:" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "✅ Rclone 配置测试成功"
        return 0
    else
        log "❌ Rclone 配置测试失败，退出码: $exit_code"
        log "❌ 错误信息: $test_result"
        return 1
    fi
}

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
    
    # 检查 Rclone 配置
    log "🔧 检查 Rclone 配置..."
    if [ -z "$RCLONE_CONFIG" ]; then
        log "❌ 配置错误: RCLONE_CONFIG 未设置"
        ((errors++))
    else
        log "✅ RCLONE_CONFIG: $RCLONE_CONFIG"
        if [ ! -f "$RCLONE_CONFIG" ]; then
            log "❌ Rclone 配置文件不存在: $RCLONE_CONFIG"
            ((errors++))
        else
            log "✅ Rclone 配置文件存在"
        fi
    fi
    
    # 测试 Rclone 配置
    if [ $errors -eq 0 ] && [ -f "$RCLONE_CONFIG" ]; then
        if ! test_rclone_config; then
            ((errors++))
        fi
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
    
    # 验证重试配置
    if [ "$RCLONE_RETRIES" -lt 1 ]; then
        log "⚠️ 配置警告: RCLONE_RETRIES 应该至少为1，当前值: $RCLONE_RETRIES"
        ((warnings++))
    fi
    
    # 检查必要的工具
    local required_tools=("jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "❌ 必要工具缺失: $tool"
            ((errors++))
        else
            log "✅ 工具可用: $tool"
        fi
    done
    
    # 验证上传路径格式
    if [[ "$UPLOAD_PATH" =~ \.\. ]]; then
        log "❌ 上传路径包含非法字符: .."
        ((errors++))
    fi
    
    # 验证智能重试配置
    if [ "$ADAPTIVE_RETRY" = "true" ]; then
        if [ "$(echo "$MAX_RETRY_DELAY" | sed 's/s//')" -lt "$(echo "$RCLONE_RETRY_DELAY" | sed 's/s//')" ]; then
            log "⚠️ 配置警告: MAX_RETRY_DELAY 应该大于 RCLONE_RETRY_DELAY"
            ((warnings++))
        fi
        log "✅ 智能重试已启用: 初始延迟=$RCLONE_RETRY_DELAY, 最大延迟=$MAX_RETRY_DELAY, 退避倍数=$RETRY_BACKOFF_MULTIPLIER"
    fi
    
    # 验证网络检查配置
    if [ "$ENABLE_NETWORK_CHECK" = "true" ]; then
        log "✅ 网络质量检测已启用"
        if [ "$(echo "$MIN_UPLOAD_SPEED" | awk '{print int($1)}')" -lt 1 ]; then
            log "⚠️ 配置警告: MIN_UPLOAD_SPEED 设置过低: ${MIN_UPLOAD_SPEED}MB/s"
            ((warnings++))
        fi
    fi
    
    # 验证存储空间检查配置
    if [ "$ENABLE_SPACE_CHECK" = "true" ]; then
        log "✅ 存储空间检查已启用: 本地最小=${LOCAL_MIN_FREE}, 远程最小=${REMOTE_MIN_FREE}"
    fi
    
    # 验证性能监控配置
    if [ "$ENABLE_PERFORMANCE_MONITORING" = "true" ]; then
        log "✅ 性能监控已启用"
    fi
    
    # 验证健康检查配置
    if [ "$ENABLE_HEALTH_CHECK" = "true" ]; then
        log "✅ 系统健康检查已启用"
    fi
    
    # 测试 API 连接（如果启用吸血模式）
    if [ "$LEECHING_MODE" = "true" ]; then
        if ! test_qbittorrent_api; then
            log "❌ qBittorrent API 连接测试失败"
            ((errors++))
        fi
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