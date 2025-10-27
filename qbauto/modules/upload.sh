#!/bin/bash

# =============================================================================
# 上传功能模块
# 功能：文件上传、验证和重试机制
# =============================================================================

# 上传验证函数
verify_upload() {
    local local_file="$1"
    local remote_path="$2"
    local filename=$(basename "$local_file")
    
    if [ "$VERIFY_UPLOAD" != "true" ]; then
        log "ℹ️ 上传验证已禁用，跳过验证: $filename"
        return 0
    fi
    
    log "🔍 开始验证上传文件: $filename"
    
    # 检查远程文件是否存在
    if ! $RCLONE_CMD --config "$RCLONE_CONFIG" ls "$RCLONE_DEST:$remote_path/$filename" >/dev/null 2>&1; then
        log "❌ 验证失败: 远程文件不存在 - $filename"
        return 1
    fi
    
    # 比较文件大小
    local local_size=$(get_file_size "$local_file")
    local remote_size=$($RCLONE_CMD --config "$RCLONE_CONFIG" size "$RCLONE_DEST:$remote_path/$filename" --json 2>/dev/null | jq -r '.bytes' 2>/dev/null || echo "0")
    
    if [ -z "$remote_size" ] || [ "$remote_size" = "null" ] || [ "$remote_size" -eq 0 ]; then
        log "⚠️ 无法获取远程文件大小，跳过大小验证: $filename"
        return 0
    fi
    
    if [ "$local_size" != "$remote_size" ]; then
        log "❌ 验证失败: 文件大小不匹配 - $filename"
        log "❌ 本地大小: $local_size, 远程大小: $remote_size"
        return 1
    fi
    
    log "✅ 验证通过: $filename (大小: $(format_size $local_size))"
    return 0
}

# 智能重试上传函数
adaptive_retry_upload() {
    local file_path="$1"
    local upload_path="$2"
    local retry_count=0
    local current_delay="$RCLONE_RETRY_DELAY"
    local filename=$(basename "$file_path")
    
    # 严格的文件检查
    if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
        log "❌ 文件不存在或路径为空: '$file_path'"
        return 1
    fi
    
    # 检查文件是否可读
    if [ ! -r "$file_path" ]; then
        log "❌ 文件不可读: $filename"
        return 1
    fi

    # 如果不启用自适应重试，使用原来的简单重试
    if [ "$ADAPTIVE_RETRY" != "true" ]; then
        while [ $retry_count -lt $RCLONE_RETRIES ]; do
            log "🔄 尝试上传 ($((retry_count+1))/$RCLONE_RETRIES): $filename"
            
            if $RCLONE_CMD --config "$RCLONE_CONFIG" copy --progress "$file_path" "$RCLONE_DEST:$upload_path/" >> "$LOG_DIR/rclone.log" 2>&1; then
                if verify_upload "$file_path" "$upload_path"; then
                    log "✅ 上传成功: $filename"
                    return 0
                else
                    log "❌ 上传验证失败: $filename"
                fi
            else
                log "❌ 上传失败: $filename (尝试 $((retry_count+1))/$RCLONE_RETRIES)"
            fi
            
            ((retry_count++))
            if [ $retry_count -lt $RCLONE_RETRIES ]; then
                log "⏳ 等待 $RCLONE_RETRY_DELAY 后重试..."
                sleep $RCLONE_RETRY_DELAY
            fi
        done
        return 1
    fi
    
    # 自适应重试逻辑
    while [ $retry_count -lt $RCLONE_RETRIES ]; do
        log "🔄 尝试上传 ($((retry_count+1))/$RCLONE_RETRIES): $filename"
        
        if $RCLONE_CMD --config "$RCLONE_CONFIG" copy --progress "$file_path" "$RCLONE_DEST:$upload_path/" >> "$LOG_DIR/rclone.log" 2>&1; then
            if verify_upload "$file_path" "$upload_path"; then
                log "✅ 上传成功: $filename"
                return 0
            else
                log "❌ 上传验证失败: $filename"
            fi
        else
            log "❌ 上传失败: $filename (尝试 $((retry_count+1))/$RCLONE_RETRIES)"
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $RCLONE_RETRIES ]; then
            log "⏳ 等待 $current_delay 后重试..."
            sleep $current_delay
            
            # 指数退避
            local seconds=$(echo "$current_delay" | sed 's/s//')
            local new_seconds=$((seconds * RETRY_BACKOFF_MULTIPLIER))
            local max_seconds=$(echo "$MAX_RETRY_DELAY" | sed 's/s//')
            
            if [ $new_seconds -le $max_seconds ]; then
                current_delay="${new_seconds}s"
            else
                current_delay="$MAX_RETRY_DELAY"
            fi
        fi
    done
    
    log "💥 最终上传失败: $filename"
    return 1
}

