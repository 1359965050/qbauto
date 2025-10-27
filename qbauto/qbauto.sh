#!/bin/bash

# =============================================================================
# qBittorrent 自动上传脚本 - 主脚本
# 版本：1.2
# =============================================================================

# 脚本目录和模块路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
CONFIG_DIR="/config/qbauto"
CONFIG_FILE="${CONFIG_DIR}/qbauto.conf"
RCLONE_CONFIG_TARGET="${CONFIG_DIR}/rclone.conf"

# 导出全局变量
export SCRIPT_DIR MODULES_DIR CONFIG_FILE RCLONE_CONFIG_TARGET

# 设置最小化的默认日志配置，确保日志系统能正常工作
LOG_DIR="/config/qbauto/log"
LOG_FILE="$LOG_DIR/qbauto.log"
mkdir -p "$LOG_DIR"

# 基础日志函数（在模块加载前使用）
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    echo "$message" >&2
}

# 检查并准备 rclone 配置文件
prepare_rclone_config() {
    log "🔍 检查 rclone 配置文件..."
    
    # 如果目标配置文件已存在，直接使用
    if [ -f "$RCLONE_CONFIG_TARGET" ]; then
        log "✅ 使用现有 rclone 配置文件: $RCLONE_CONFIG_TARGET"
        
        # 设置正确的文件权限
        chmod 600 "$RCLONE_CONFIG_TARGET" 2>/dev/null || true
        log "🔒 已设置配置文件权限为 600"
        return 0
    fi
    
    log "❌ rclone 配置文件不存在: $RCLONE_CONFIG_TARGET"
    return 1
}

