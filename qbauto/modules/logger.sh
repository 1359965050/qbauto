#!/bin/bash

# =============================================================================
# 日志管理模块
# 功能：提供统一的日志记录和管理功能
# =============================================================================

# 初始化日志系统
init_logger() {
    # 如果 LOG_FILE 未设置，使用默认值
    if [ -z "${LOG_FILE:-}" ]; then
        LOG_FILE="/config/qbauto/log/qbauto.log"
    fi
    
    # 如果 LOG_DIR 未设置，从 LOG_FILE 提取
    if [ -z "${LOG_DIR:-}" ]; then
        LOG_DIR=$(dirname "$LOG_FILE")
    fi
    
    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    # 初始化日志文件
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
}

# 日志函数
log() {
    local message="$1"
    
    # 确保日志系统已初始化
    if [ -z "${LOG_FILE:-}" ]; then
        init_logger
    fi
    
    if [ -z "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >&2
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
        echo "$message" >&2
    fi
}

# 日志轮转
log_rotate() {
    local max_log_files="${MAX_LOG_FILES:-10}"
    
    if [ -f "$LOG_FILE" ]; then
        # 轮转日志文件
        for i in $(seq $((max_log_files-1)) -1 1); do
            local old_log="$LOG_FILE.$i"
            local new_log="$LOG_FILE.$((i+1))"
            [ -f "$old_log" ] && mv "$old_log" "$new_log" 2>/dev/null
        done
        mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
        > "$LOG_FILE"
        log "📄 日志文件已轮转"
        
        # 同样轮转 rclone 日志
        local rclone_log="$LOG_DIR/rclone.log"
        if [ -f "$rclone_log" ]; then
            for i in $(seq $((max_log_files-1)) -1 1); do
                local old_rclone_log="$rclone_log.$i"
                local new_rclone_log="$rclone_log.$((i+1))"
                [ -f "$old_rclone_log" ] && mv "$old_rclone_log" "$new_rclone_log" 2>/dev/null
            done
            mv "$rclone_log" "$rclone_log.1" 2>/dev/null
            > "$rclone_log"
        fi
    fi
}