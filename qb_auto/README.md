qBittorrent 自动上传脚本 (qbauto)

一个简单高效的 qBittorrent 下载完成后自动上传到云存储的 Bash 脚本。

功能特点

✅ 自动上传下载完成的文件到云存储

✅ 支持单个文件和整个目录上传

✅ 可配置的过滤规则（白名单/黑名单）

✅ 吸血模式（上传后自动删除种子）

✅ 详细的日志记录

✅ 速率限制和重试机制

✅ 轻量级，依赖少

快速开始

# 创建目录结构

mkdir -p /config/qbauto/log

# 安装依赖

sudo apt-get install curl

# 可选：用于更好的 JSON 解析

sudo apt-get install jq

# 配置云存储

rclone config

# 创建配置文件
在 /config/qbauto/qbauto.conf 创建配置文件

# 基础配置
QB_WEB_URL="http://localhost:8080"

QB_USERNAME="admin"

QB_PASSWORD="your_password"

# Rclone 配置
RCLONE_DEST="your_remote_name"

UPLOAD_PATH="/uploads"

# 日志配置
LOG_DIR="/config/qbauto/log"    # 所有日志文件目录

# 运行模式
LEECHING_MODE="true"

# 设置 qBittorrent

在 qBittorrent 设置中配置执行脚本：

工具 → 选项 → 下载 → 运行外部程序

/bin/bash /path/to/qbauto.sh "%N" "%F" "%R" "%D" "%C" "%Z" "%I"

# 日志管理

log/qbauto.log	主运行日志，记录脚本执行过程

log/rclone.log	rclone 上传详细日志

log/rclone_errors.log	rclone 错误日志

log/qb_cookie.txt	临时登录 cookie（自动清理）

log/upload_count.txt	上传计数文件（速率限制用）

# 查看日志

# 实时查看主日志
tail -f /config/qbauto/log/qbauto.log

# 查看上传日志
tail -f /config/qbauto/log/rclone.log

# 查看错误日志
tail -f /config/qbauto/log/rclone_errors.log

# 日志清理

日志文件会自动轮转，当主日志文件超过 10MB 时会自动备份为 qbauto.log.old。

# 清理所有日志
rm -f /config/qbauto/log/*.log

# 只清理旧的日志备份
rm -f /config/qbauto/log/*.old

# 配置说明

配置项	     说明	            示例

QB_WEB_URL	qBittorrent地址	 http://localhost:8080

QB_USERNAME	qBittorrent用户名  admin

QB_PASSWORD	qBittorrent密码  password

RCLONE_DEST	rclone 远程存储名称	mydrive

UPLOAD_PATH	云存储上传路径  /downloads

LOG_DIR  日志文件目录  /config/qbauto/log

# 可选配置

## 运行模式
LEECHING_MODE="true"

## 上传优化
RCLONE_BWLIMIT="10M"
RCLONE_PARALLEL="4"
MAX_RETRIES="3"

## 过滤规则
WHITELIST_KEYWORDS="movie,series"
BLACKLIST_KEYWORDS="sample,nfo"
ALLOWED_EXTENSIONS="mkv,mp4,avi"

## 速率限制
RATE_LIMIT_ENABLED="true"
MAX_UPLOADS_PER_HOUR="6"
UPLOAD_COOLDOWN="600"

# 故障排除

## 确保日志目录有写权限
chmod 755 /config/qbauto/log

## 检查所有日志文件
ls -la /config/qbauto/log/

## 查看最近错误
tail -20 /config/qbauto/log/qbauto.log
tail -20 /config/qbauto/log/rclone_errors.log

## 手动运行脚本测试
/bin/bash /path/to/qbauto.sh "测试种子" "/path/to/file"

## 检查日志输出
tail -f /config/qbauto/log/qbauto.log

# 更新日志

## v1.0

### 基础文件上传功能

### 配置文件支持

### 基础日志系统

## v1.1

### 添加文件过滤功能

### 吸血模式支持

### 速率限制机制

## v1.2

### 性能优化

### 错误处理改进

### 文档完善

## v1.3

### 将所有日志文件统一移动到 log 目录

### 改善日志文件管理

### 简化目录结构




