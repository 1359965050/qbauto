#!/bin/bash

# =============================================================================
# 通知模块
# 功能：支持 Telegram、Server 酱和 Server 酱 Turbo 版通知
# =============================================================================

# 初始化通知系统
init_notify() {
    if [ "$NOTIFY_ENABLE" != "true" ]; then
        log "ℹ️ 通知功能已禁用"
        return 0
    fi
    
    # 检查必要的配置
    if [ -z "$NOTIFY_TITLE" ]; then
        NOTIFY_TITLE="qBittorrent 自动上传"
    fi
    
    # 设置默认的任务类型推送配置
    if [ -z "$NOTIFY_PROCESS_START" ]; then
        NOTIFY_PROCESS_START="true"
    fi
    if [ -z "$NOTIFY_UPLOAD_SUCCESS" ]; then
        NOTIFY_UPLOAD_SUCCESS="true"
    fi
    if [ -z "$NOTIFY_UPLOAD_FAILED" ]; then
        NOTIFY_UPLOAD_FAILED="true"
    fi
    if [ -z "$NOTIFY_BLACKLISTED" ]; then
        NOTIFY_BLACKLISTED="true"
    fi
    if [ -z "$NOTIFY_SYSTEM_STATUS" ]; then
        NOTIFY_SYSTEM_STATUS="false"
    fi
    if [ -z "$NOTIFY_STATS_SUMMARY" ]; then
        NOTIFY_STATS_SUMMARY="false"
    fi
    
    # 检查通知渠道配置
    local has_channel=false
    
    if [ "$TELEGRAM_ENABLE" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        log "✅ Telegram 通知已配置"
        has_channel=true
    fi
    
    if [ "$SERVERCHAN_ENABLE" = "true" ] && [ -n "$SERVERCHAN_SENDKEY" ]; then
        log "✅ Server 酱通知已配置"
        has_channel=true
    fi
    
    if [ "$SERVERCHAN_TURBO_ENABLE" = "true" ] && [ -n "$SERVERCHAN_TURBO_SENDKEY" ]; then
        log "✅ Server 酱 Turbo 版通知已配置"
        has_channel=true
    fi
    
    if [ "$has_channel" = "false" ]; then
        log "⚠️ 通知已启用但未配置任何通知渠道"
        return 1
    fi
    
    log "✅ 通知系统初始化完成"
    log "📋 任务类型推送配置:"
    log "  - 开始处理: $NOTIFY_PROCESS_START"
    log "  - 上传成功: $NOTIFY_UPLOAD_SUCCESS"
    log "  - 上传失败: $NOTIFY_UPLOAD_FAILED"
    log "  - 黑名单删除: $NOTIFY_BLACKLISTED"
    log "  - 系统状态: $NOTIFY_SYSTEM_STATUS"
    log "  - 统计摘要: $NOTIFY_STATS_SUMMARY"
    
    return 0
}

# 发送 Telegram 通知
send_telegram_notify() {
    local message="$1"
    local silent="${2:-false}"
    
    if [ "$TELEGRAM_ENABLE" != "true" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 1
    fi
    
    local telegram_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local silent_param=""
    
    if [ "$silent" = "true" ]; then
        silent_param="&disable_notification=true"
    fi
    
    local response=$(curl -s -X POST "$telegram_url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" \
        $silent_param)
    
    if echo "$response" | grep -q '"ok":true'; then
        log "✅ Telegram 通知发送成功"
        return 0
    else
        log "❌ Telegram 通知发送失败: $response"
        return 1
    fi
}

# 发送 Server 酱通知（旧版）
send_serverchan_notify() {
    local title="$1"
    local message="$2"
    
    if [ "$SERVERCHAN_ENABLE" != "true" ] || [ -z "$SERVERCHAN_SENDKEY" ]; then
        return 1
    fi
    
    # Server 酱旧版 URL 格式: https://<sendkey>.push.ft07.com/send
    local serverchan_url="https://${SERVERCHAN_SENDKEY}.push.ft07.com/send"
    
    log "🔗 调用 Server 酱 URL: $serverchan_url"
    
    # 使用 POST 请求，JSON 格式（推荐方式）
    local json_data=$(jq -n \
        --arg title "$title" \
        --arg desp "$message" \
        '{
            title: $title,
            desp: $desp
        }' 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$json_data" ]; then
        # 使用 JSON 格式发送
        local response=$(curl -s -X POST "$serverchan_url" \
            -H "Content-Type: application/json;charset=utf-8" \
            -d "$json_data")
    else
        # 回退到表单格式
        log "⚠️ JSON 生成失败，使用表单格式"
        local response=$(curl -s -X POST "$serverchan_url" \
            -d "title=$title" \
            -d "desp=$message")
    fi
    
    # 调试信息
    log "🔍 Server 酱响应: $response"
    
    # 检查响应 - 旧版返回 errno: 0 表示成功
    if echo "$response" | grep -q '"errno":0'; then
        log "✅ Server 酱通知发送成功"
        return 0
    elif echo "$response" | grep -q '"code":0'; then
        log "✅ Server 酱通知发送成功 (code格式)"
        return 0
    else
        log "❌ Server 酱通知发送失败: $response"
        
        # 尝试 GET 方法作为备选
        log "🔄 尝试使用 GET 方法..."
        local encoded_title=$(echo "$title" | sed 's/ /%20/g; s/&/%26/g; s/?/%3F/g; s/=/%3D/g; s/:/%3A/g; s/\//%2F/g')
        local encoded_message=$(echo "$message" | sed 's/ /%20/g; s/&/%26/g; s/?/%3F/g; s/=/%3D/g; s/:/%3A/g; s/\//%2F/g')
        
        local get_url="${serverchan_url}?title=${encoded_title}&desp=${encoded_message}"
        local get_response=$(curl -s -X GET "$get_url")
        
        if echo "$get_response" | grep -q '"errno":0'; then
            log "✅ Server 酱通知发送成功 (GET方法)"
            return 0
        else
            log "❌ Server 酱通知发送失败 (GET方法): $get_response"
            return 1
        fi
    fi
}

# 发送 Server 酱 Turbo 版通知（新版）
send_serverchan_turbo_notify() {
    local title="$1"
    local message="$2"
    
    if [ "$SERVERCHAN_TURBO_ENABLE" != "true" ] || [ -z "$SERVERCHAN_TURBO_SENDKEY" ]; then
        return 1
    fi
    
    local serverchan_url="https://sctapi.ftqq.com/${SERVERCHAN_TURBO_SENDKEY}.send"
    
    local response=$(curl -s -X POST "$serverchan_url" \
        -d "title=${title}" \
        -d "desp=${message}")
    
    if echo "$response" | grep -q '"code":0'; then
        log "✅ Server 酱 Turbo 版通知发送成功"
        return 0
    else
        log "❌ Server 酱 Turbo 版通知发送失败: $response"
        return 1
    fi
}

# 构建通知消息内容
build_notify_message() {
    local emoji="$1"
    local action="$2"
    local title="$3"
    local actionnumber="$4"
    local actiontotalsize="$5"
    local actionelapsedtime="$6"
    
    local actiontime=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 格式化文件大小
    local formatted_size=$(format_size "$actiontotalsize")
    
    # 构建远程存储路径
    local remote_path="${RCLONE_DEST}:${UPLOAD_PATH}"
    
    # 构建格式化的通知消息
    local message=""
    message+="${emoji}${emoji}${emoji}\n"
    message+="任务标题: ${NOTIFY_TITLE}-${action}\n"
    message+="任务类型: ${action}\n"
    message+="任务名称: ${title}\n"
    message+="时间: ${actiontime}\n"
    message+="上传位置: ${remote_path}\n"
    message+="数量: ${actionnumber}\n"
    message+="总大小: ${formatted_size}\n"
    message+="耗时: ${actionelapsedtime}秒\n"
    message+="${emoji}${emoji}${emoji}"
    
    echo -e "$message"
}

# 发送统一通知
send_notify() {
    local title="$1"
    local message="$2"
    local level="${3:-info}"  # info, success, warning, error
    local silent="${4:-false}"
    
    if [ "$NOTIFY_ENABLE" != "true" ]; then
        return 0
    fi
    
    log "📢 发送通知: ${title} (级别: ${level})"
    
    # 发送到各个渠道
    local success_count=0
    
    # Telegram
    if send_telegram_notify "*${title}*\n\n${message}" "$silent"; then
        ((success_count++))
    fi
    
    # Server 酱（旧版）
    if send_serverchan_notify "${title}" "${message}"; then
        ((success_count++))
    fi
    
    # Server 酱 Turbo 版（新版）
    if send_serverchan_turbo_notify "${title}" "${message}"; then
        ((success_count++))
    fi
    
    if [ $success_count -gt 0 ]; then
        log "✅ 通知发送成功 ($success_count 个渠道)"
        return 0
    else
        log "❌ 所有通知渠道发送失败"
        return 1
    fi
}

# 发送开始处理通知
notify_process_start() {
    if [ "$NOTIFY_PROCESS_START" != "true" ]; then
        return 0
    fi
    
    local torrent_name="$1"
    
    local emoji="🎈"
    local action="开始上传"
    local title="$torrent_name"
    local actionnumber="0"  # 开始处理时还不知道文件数量
    local actiontotalsize="0"  # 开始处理时还不知道总大小
    local actionelapsedtime="0"  # 刚开始，耗时为0
    
    local message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    send_notify "${NOTIFY_TITLE}开始${action}" "$message" "info"
}

# 发送上传成功通知
notify_upload_success() {
    if [ "$NOTIFY_UPLOAD_SUCCESS" != "true" ]; then
        return 0
    fi
    
    local torrent_name="$1"
    local file_count="$2"
    local total_size="$3"
    local duration="$4"
    
    local emoji="🎉"
    local action="上传完成"
    local title="$torrent_name"
    local actionnumber="$file_count"
    local actiontotalsize="$total_size"
    local actionelapsedtime="$duration"
    
    local message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    send_notify "${NOTIFY_TITLE}-${action}" "$message" "success"
}

# 发送上传失败通知
notify_upload_failed() {
    if [ "$NOTIFY_UPLOAD_FAILED" != "true" ]; then
        return 0
    fi
    
    local torrent_name="$1"
    local error_message="$2"
    
    local emoji="❌"
    local action="发生错误"
    local title="$torrent_name"
    local actionnumber="0"
    local actiontotalsize="0"
    local actionelapsedtime="0"
    
    local message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    # 添加错误信息
    message+="\n错误详情: ${error_message}"
    
    send_notify "${NOTIFY_TITLE}-${action}" "$message" "error"
}

# 发送黑名单删除通知
notify_blacklisted() {
    if [ "$NOTIFY_BLACKLISTED" != "true" ]; then
        return 0
    fi
    
    local torrent_name="$1"
    local reason="$2"
    
    local emoji="⚠"
    local action="黑名单删除"
    local title="$torrent_name"
    local actionnumber="0"
    local actiontotalsize="0"
    local actionelapsedtime="0"
    
    local message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    # 添加删除原因
    message+="\n删除原因: ${reason}"
    
    send_notify "${NOTIFY_TITLE}-${action}" "$message" "warning"
}

# 发送系统状态通知
notify_system_status() {
    if [ "$NOTIFY_SYSTEM_STATUS" != "true" ]; then
        return 0
    fi
    
    local status="$1"
    local message="$2"
    
    local emoji="🙌"
    local action="系统状态"
    local title="$status"
    local actionnumber="N/A"
    local actiontotalsize="0"
    local actionelapsedtime="N/A"
    
    local notify_message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    # 添加状态详情
    notify_message+="\n状态详情: ${message}"
    
    send_notify "${NOTIFY_TITLE}-${action}" "$notify_message" "info" "true"
}

# 发送统计摘要通知
notify_stats_summary() {
    if [ "$NOTIFY_STATS_SUMMARY" != "true" ]; then
        return 0
    fi
    
    if [ ! -f "$UPLOAD_STATS_FILE" ]; then
        return 1
    fi
    
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
    
    local emoji="🐟"
    local action="统计摘要"
    local title="上传统计报告"
    local actionnumber="$total_uploads"
    local actiontotalsize="$total_size"
    local actionelapsedtime="N/A"
    
    local message=$(build_notify_message "$emoji" "$action" "$title" "$actionnumber" "$actiontotalsize" "$actionelapsedtime")
    
    # 添加详细统计信息
    message+="\n成功任务: ${successful}"
    message+="\n失败任务: ${failed}"
    message+="\n黑名单删除: ${blacklisted}"
    message+="\n总文件数: ${total_files}"
    message+="\n成功率: ${success_rate}%"
    
    send_notify "${NOTIFY_TITLE}-${action}" "$message" "info"
}