#!/bin/bash

# =============================================================================
# 文件类型过滤模块
# 功能：根据文件类型进行过滤
# =============================================================================

# 初始化文件类型过滤
init_file_filter() {
    if [ "$FILE_FILTER_ENABLE" != "true" ]; then
        log "ℹ️ 文件类型过滤已禁用"
        return 0
    fi
    
    # 验证过滤模式
    if [ "$FILE_FILTER_MODE" != "allow" ] && [ "$FILE_FILTER_MODE" != "deny" ]; then
        log "❌ 文件过滤模式配置错误: $FILE_FILTER_MODE，应为 'allow' 或 'deny'"
        return 1
    fi
    
    # 将文件类型列表转换为数组
    IFS=',' read -ra FILE_FILTER_TYPES_ARRAY <<< "$FILE_FILTER_TYPES"
    
    log "✅ 文件类型过滤已启用 - 模式: $FILE_FILTER_MODE, 类型: $FILE_FILTER_TYPES"
    return 0
}

# 获取文件扩展名
get_file_extension() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # 提取扩展名（小写）
    echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'
}

# 检查文件类型是否匹配
check_file_type() {
    local file_path="$1"
    local extension=$(get_file_extension "$file_path")
    
    if [ -z "$extension" ]; then
        log "⚠️ 文件无扩展名: $(basename "$file_path")"
        # 无扩展名文件的处理
        if [ "$FILE_FILTER_MODE" = "allow" ]; then
            return 1  # 在白名单模式下，无扩展名文件不被允许
        else
            return 0  # 在黑名单模式下，无扩展名文件不被阻止
        fi
    fi
    
    # 检查扩展名是否在过滤列表中
    local found=false
    for filter_type in "${FILE_FILTER_TYPES_ARRAY[@]}"; do
        # 清理类型字符串（去除空格）
        local clean_type=$(echo "$filter_type" | xargs)
        if [ "$extension" = "$clean_type" ]; then
            found=true
            break
        fi
    done
    
    # 根据过滤模式返回结果
    if [ "$FILE_FILTER_MODE" = "allow" ]; then
        # 白名单模式：只有在列表中的类型才允许
        if [ "$found" = "true" ]; then
            return 0
        else
            return 1
        fi
    else
        # 黑名单模式：在列表中的类型被阻止
        if [ "$found" = "true" ]; then
            return 1
        else
            return 0
        fi
    fi
}

# 过滤文件列表
filter_files_by_type() {
    local files=("$@")
    local filtered_files=()
    local skipped_count=0
    
    if [ "$FILE_FILTER_ENABLE" != "true" ]; then
        # 返回原始文件列表
        printf '%s\0' "${files[@]}"
        return 0
    fi
    
    log "🔍 开始文件类型过滤 (模式: $FILE_FILTER_MODE)"
    
    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            if check_file_type "$file_path"; then
                filtered_files+=("$file_path")
                log "✅ 文件类型允许: $(basename "$file_path")"
            else
                log "🚫 文件类型跳过: $(basename "$file_path") - 不符合过滤规则"
                ((skipped_count++))
            fi
        else
            # 如果是目录，保留（目录过滤在别处处理）
            filtered_files+=("$file_path")
        fi
    done
    
    log "📊 文件过滤完成: ${#filtered_files[@]}/${#files[@]} 个文件通过, $skipped_count 个被跳过"
    
    # 返回过滤后的文件数组
    printf '%s\0' "${filtered_files[@]}"
}

# 处理目录中的文件过滤
filter_directory_files() {
    local dir_path="$1"
    local filtered_files=()
    
    if [ "$FILE_FILTER_ENABLE" != "true" ] || [ ! -d "$dir_path" ]; then
        return 1
    fi
    
    log "🔍 过滤目录文件: $(basename "$dir_path")"
    
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && check_file_type "$file"; then
            filtered_files+=("$file")
        fi
    done < <(find "$dir_path" -type f -print0 2>/dev/null)
    
    # 返回过滤后的文件数组
    printf '%s\0' "${filtered_files[@]}"
}

# 获取文件类型统计
get_file_type_stats() {
    local files=("$@")
    declare -A type_count
    declare -A type_size
    
    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            local extension=$(get_file_extension "$file_path")
            local size=$(get_file_size "$file_path")
            
            if [ -z "$extension" ]; then
                extension="无扩展名"
            fi
            
            ((type_count["$extension"]++))
            type_size["$extension"]=$((type_size["$extension"] + size))
        fi
    done
    
    # 输出统计信息
    log "📊 文件类型统计:"
    for type in "${!type_count[@]}"; do
        log "  - $type: ${type_count[$type]} 个文件, $(format_size ${type_size[$type]})"
    done
}

# 验证文件类型配置
validate_file_filter_config() {
    if [ "$FILE_FILTER_ENABLE" != "true" ]; then
        return 0
    fi
    
    if [ -z "$FILE_FILTER_TYPES" ]; then
        log "❌ 文件类型过滤已启用但未设置文件类型列表"
        return 1
    fi
    
    if [ "$FILE_FILTER_MODE" != "allow" ] && [ "$FILE_FILTER_MODE" != "deny" ]; then
        log "❌ 文件过滤模式配置错误: $FILE_FILTER_MODE"
        return 1
    fi
    
    log "✅ 文件类型过滤配置验证通过"
    return 0
}