# qBittorrent 自动上传脚本 (qbauto)

## 一个简单高效的 qBittorrent 下载完成后自动上传到云存储的 Bash 脚本。

# 功能特点

✅ 自动将下载完成的文件上传到云存储（支持 rclone）

✅ 吸血模式：上传完成后自动删除种子和文件

✅ 灵活的配置文件系统

✅ 详细的日志记录

✅ 支持单个文件和目录上传

✅ 自动获取种子哈希值

✅ 与 qBittorrent Web UI 集成

# 快速开始

## 配置云存储

rclone config

## 设置 qBittorrent

### 在 qBittorrent 设置中配置执行脚本：

### 工具 → 选项 → 下载 → 运行外部程序

/bin/bash /path/to/qbauto.sh "%N" "%F" "%R" "%D" "%C" "%Z" "%I"

## 故障排除

## 确保日志目录有写权限

chmod 755 /config/qbauto/log

## 检查所有日志文件

ls -la /config/qbauto/log

## 查看最近错误

tail -20 /config/qbauto/log/qbauto.log

