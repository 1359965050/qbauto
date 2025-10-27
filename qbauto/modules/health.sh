#!/bin/bash

# =============================================================================
# 健康检查模块
# 功能：系统健康状态检查和自愈机制
# =============================================================================

# 系统健康检查
run_health_check() {
    if [ "${ENABLE_HEALTH_CHECK:-true}" != "true" ]; then
        return 0
    fi
    
    local errors=0
    local warnings=0
    
    log "🏥 开始系统健康检查..."
    
    # 检查 rclone 命令可用性（而不是进程）
    if ! command -v "${RCLONE_CMD:-/usr/bin/rclone}" >/dev/null 2>&1; then
        log "❌ rclone 命令不可用: ${RCLONE_CMD:-/usr/bin/rclone}"
        ((errors++))
    else
        # 测试 rclone 基本功能
        if ! ${RCLONE_CMD:-/usr/bin/rclone} version >/dev/null 2>&1; then
            log "❌ rclone 命令执行失败"
            ((errors++))
        else
            log "✅ rclone 命令可用"
        fi
    fi
    
    # 检查日志文件大小
    if [ -f "${LOG_FILE:-/config/qbauto/log/qbauto.log}" ]; then
        local log_size=$(stat -c%s "${LOG_FILE:-/config/qbauto/log/qbauto.log}" 2>/dev/null || echo "0")
        if [ "$log_size" -gt $((100 * 1024 * 1024)) ]; then  # 100MB
            log "⚠️ 日志文件过大 ($(format_size $log_size))，执行轮转"
            log_rotate
        fi
    fi
    
    # 检查 rclone 日志文件大小
    local rclone_log="${LOG_DIR:-/config/qbauto/log}/rclone.log"
    if [ -f "$rclone_log" ]; then
        local rclone_log_size=$(stat -c%s "$rclone_log" 2>/dev/null || echo "0")
        if [ "$rclone_log_size" -gt $((50 * 1024 * 1024)) ]; then  # 50MB
            log "⚠️ rclone 日志文件过大 ($(format_size $rclone_log_size))，执行轮转"
            # 轮转 rclone 日志
            local max_log_files="${MAX_LOG_FILES:-10}"
            for i in $(seq $((max_log_files-1)) -1 1); do
                local old_log="$rclone_log.$i"
                local new_log="$rclone_log.$((i+1))"
                [ -f "$old_log" ] && mv "$old_log" "$new_log" 2>/dev/null
            done
            mv "$rclone_log" "$rclone_log.1" 2>/dev/null
            > "$rclone_log"
        fi
    fi
    
    # 检查临时文件
    local temp_files_count=$(find /tmp -name "qbauto_*" -mtime +1 2>/dev/null | wc -l)
    if [ "$temp_files_count" -gt 10 ]; then
        log "⚠️ 发现 $temp_files_count 个过期临时文件，正在清理..."
        find /tmp -name "qbauto_*" -mtime +1 -delete 2>/dev/null
    fi
    
    # 检查磁盘 inode（如果可用）
    if command -v df >/dev/null 2>&1; then
        local inode_usage
        inode_usage=$(df -i /downloads 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
        if [ -n "$inode_usage" ] && [ "$inode_usage" -ne "0" ] && [ "$inode_usage" -gt 90 ]; then
            log "⚠️ inode 使用率过高: ${inode_usage}%"
            ((warnings++))
        fi
    fi
    
    # 检查必要的目录权限
    local dirs_to_check=("/downloads" "${LOG_DIR:-/config/qbauto/log}" "$(dirname "${CONFIG_FILE:-/config/qbauto/qbauto.conf}")")
    for dir in "${dirs_to_check[@]}"; do
        if [ -d "$dir" ] && [ ! -w "$dir" ]; then
            log "❌ 目录不可写: $dir"
            ((errors++))
        fi
    done
    
    # 检查配置文件可读性
    if [ ! -r "${CONFIG_FILE:-/config/qbauto/qbauto.conf}" ]; then
        log "❌ 配置文件不可读: ${CONFIG_FILE:-/config/qbauto/qbauto.conf}"
        ((errors++))
    fi
    
    # 检查 rclone 配置文件
    if [ ! -r "${RCLONE_CONFIG:-/config/rclone/rclone.conf}" ]; then
        log "❌ rclone 配置文件不可读: ${RCLONE_CONFIG:-/config/rclone/rclone.conf}"
        ((errors++))
    fi
    
    # 输出健康检查结果
    if [ $errors -gt 0 ]; then
        log "❌ 系统健康检查发现 $errors 个错误, $warnings 个警告"
        return 1
    elif [ $warnings -gt 0 ]; then
        log "⚠️ 系统健康检查通过，但有 $warnings 个警告"
        return 0
    else
        log "✅ 系统健康检查通过"
        return 0
    fi
}