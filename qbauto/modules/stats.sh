#!/bin/bash

# =============================================================================
# 统计模块
# 功能：上传统计管理和报告
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