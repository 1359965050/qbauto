#!/bin/bash

# =============================================================================
# 黑名单模块
# 功能：黑名单文件检测和处理
# =============================================================================

# 安全删除文件或目录
safe_delete() {
    local path="$1"
    local reason="$2"
    
    if [ ! -e "$path" ]; then
        log "⚠️ 要删除的路径不存在: $path"
        return 0
    fi
    
    # 安全检查：确保路径在预期的下载目录内
    local safe_pattern="/downloads/"
    if [[ "$path" != *"$safe_pattern"* ]]; then
        log "❌ 安全警告: 尝试删除非下载目录内的文件: $path"
        return 1
    fi
    
    if [ -f "$path" ]; then
        if rm -f "$path"; then
            log "🗑️ 已删除文件 ($reason): $(basename "$path")"
            return 0
        else
            log "❌ 删除文件失败: $path"
            return 1
        fi
    elif [ -d "$path" ]; then
        # 对于目录，先检查是否为空
        if [ -z "$(ls -A "$path")" ]; then
            if rmdir "$path"; then
                log "🗑️ 已删除空目录 ($reason): $(basename "$path")"
                return 0
            else
                log "❌ 删除空目录失败: $path"
                return 1
            fi
        else
            log "⚠️ 目录非空，跳过删除: $path"
            return 0
        fi
    else
        log "⚠️ 未知类型的路径: $path"
        return 1
    fi
}

# 删除黑名单文件或目录
delete_blacklisted() {
    local path="$1"
    
    if [ "$DELETE_BLACKLISTED" != "true" ]; then
        log "ℹ️ 黑名单文件删除功能已禁用，跳过删除: $path"
        return 0
    fi
    
    log "🚫 开始删除黑名单内容: $path"
    
    if [ -f "$path" ]; then
        # 单个文件
        safe_delete "$path" "黑名单文件"
    elif [ -d "$path" ]; then
        # 目录 - 删除整个目录
        safe_delete "$path" "黑名单目录"
    fi
}

# 黑名单检查函数
check_blacklist() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # 如果没有设置黑名单关键词，直接通过
    if [ -z "$BLACKLIST_KEYWORDS" ]; then
        return 1
    fi
    
    # 将关键词转换为小写进行比较（不区分大小写）
    local lower_filename=$(echo "$filename" | tr '[:upper:]' '[:lower:]')
    local lower_keywords=$(echo "$BLACKLIST_KEYWORDS" | tr '[:upper:]' '[:lower:]')
    
    # 分割关键词为数组
    IFS=',' read -ra keywords <<< "$lower_keywords"
    
    for keyword in "${keywords[@]}"; do
        # 去除关键词前后的空格
        keyword_clean=$(echo "$keyword" | xargs)
        if [ -n "$keyword_clean" ] && [[ "$lower_filename" == *"$keyword_clean"* ]]; then
            log "🚫 文件包含黑名单关键词 '$keyword_clean': $filename"
            
            # 立即删除黑名单文件
            delete_blacklisted "$file_path"
            
            return 0  # 包含黑名单关键词
        fi
    done
    
    return 1  # 不包含黑名单关键词
}

# 检查文件夹是否包含黑名单文件
check_folder_blacklist() {
    local folder_path="$1"
    local has_blacklisted=false
    
    # 如果没有设置黑名单关键词，直接通过
    if [ -z "$BLACKLIST_KEYWORDS" ]; then
        return 1
    fi
    
    # 检查文件夹中的所有文件
    while IFS= read -r -d '' file; do
        if check_blacklist "$file"; then
            log "🚫 文件夹包含黑名单文件: $(basename "$file")"
            has_blacklisted=true
        fi
    done < <(find "$folder_path" -type f -print0 2>/dev/null)
    
    # 如果文件夹中有黑名单文件，删除整个文件夹
    if [ "$has_blacklisted" = true ] && [ "$DELETE_BLACKLISTED" = "true" ]; then
        log "🚫 文件夹包含黑名单文件，删除整个文件夹: $(basename "$folder_path")"
        delete_blacklisted "$folder_path"
        return 0  # 文件夹包含黑名单文件
    fi
    
    return 1  # 文件夹不包含黑名单文件
}

# 处理黑名单内容
process_blacklisted_content() {
    local content_path="$1"
    
    if [ -z "$BLACKLIST_KEYWORDS" ] || [ "$DELETE_BLACKLISTED" != "true" ]; then
        return 0
    fi
    
    log "🔍 检查黑名单内容: $content_path"
    
    if [ -f "$content_path" ]; then
        # 单个文件
        check_blacklist "$content_path"
    elif [ -d "$content_path" ]; then
        # 目录
        check_folder_blacklist "$content_path"
    fi
}