# 获取要上传的文件列表
get_upload_files() {
    local content_path="$1"
    local files=()

    # 首先处理黑名单内容
    process_blacklisted_content "$content_path"
    
    # 检查内容是否已被删除（由于黑名单）
    if [ ! -e "$content_path" ]; then
        log "ℹ️ 内容已被删除（黑名单）: $content_path"
        return 1
    fi

    if [ -f "$content_path" ]; then
        # 单个文件 - 检查黑名单
        if check_blacklist "$content_path"; then
            log "🚫 跳过黑名单文件: $(basename "$content_path")"
            return 1
        else
            files=("$content_path")
            log "📄 单个文件: $(basename "$content_path")"
        fi
    elif [ -d "$content_path" ]; then
        # 目录 - 先检查整个文件夹是否包含黑名单文件
        if check_folder_blacklist "$content_path"; then
            log "🚫 跳过包含黑名单文件的文件夹: $(basename "$content_path")"
            return 1
        fi
        
        # 文件夹中没有黑名单文件，获取所有文件
        while IFS= read -r -d '' file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                files+=("$file")
            fi
        done < <(find "$content_path" -type f -print0 2>/dev/null)
        log "📁 目录文件数: ${#files[@]}"
    else
        log "❌ 路径既不是文件也不是目录: $content_path"
        return 1
    fi

    # 正确返回文件数组
    if [ ${#files[@]} -gt 0 ]; then
        printf '%s\0' "${files[@]}"
    fi
}

# 上传文件（使用智能重试）
upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0
    local total=${#files[@]}
    local total_size=0
    
    # 严格的数组检查
    if [ $total -eq 0 ] || [ -z "${files[0]}" ]; then
        log "❌ 上传文件列表为空或无效"
        return 1
    fi

    log "📤 开始上传 $total 个文件到: $upload_path"
    
    # 计算总大小并验证文件存在
    for file_path in "${files[@]}"; do
        if [ -z "$file_path" ]; then
            log "❌ 文件路径为空，跳过"
            continue
        fi
        
        if [ -f "$file_path" ]; then
            local file_size=$(get_file_size "$file_path")
            total_size=$((total_size + file_size))
            log "✅ 文件验证通过: $(basename "$file_path") ($(format_size $file_size))"
        else
            log "❌ 文件不存在或不可访问: $file_path"
            return 1
        fi
    done
    
    if [ $total_size -eq 0 ]; then
        log "⚠️ 警告: 总上传大小为 0，可能有问题"
    fi

    log "💾 总上传大小: $(format_size $total_size)"

    for file_path in "${files[@]}"; do
        # 再次检查文件是否存在
        if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
            log "❌ 文件不存在或路径为空，跳过: '$file_path'"
            continue
        fi
        
        if adaptive_retry_upload "$file_path" "$upload_path"; then
            ((success++))
        fi
    done

    log "📊 上传完成: $success/$total 成功"
    if [ $success -eq $total ]; then
        return 0
    else
        log "❌ 上传失败: $((total - success)) 个文件失败"
        return 1
    fi
}

# 批量上传函数（用于大量文件）
batch_upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0
    local total=${#files[@]}
    local total_size=0
    local batch_size=10  # 每批上传的文件数

    # 数组检查
    if [ $total -eq 0 ] || [ -z "${files[0]}" ]; then
        log "❌ 批量上传文件列表为空"
        return 1
    fi

    log "📤 开始批量上传 $total 个文件到: $upload_path (批次大小: $batch_size)"

    # 计算总大小
    for file_path in "${files[@]}"; do
        if [ -n "$file_path" ] && [ -f "$file_path" ]; then
            local file_size=$(get_file_size "$file_path")
            total_size=$((total_size + file_size))
        fi
    done

    log "💾 总上传大小: $(format_size $total_size)"

    # 分批处理文件
    for ((i=0; i<total; i+=batch_size)); do
        local batch_files=("${files[@]:i:batch_size}")
        local batch_num=$((i/batch_size + 1))
        local batch_total=$(( (total + batch_size - 1) / batch_size ))
        
        log "🔄 处理批次 $batch_num/$batch_total (${#batch_files[@]} 个文件)"
        
        for file_path in "${batch_files[@]}"; do
            # 检查文件是否存在
            if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
                log "❌ 文件不存在，跳过: '$file_path'"
                continue
            fi
            
            if adaptive_retry_upload "$file_path" "$upload_path"; then
                ((success++))
            fi
        done
        
        # 批次间延迟，避免过度请求
        if [ $i -lt $((total - batch_size)) ]; then
            log "⏳ 批次完成，等待 5 秒后继续下一批次..."
            sleep 5
        fi
    done

    log "📊 批量上传完成: $success/$total 成功"
    [ $success -eq $total ]
}

# 并行上传函数（实验性功能）
parallel_upload_files() {
    local files=("$@")
    local upload_path="${UPLOAD_PATH%/}"
    local success=0
    local total=${#files[@]}
    local total_size=0
    local max_parallel=3  # 最大并行上传数

    # 数组检查
    if [ $total -eq 0 ] || [ -z "${files[0]}" ]; then
        log "❌ 并行上传文件列表为空"
        return 1
    fi

    log "⚡ 开始并行上传 $total 个文件到: $upload_path (最大并行数: $max_parallel)"

    # 计算总大小
    for file_path in "${files[@]}"; do
        if [ -n "$file_path" ] && [ -f "$file_path" ]; then
            local file_size=$(get_file_size "$file_path")
            total_size=$((total_size + file_size))
        fi
    done

    log "💾 总上传大小: $(format_size $total_size)"

    # 创建临时文件用于跟踪进程
    local temp_dir=$(mktemp -d)
    local pid_file="$temp_dir/upload_pids"
    local results_file="$temp_dir/results"
    
    # 初始化结果文件
    > "$results_file"
    
    # 并行上传函数
    upload_single_file() {
        local file="$1"
        local path="$2"
        local filename=$(basename "$file")
        
        if adaptive_retry_upload "$file" "$path"; then
            echo "success:$filename" >> "$results_file"
        else
            echo "failed:$filename" >> "$results_file"
        fi
    }
    
    # 启动并行上传
    local running=0
    for file_path in "${files[@]}"; do
        # 检查文件是否存在
        if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
            log "❌ 文件不存在，跳过: '$file_path'"
            continue
        fi
        
        # 如果达到最大并行数，等待一个进程完成
        while [ $running -ge $max_parallel ]; do
            sleep 1
            running=$(jobs -r | wc -l)
        done
        
        # 启动上传进程
        upload_single_file "$file_path" "$upload_path" &
        echo $! >> "$pid_file"
        ((running++))
    done
    
    # 等待所有进程完成
    wait
    
    # 统计结果
    if [ -f "$results_file" ]; then
        success=$(grep -c "^success:" "$results_file" || echo "0")
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"

    log "📊 并行上传完成: $success/$total 成功"
    [ $success -eq $total ]
}

# 上传进度监控函数
monitor_upload_progress() {
    local total_files="$1"
    local completed_files="$2"
    local total_size="$3"
    local uploaded_size="$4"
    
    if [ "$total_files" -eq 0 ]; then
        return
    fi
    
    local progress_percent=0
    if [ "$total_size" -gt 0 ]; then
        progress_percent=$((uploaded_size * 100 / total_size))
    fi
    
    local file_progress=$((completed_files * 100 / total_files))
    
    log "📊 上传进度: 文件 $completed_files/$total_files ($file_progress%) | 数据 $(format_size $uploaded_size)/$(format_size $total_size) ($progress_percent%)"
}

# 上传速度计算函数
calculate_upload_speed() {
    local start_time="$1"
    local total_size="$2"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$duration" -gt 0 ] && [ "$total_size" -gt 0 ]; then
        local speed_bps=$((total_size / duration))
        local speed_mbps=$(echo "scale=2; $speed_bps / 1048576" | bc 2>/dev/null || echo "0")
        echo "$speed_mbps"
    else
        echo "0"
    fi
}

# 上传诊断函数
upload_diagnosis() {
    local error_output="$1"
    local filename="$2"
    
    log "🔍 开始上传诊断: $filename"
    
    # 分析常见的错误模式
    if [[ "$error_output" == *"quota exceeded"* ]]; then
        log "❌ 诊断: 存储配额已满"
        return 1
    elif [[ "$error_output" == *"rate limit"* ]]; then
        log "❌ 诊断: API 速率限制"
        return 1
    elif [[ "$error_output" == *"network"* ]] || [[ "$error_output" == *"timeout"* ]]; then
        log "❌ 诊断: 网络连接问题"
        return 1
    elif [[ "$error_output" == *"permission denied"* ]]; then
        log "❌ 诊断: 权限不足"
        return 1
    elif [[ "$error_output" == *"no such file or directory"* ]]; then
        log "❌ 诊断: 本地文件不存在"
        return 1
    elif [[ "$error_output" == *"didn't find section in config file"* ]]; then
        log "❌ 诊断: Rclone 配置错误 - 远程存储不存在"
        return 1
    else
        log "⚠️ 诊断: 未知错误类型"
        return 0
    fi
}

# 上传前预处理函数
pre_upload_processing() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # 检查文件是否为空
    if [ -z "$file_path" ]; then
        log "❌ 文件路径为空"
        return 1
    fi
    
    # 检查文件权限
    if [ ! -r "$file_path" ]; then
        log "❌ 文件不可读: $filename"
        return 1
    fi
    
    # 检查文件是否正在被写入（可选）
    if command -v lsof >/dev/null 2>&1; then
        if lsof "$file_path" >/dev/null 2>&1; then
            log "⚠️ 文件可能正在被其他进程使用: $filename"
            # 可以添加重试逻辑或跳过
        fi
    fi
    
    # 记录文件信息
    local file_size=$(get_file_size "$file_path")
    local file_mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
    
    log "📋 文件信息: $filename (大小: $(format_size $file_size), 修改时间: $(date -d "@$file_mtime" '+%Y-%m-%d %H:%M:%S'))"
    
    return 0
}

# 上传后清理函数
post_upload_cleanup() {
    local file_path="$1"
    local upload_success="$2"
    
    if [ -z "$file_path" ]; then
        log "⚠️ 上传后清理: 文件路径为空"
        return
    fi
    
    if [ "$upload_success" = "true" ] && [ "$LEECHING_MODE" = "true" ]; then
        # 上传成功且启用吸血模式，文件会被 qBittorrent 删除
        log "ℹ️ 文件上传成功，等待 qBittorrent 删除: $(basename "$file_path")"
    elif [ "$upload_success" = "true" ] && [ "$LEECHING_MODE" != "true" ]; then
        log "ℹ️ 文件上传成功，保留本地文件: $(basename "$file_path")"
    else
        log "ℹ️ 文件上传失败，保留本地文件: $(basename "$file_path")"
    fi
}

# 上传统计函数
log_upload_statistics() {
    local start_time="$1"
    local total_files="$2"
    local successful_uploads="$3"
    local total_size="$4"
    local upload_duration="$5"
    
    local success_rate=0
    if [ "$total_files" -gt 0 ]; then
        success_rate=$((successful_uploads * 100 / total_files))
    fi
    
    local average_speed="0"
    if [ "$upload_duration" -gt 0 ] && [ "$total_size" -gt 0 ]; then
        local speed_bps=$((total_size / upload_duration))
        average_speed=$(echo "scale=2; $speed_bps / 1048576" | bc 2>/dev/null || echo "0")
    fi
    
    log "📈 上传统计:"
    log "  📁 总文件数: $total_files"
    log "  ✅ 成功上传: $successful_uploads"
    log "  📈 成功率: $success_rate%"
    log "  💾 总数据量: $(format_size $total_size)"
    log "  ⏱️ 总耗时: ${upload_duration}s"
    log "  🚀 平均速度: ${average_speed} MB/s"
    
    # 记录到详细统计文件
    local stats_entry="$(date '+%Y-%m-%d %H:%M:%S')|$total_files|$successful_uploads|$total_size|$upload_duration|$average_speed"
    echo "$stats_entry" >> "$LOG_DIR/upload_detailed_stats.log"
}