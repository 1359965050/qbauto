#!/bin/bash

# =============================================================================
# qBittorrent 集成模块
# 功能：与 qBittorrent WebUI 交互
# =============================================================================

# 获取十六进制哈希值
get_hex_hash() {
    local torrent_name="$1"
    local content_dir="$2"
    shift 2

    log "🔍 开始获取种子哈希值"
    
    # 方法1: 遍历所有参数寻找40位十六进制哈希
    local i=1
    for arg in "$@"; do
        if [[ "$arg" =~ ^[a-fA-F0-9]{40}$ ]]; then
            log "✅ 从参数$i获取到十六进制哈希: $arg"
            echo "$arg"
            return 0
        fi
        ((i++))
    done

    # 方法2: 尝试从qBittorrent API获取哈希值
    if [ -n "$QB_WEB_URL" ] && [ -n "$QB_USERNAME" ] && [ -n "$QB_PASSWORD" ]; then
        log "🔑 尝试通过API获取哈希值"
        local cookie_file="$LOG_DIR/qb_cookie.txt"
        
        # 登录qBittorrent
        local login_result
        login_result=$(curl -s -c "$cookie_file" -X POST \
            --data-urlencode "username=$QB_USERNAME" \
            --data-urlencode "password=$QB_PASSWORD" \
            "$QB_WEB_URL/api/v2/auth/login" 2>&1)
        
        local login_exit_code=$?
        
        if [ $login_exit_code -eq 0 ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
            log "✅ API登录成功"
            
            # 获取种子列表并查找匹配的种子
            local torrent_list=$(curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/torrents/info" 2>&1)
            local hex_hash=$(echo "$torrent_list" | \
                jq -r --arg name "$torrent_name" --arg path "$(dirname "$content_dir")" \
                '.[] | select(.name == $name and .save_path == $path) | .hash' 2>/dev/null)
            
            rm -f "$cookie_file"
            
            if [ -n "$hex_hash" ] && [ "$hex_hash" != "null" ]; then
                log "✅ 通过API获取到哈希值: $hex_hash"
                echo "$hex_hash"
                return 0
            else
                log "❌ API未找到匹配的种子"
            fi
        else
            log "❌ API登录失败，退出码: $login_exit_code"
            log "❌ 登录响应: $login_result"
        fi
    else
        log "⚠️ 缺少API配置信息，跳过API获取"
    fi
    
    # 方法3: 生成基于名称和路径的伪哈希
    local fallback_hash=$(echo -n "${torrent_name}${content_dir}" | sha1sum | cut -d' ' -f1)
    log "⚠️ 所有方法失败，使用回退哈希: $fallback_hash"
    echo "$fallback_hash"
}

# 处理种子（吸血模式）
process_torrent() {
    if [ "$LEECHING_MODE" != "true" ]; then
        log "ℹ️ 吸血模式未启用，跳过种子处理"
        return 0
    fi

    local torrent_hash="$1"
    
    if [ -z "$torrent_hash" ]; then
        log "❌ 吸血模式需要种子哈希值，但获取到的哈希值为空"
        return 1
    fi
    
    log "🔧 开始吸血模式处理，种子哈希: $torrent_hash"
    
    # 检查必要的API配置
    if [ -z "$QB_WEB_URL" ] || [ -z "$QB_USERNAME" ] || [ -z "$QB_PASSWORD" ]; then
        log "❌ 吸血模式需要设置 QB_WEB_URL, QB_USERNAME, QB_PASSWORD"
        return 1
    fi

    local cookie_file="$LOG_DIR/qb_cookie.txt"
    
    # 登录 qBittorrent
    log "🔑 尝试登录qBittorrent..."
    local login_response
    login_response=$(curl -s -w "%{http_code}" -c "$cookie_file" -X POST \
        --data-urlencode "username=$QB_USERNAME" \
        --data-urlencode "password=$QB_PASSWORD" \
        "$QB_WEB_URL/api/v2/auth/login" 2>&1)
    
    local http_code="${login_response: -3}"
    local response_body="${login_response%???}"
    
    log "🔧 登录响应状态码: $http_code"
    
    if [ "$http_code" = "200" ] && [ -f "$cookie_file" ] && grep -q "SID" "$cookie_file"; then
        log "✅ 登录成功，准备删除种子"
        
        # 删除种子（使用十六进制哈希）
        log "🗑️ 发送删除请求，哈希: $torrent_hash"
        local delete_response
        delete_response=$(curl -s -w "%{http_code}" -b "$cookie_file" -X POST \
            --data-urlencode "hashes=$torrent_hash" \
            --data-urlencode "deleteFiles=true" \
            "$QB_WEB_URL/api/v2/torrents/delete" 2>&1)
        
        local delete_http_code="${delete_response: -3}"
        
        log "🔧 删除响应状态码: $delete_http_code"
        
        if [ "$delete_http_code" = "200" ]; then
            log "✅ 种子删除请求发送成功"
            
            # 验证种子是否真的被删除
            sleep 2
            local verify_response=$(curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/torrents/info")
            if echo "$verify_response" | jq -e --arg hash "$torrent_hash" '.[] | select(.hash == $hash)' >/dev/null 2>&1; then
                log "❌ 种子仍然存在，删除可能失败"
            else
                log "✅ 种子确认已删除"
            fi
        else
            log "❌ 种子删除请求失败，HTTP状态码: $delete_http_code"
            log "❌ 删除响应: ${delete_response%???}"
        fi
        
        # 登出
        curl -s -b "$cookie_file" "$QB_WEB_URL/api/v2/auth/logout" >/dev/null 2>&1
        rm -f "$cookie_file"
    else
        log "❌ 登录失败，HTTP状态码: $http_code"
        log "❌ 登录响应: $response_body"
        log "🔧 检查项目:"
        log "  - QB_WEB_URL: $QB_WEB_URL"
        log "  - QB_USERNAME: $QB_USERNAME"
        log "  - QB_PASSWORD: [已设置]"
        log "  - WebUI是否启用: 请检查qBittorrent设置"
        return 1
    fi
    
    log "🔧 吸血模式处理完成"
    return 0
}