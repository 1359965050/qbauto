#!/bin/bash

# =============================================================================
# 模块加载器
# 功能：动态加载所有模块
# =============================================================================

# 模块加载函数
load_modules() {
    local modules=(
        "core.sh"
        "logger.sh" 
        "config.sh"
        "health.sh"
        "network.sh"
        "storage.sh"
        "upload.sh"
        "blacklist.sh"
        "stats.sh"
        "performance.sh"
        "qbittorrent.sh"
    )
    
    for module in "${modules[@]}"; do
        local module_path="${MODULES_DIR}/${module}"
        if [ -f "$module_path" ]; then
            source "$module_path"
            log "✅ 加载模块: $module"
        else
            log "❌ 模块不存在: $module"
            return 1
        fi
    done
    
    return 0
}

# 自动加载所有模块
load_modules