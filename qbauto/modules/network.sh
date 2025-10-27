#!/bin/bash

# =============================================================================
# 网络检测模块
# 功能：网络质量检测和连接测试
# =============================================================================

# 网络检测函数
check_network_quality() {
    if [ "$ENABLE_NETWORK_CHECK" != "true" ]; then
        log "ℹ️ 网络质量检测已禁用"
        return 0
    fi
    
    local min_speed="${MIN_UPLOAD_SPEED:-1}"  # MB/s
    local timeout="${NETWORK_CHECK_TIMEOUT:-30}"
    
    log "🌐 检查网络连接质量..."
    
    # 测试到目标存储的连接
    local start_time=$(date +%s)
    local test_result
    test_result=$($RCLONE_CMD --config "$RCLONE_CONFIG" about "$RCLONE_DEST:" --timeout "${timeout}s" 2>&1)
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $? -eq 0 ]; then
        log "✅ 网络连接正常，响应时间: ${duration}s"
        return 0
    else
        log "⚠️ 网络连接不稳定或响应缓慢，响应时间: ${duration}s"
        log "⚠️ 错误信息: $test_result"
        return 1
    fi
}