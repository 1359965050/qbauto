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


# 安装依赖

sudo apt-get install curl

sudo apt-get install jq

# 配置云存储

rclone config

# 设置 qBittorrent

在 qBittorrent 设置中配置执行脚本：

工具 → 选项 → 下载 → 运行外部程序

/bin/bash /path/to/qbauto.sh "%N" "%F" "%R" "%D" "%C" "%Z" "%I"

# 日志清理

日志文件会自动轮转，当主日志文件超过 10MB 时会自动备份为 qbauto.log.old。

# 故障排除

## 确保日志目录有写权限

chmod 755 /config/qbauto/log

## 检查所有日志文件

ls -la /config/qbauto/log/

## 查看最近错误

tail -20 /config/qbauto/log/qbauto.log

tail -20 /config/qbauto/log/rclone_errors.log

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