# 更新配置文件中的 RCLONE_CONFIG 路径
update_config_file() {
    if [ -f "$CONFIG_FILE" ]; then
        # 检查是否需要更新配置
        local current_config=$(grep "^RCLONE_CONFIG=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"'"'")
        if [ "$current_config" != "$RCLONE_CONFIG_TARGET" ]; then
            log "🔄 更新配置文件中的 RCLONE_CONFIG 路径..."
            # 使用 sed 更新配置
            if sed -i "s|^RCLONE_CONFIG=.*|RCLONE_CONFIG=\"$RCLONE_CONFIG_TARGET\"|" "$CONFIG_FILE"; then
                log "✅ 已更新配置文件中的 RCLONE_CONFIG 路径"
            else
                log "⚠️ 更新配置文件失败，但继续执行"
            fi
        else
            log "ℹ️ 配置文件中的 RCLONE_CONFIG 路径已是最新"
        fi
    else
        log "⚠️ 配置文件不存在，将在加载模块后创建"
    fi
}

# 加载核心模块
log "🔧 开始加载模块..."
source "${MODULES_DIR}/core.sh"
source "${MODULES_DIR}/logger.sh"
source "${MODULES_DIR}/config.sh"

# 主函数
main() {
    local start_time=$(date +%s)
    local torrent_name="$1"
    local content_dir="$2"
    
    # 初始化日志系统
    init_logger
    
    log "🚀 开始处理: $torrent_name"
    log "🎯 主流程开始"
    log "📝 输入参数: 名称='$torrent_name', 路径='$content_dir'"
    
    # 准备 rclone 配置文件
    if prepare_rclone_config; then
        log "✅ rclone 配置文件准备就绪"
        # 更新配置文件路径
        update_config_file
    else
        log "❌ rclone 配置文件准备失败，尝试使用现有配置"
    fi
    
    # 加载配置
    if ! load_config; then
        log "❌ 配置加载失败"
        exit 1
    fi
    
    # 重新初始化日志系统（使用配置中的LOG_DIR）
    init_logger
    
    # 显式设置 rclone 配置环境变量
    if [ -n "$RCLONE_CONFIG" ] && [ -f "$RCLONE_CONFIG" ]; then
        export RCLONE_CONFIG
        log "✅ 设置 RCLONE_CONFIG 环境变量: $RCLONE_CONFIG"
    else
        log "❌ Rclone 配置文件不存在: $RCLONE_CONFIG"
        # 如果配置文件中指定的路径不存在，使用目标配置文件
        if [ -f "$RCLONE_CONFIG_TARGET" ]; then
            RCLONE_CONFIG="$RCLONE_CONFIG_TARGET"
            export RCLONE_CONFIG
            log "✅ 使用目标配置文件: $RCLONE_CONFIG"
        else
            log "❌ 无法找到可用的 Rclone 配置文件"
            exit 1
        fi
    fi
    
    # 加载其他功能模块
    source "${MODULES_DIR}/health.sh"
    source "${MODULES_DIR}/network.sh"
    source "${MODULES_DIR}/storage.sh"
    source "${MODULES_DIR}/filefilter.sh"  # 先加载模块
    source "${MODULES_DIR}/upload.sh"
    source "${MODULES_DIR}/blacklist.sh"
    source "${MODULES_DIR}/stats.sh"
    source "${MODULES_DIR}/performance.sh"
    source "${MODULES_DIR}/qbittorrent.sh"
    source "${MODULES_DIR}/notify.sh"
    
    # 初始化新模块
    init_file_filter
    init_notify
    
    # 配置验证
    if ! validate_config; then
        log "❌ 配置验证失败，请检查配置文件"
        exit 1
    fi
    
    # 发送开始处理通知
    if [ "$NOTIFY_ENABLE" = "true" ]; then
        notify_process_start "$torrent_name" "$content_dir"
    fi
    
    # 显示当前统计摘要
    show_stats_summary

    # 系统健康检查
    if ! run_health_check; then
        log "⚠️ 健康检查发现问题，但继续执行"
    fi

    # 网络质量检测
    if ! check_network_quality; then
        log "⚠️ 网络质量不佳，但继续执行上传"
    fi

    # 存储空间检查
    if ! check_storage_space; then
        log "❌ 存储空间检查失败，但尝试继续执行（可能是检测误差）"
    fi

    # 基础检查
    if ! check_basics "$torrent_name" "$content_dir"; then
        log "❌ 基础检查失败"
        update_upload_stats "$torrent_name" "0" "0" "failed" "基础检查失败"
        
        # 发送失败通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_upload_failed "$torrent_name" "基础检查失败"
        fi
        
        exit 1
    fi

    # 获取十六进制哈希值
    log "🔍 正在获取哈希值..."
    local torrent_hash
    torrent_hash=$(get_hex_hash "$torrent_name" "$content_dir" "$@")
    
    # 检查哈希值是否为空
    if [ -z "$torrent_hash" ]; then
        log "❌ 错误：获取到的哈希值为空"
        update_upload_stats "$torrent_name" "0" "0" "failed" "获取哈希值失败"
        
        # 发送失败通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_upload_failed "$torrent_name" "获取哈希值失败"
        fi
        
        exit 3
    fi
    
    log "🔐 使用的哈希值: $torrent_hash"

    # 获取文件列表（已应用黑名单过滤）
    local files
    mapfile -d '' files < <(get_upload_files "$content_dir")
    
    # 检查内容是否因黑名单而被完全删除
    if [ ! -e "$content_dir" ]; then
        log "🚫 内容已被完全删除（黑名单）: $torrent_name"
        update_upload_stats "$torrent_name" "0" "0" "blacklisted" "内容包含黑名单关键词，已删除"
        
        # 发送黑名单通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_blacklisted "$torrent_name" "内容包含黑名单关键词"
        fi
        
        # 即使没有文件上传，如果是吸血模式且获取到了哈希值，仍然删除种子
        if [ "$LEECHING_MODE" = "true" ] && [ -n "$torrent_hash" ]; then
            log "🔄 内容已被黑名单删除，但吸血模式已启用，尝试删除种子..."
            if process_torrent "$torrent_hash"; then
                log "🎉 种子已删除（黑名单内容）"
            else
                log "⚠️ 种子删除失败（黑名单内容）"
            fi
        fi
        
        # 性能监控（黑名单情况）
        monitor_performance "$start_time" "0" "0" "blacklisted"
        exit 0
    fi
    
        # 检查文件数组是否为空
    if [ ${#files[@]} -eq 0 ] || [ -z "${files[0]}" ]; then
        log "🚫 没有找到可上传的文件（可能被黑名单过滤）"
        update_upload_stats "$torrent_name" "0" "0" "blacklisted" "没有找到可上传的文件（黑名单过滤）"
        
        # 发送黑名单通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_blacklisted "$torrent_name" "没有找到可上传的文件"
        fi
        
        # 即使没有文件上传，如果是吸血模式且获取到了哈希值，仍然删除种子
        if [ "$LEECHING_MODE" = "true" ] && [ -n "$torrent_hash" ]; then
            log "🔄 没有文件需要上传，但吸血模式已启用，尝试删除种子..."
            if process_torrent "$torrent_hash"; then
                log "🎉 种子已删除（无文件上传）"
            else
                log "⚠️ 种子删除失败（无文件上传）"
            fi
        fi
        
        # 性能监控（无文件情况）
        monitor_performance "$start_time" "0" "0" "no_files"
        exit 0
    fi

    # 应用文件类型过滤
    log "🔍 应用文件类型过滤..."
    local filtered_files_array=()
    
    if [ "$FILE_FILTER_ENABLE" = "true" ]; then
        # 启用文件过滤时使用正确的数组处理
        mapfile -d '' filtered_files_array < <(filter_files_by_type "${files[@]}")
    else
        # 禁用文件过滤时直接复制数组
        filtered_files_array=("${files[@]}")
        log "ℹ️ 文件类型过滤已禁用，跳过过滤"
    fi
    
        # 添加更严格的数组检查
    if [ ${#filtered_files_array[@]} -eq 0 ] || [ -z "${filtered_files_array[0]}" ]; then
        log "🚫 过滤后没有可上传的文件"
        # ... 处理无文件的情况
    fi
    
    if [ ${#filtered_files_array[@]} -eq 0 ]; then
        log "🚫 所有文件都被文件类型过滤排除"
        update_upload_stats "$torrent_name" "0" "0" "filtered" "所有文件被文件类型过滤排除"
        
        # 发送过滤通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_blacklisted "$torrent_name" "所有文件被文件类型过滤排除"
        fi
        
        # 即使没有文件上传，如果是吸血模式且获取到了哈希值，仍然删除种子
        if [ "$LEECHING_MODE" = "true" ] && [ -n "$torrent_hash" ]; then
            log "🔄 所有文件被过滤，但吸血模式已启用，尝试删除种子..."
            if process_torrent "$torrent_hash"; then
                log "🎉 种子已删除（文件被过滤）"
            else
                log "⚠️ 种子删除失败（文件被过滤）"
            fi
        fi
        
        # 性能监控（过滤情况）
        monitor_performance "$start_time" "0" "0" "filtered"
        exit 0
    fi

    # 计算总文件大小 - 使用修复后的数组
    local total_size=0
    for file in "${filtered_files_array[@]}"; do
        if [ -f "$file" ]; then
            local size=$(get_file_size "$file")
            total_size=$((total_size + size))
        fi
    done

    # 获取文件类型统计
    get_file_type_stats "${filtered_files_array[@]}"

# 上传文件 - 使用修复后的数组
    local upload_file_count=${#filtered_files_array[@]}
    if [ $upload_file_count -gt 0 ] && upload_files "${filtered_files_array[@]}"; then
        log "✅ 所有文件上传成功"
        update_upload_stats "$torrent_name" "$upload_file_count" "$total_size" "success" "所有文件上传成功"
        
        # 计算平均速度
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local avg_speed="0"
        if [ "$duration" -gt 0 ] && [ "$total_size" -gt 0 ]; then
            local speed_bps=$((total_size / duration))
            avg_speed=$(echo "scale=2; $speed_bps / 1048576" | bc 2>/dev/null || echo "0")
        fi
        
        # 发送成功通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_upload_success "$torrent_name" "$upload_file_count" "$total_size" "$duration" "$avg_speed"
        fi
        
        log "🔄 开始处理种子..."
        if process_torrent "$torrent_hash"; then
            log "🎉 任务完成 - 种子已删除"
        else
            log "⚠️ 任务完成 - 但种子删除失败"
        fi
        
        # 性能监控（成功情况）
        monitor_performance "$start_time" "$upload_file_count" "$total_size" "success"
    else
        log "❌ 部分文件上传失败，跳过种子处理"
        update_upload_stats "$torrent_name" "$upload_file_count" "$total_size" "failed" "部分文件上传失败"
        
        # 发送失败通知
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            notify_upload_failed "$torrent_name" "部分文件上传失败"
        fi
        
        # 性能监控（失败情况）
        monitor_performance "$start_time" "$upload_file_count" "$total_size" "failed"
        exit 1
    fi
    
    # 显示更新后的统计
    show_stats_summary
    
    # 发送统计摘要通知
    if [ "$NOTIFY_ENABLE" = "true" ] && [ "$NOTIFY_STATS_ENABLE" = "true" ]; then
        notify_stats_summary
    fi
}

# 独立健康检查函数（供cron使用）
health_check() {
    # 设置最小化的默认配置
    LOG_DIR="/config/qbauto/log"
    LOG_FILE="$LOG_DIR/qbauto.log"
    mkdir -p "$LOG_DIR"
    
    # 基础日志函数
    log() {
        local message="$1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
        echo "$message" >&2
    }
    
    # 加载健康检查模块
    source "${MODULES_DIR}/health.sh"
    
    log "🏥 开始独立健康检查..."
    
    # 运行健康检查
    if run_health_check; then
        log "✅ 独立健康检查完成"
        return 0
    else
        log "❌ 独立健康检查发现问题"
        return 1
    fi
}

# 命令行参数处理
case "${1:-}" in
    "health-check")
        health_check
        ;;
    "test-notify")
        # 测试通知功能
        source "${MODULES_DIR}/core.sh"
        source "${MODULES_DIR}/logger.sh"
        source "${MODULES_DIR}/config.sh"
        load_config
        init_logger
        source "${MODULES_DIR}/notify.sh"
        init_notify
        
        if [ "$NOTIFY_ENABLE" = "true" ]; then
            log "🧪 发送测试通知..."
            send_notify "测试通知" "这是一条测试消息，用于验证通知功能是否正常工作。" "info"
        else
            log "❌ 通知功能未启用"
        fi
        ;;
    "prepare-rclone-config")
        # 手动准备 rclone 配置
        prepare_rclone_config
        ;;
    *)
        # 运行主程序
        main "$@"
        ;;
esac
