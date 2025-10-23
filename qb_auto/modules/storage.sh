#!/bin/bash

# =============================================================================
# 存储管理模块
# 功能：本地和远程存储空间检查
# =============================================================================

# 存储空间检查（最终修复版）
check_storage_space() {
    if [ "$ENABLE_SPACE_CHECK" != "true" ]; then
        log "ℹ️ 存储空间检查已禁用"
        return 0
    fi
    
    log "💾 检查存储空间..."
    local errors=0
    
    # 检查本地存储空间
    if command -v df >/dev/null 2>&1; then
        # 方法1: 使用 df -B1 获取字节（如果支持）
        local local_free_space="0"
        if df --help 2>/dev/null | grep -q "\-\-output"; then
            local_free_space=$(df --output=avail -B1 "/downloads" 2>/dev/null | awk 'NR==2 {print $1}' 2>/dev/null || echo "0")
        fi
        
        # 方法2: 如果方法1失败，使用传统方法（KB单位转换为字节）
        if [ "$local_free_space" = "0" ] || [ -z "$local_free_space" ]; then
            local_free_space=$(df "/downloads" 2>/dev/null | awk 'NR==2 {print $4 * 1024}' 2>/dev/null || echo "0")
        fi
        
        # 确保获取到有效的数字
        if [ -z "$local_free_space" ] || [ "$local_free_space" = "" ]; then
            local_free_space="0"
        fi
        
        # 将配置的最小空闲空间转换为字节
        local local_min_bytes=0
        if [[ "$LOCAL_MIN_FREE" =~ ^[0-9]+G$ ]]; then
            local_min_bytes=$((${LOCAL_MIN_FREE%G} * 1024 * 1024 * 1024))
        elif [[ "$LOCAL_MIN_FREE" =~ ^[0-9]+M$ ]]; then
            local_min_bytes=$((${LOCAL_MIN_FREE%M} * 1024 * 1024))
        elif [[ "$LOCAL_MIN_FREE" =~ ^[0-9]+K$ ]]; then
            local_min_bytes=$((${LOCAL_MIN_FREE%K} * 1024))
        else
            # 如果没有单位，假设是字节
            local_min_bytes=$LOCAL_MIN_FREE
        fi
        
        log "🔍 本地存储检查: 可用空间=$(format_size $local_free_space), 最小要求=$LOCAL_MIN_FREE ($(format_size $local_min_bytes))"
        
        # 验证数字有效性
        if ! [[ "$local_free_space" =~ ^[0-9]+$ ]]; then
            log "⚠️ 本地存储空间检测失败，获取到的值无效: '$local_free_space'"
            ((errors++))
        elif [ "$local_free_space" -lt "$local_min_bytes" ]; then
            log "❌ 本地存储空间不足: 剩余 $(format_size $local_free_space)，需要至少 $LOCAL_MIN_FREE"
            ((errors++))
        else
            log "✅ 本地存储空间充足: $(format_size $local_free_space)"
        fi
    else
        log "⚠️ 无法检查本地存储空间，df 命令不可用"
        ((errors++))
    fi
    
    # 检查远程存储空间
    log "🔍 检查远程存储空间..."
    local remote_info
    remote_info=$($RCLONE_CMD --config "$RCLONE_CONFIG" about "$RCLONE_DEST:" --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local remote_free=$(echo "$remote_info" | jq -r '.free // 0' 2>/dev/null || echo "0")
        local remote_total=$(echo "$remote_info" | jq -r '.total // 0' 2>/dev/null || echo "0")
        
        if [ "$remote_free" != "0" ] && [ "$remote_free" != "null" ] && [ "$remote_free" != "undefined" ] && [ -n "$remote_free" ]; then
            # 将配置的最小空闲空间转换为字节
            local remote_min_bytes=0
            if [[ "$REMOTE_MIN_FREE" =~ ^[0-9]+G$ ]]; then
                remote_min_bytes=$((${REMOTE_MIN_FREE%G} * 1024 * 1024 * 1024))
            elif [[ "$REMOTE_MIN_FREE" =~ ^[0-9]+M$ ]]; then
                remote_min_bytes=$((${REMOTE_MIN_FREE%M} * 1024 * 1024))
            elif [[ "$REMOTE_MIN_FREE" =~ ^[0-9]+K$ ]]; then
                remote_min_bytes=$((${REMOTE_MIN_FREE%K} * 1024))
            else
                # 如果没有单位，假设是字节
                remote_min_bytes=$REMOTE_MIN_FREE
            fi
            
            log "🔍 远程存储检查: 可用空间=$(format_size $remote_free), 最小要求=$REMOTE_MIN_FREE ($(format_size $remote_min_bytes))"
            
            if [ "$remote_free" -lt "$remote_min_bytes" ]; then
                log "❌ 远程存储空间不足: 剩余 $(format_size $remote_free)，需要至少 $REMOTE_MIN_FREE"
                ((errors++))
            else
                log "✅ 远程存储空间充足: $(format_size $remote_free)"
            fi
        else
            log "ℹ️ 远程存储空间无限或无法获取具体数值，跳过检查"
        fi
    else
        log "⚠️ 远程存储检查失败，但继续执行"
    fi
    
    if [ $errors -gt 0 ]; then
        log "❌ 存储空间检查失败: $errors 个错误"
        return 1
    else
        log "✅ 存储空间检查通过"
        return 0
    fi
}