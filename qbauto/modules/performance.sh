#!/bin/bash

# =============================================================================
# 性能监控模块
# 功能：性能数据收集和报告
# =============================================================================

# 性能监控函数
monitor_performance() {
    if [ "$ENABLE_PERFORMANCE_MONITORING" != "true" ]; then
        return 0
    fi
    
    local start_time="$1"
    local file_count="$2"
    local total_size="$3"
    local status="$4"  # success, failed
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 确保性能日志目录存在
    mkdir -p "$(dirname "$PERFORMANCE_LOG")"
    
    # 初始化性能日志文件（如果不存在）
    if [ ! -f "$PERFORMANCE_LOG" ]; then
        echo "timestamp,torrent_name,file_count,total_size,duration,status,average_speed_mbps" > "$PERFORMANCE_LOG"
    fi
    
    if [ "$duration" -gt 0 ] && [ "$total_size" -gt 0 ]; then
        local speed_bps=$((total_size / duration))
        local speed_mbps=$(echo "scale=2; $speed_bps / 1048576" | bc 2>/dev/null || echo "0")
        
        log "📊 性能统计:"
        log "  ⏱️ 耗时: ${duration}s"
        log "  🚀 平均速度: ${speed_mbps} MB/s"
        log "  📁 处理文件: $file_count 个"
        log "  💾 总大小: $(format_size $total_size)"
        log "  📝 状态: $status"
        
        # 记录到性能日志
        echo "$(date '+%Y-%m-%d %H:%M:%S'),\"$torrent_name\",$file_count,$total_size,$duration,$status,$speed_mbps" >> "$PERFORMANCE_LOG"
        
        # 记录详细的性能信息到单独文件
        local detail_log="$LOG_DIR/performance_detail.json"
        local performance_entry=$(jq -n \
            --arg timestamp "$(date -Iseconds)" \
            --arg name "$torrent_name" \
            --argjson count "$file_count" \
            --argjson size "$total_size" \
            --argjson duration "$duration" \
            --arg speed "$speed_mbps" \
            --arg status "$status" \
            '{
                timestamp: $timestamp,
                name: $name,
                file_count: $count,
                total_size: $size,
                duration_seconds: $duration,
                average_speed_mbps: $speed,
                status: $status
            }')
        
        if [ -f "$detail_log" ]; then
            local temp_file=$(mktemp)
            jq ". += [$performance_entry]" "$detail_log" > "$temp_file" 2>/dev/null && mv "$temp_file" "$detail_log"
        else
            echo "[$performance_entry]" > "$detail_log"
        fi
    else
        log "📊 性能统计: 耗时 ${duration}s, 状态: $status"
    fi
}