# 存储配置示例文档

本文档提供了 qBittorrent 自动上传脚本支持的所有存储类型的详细配置示例。

## 支持的存储类型

当前支持的存储类型：
1. **Rclone 远程存储** (`rclone`)
2. **本地存储** (`local`)
3. **Amazon S3 兼容存储** (`s3`)
4. **FTP/SFTP 存储** (`ftp`)
5. **WebDAV 存储** (`webdav`)

## 1. Rclone 远程存储配置示例

### qbauto.conf 配置
```bash
# 存储配置列表
STORAGE_CONFIGS='{
  "onedrive_storage": {
    "rclone_dest": "onedrive",
    "upload_path": "qbittorrent",
    "description": "OneDrive 云存储",
    "type": "rclone"
  },
  "google_drive_storage": {
    "rclone_dest": "gdrive",
    "upload_path": "downloads",
    "description": "Google Drive 存储",
    "type": "rclone"
  },
  "dropbox_storage": {
    "rclone_dest": "dropbox",
    "upload_path": "backup",
    "description": "Dropbox 存储",
    "type": "rclone"
  }
}'
```

### rclone.conf 配置示例
```ini
# OneDrive 配置
[onedrive]
type = onedrive
client_id = your_client_id
client_secret = your_client_secret
region = cn
token = {"access_token":"your_access_token","refresh_token":"your_refresh_token"}
drive_id = your_drive_id
drive_type = business

# Google Drive 配置
[gdrive]
type = drive
client_id = your_client_id
client_secret = your_client_secret
scope = drive
token = {"access_token":"your_access_token","refresh_token":"your_refresh_token"}

# Dropbox 配置
[dropbox]
type = dropbox
client_id = your_client_id
client_secret = your_client_secret
token = {"access_token":"your_access_token","refresh_token":"your_refresh_token"}
```

## 2. 本地存储配置示例

### qbauto.conf 配置
```bash
STORAGE_CONFIGS='{
  "local_backup": {
    "rclone_dest": "/mnt/backup",
    "upload_path": "qbittorrent",
    "description": "本地备份存储",
    "type": "local"
  },
  "nas_storage": {
    "rclone_dest": "/mnt/nas/downloads",
    "upload_path": "torrents",
    "description": "NAS 网络存储",
    "type": "local"
  },
  "external_drive": {
    "rclone_dest": "/media/external",
    "upload_path": "backup",
    "description": "外置硬盘存储",
    "type": "local"
  }
}'
```

### 注意事项
- 确保本地目录有读写权限
- 路径必须是绝对路径
- 建议使用挂载点而不是符号链接

## 3. Amazon S3 兼容存储配置示例

### qbauto.conf 配置
```bash
STORAGE_CONFIGS='{
  "aws_s3": {
    "rclone_dest": "s3:bucket-name/path",
    "upload_path": "qbittorrent",
    "description": "AWS S3 存储",
    "type": "s3"
  },
  "minio_storage": {
    "rclone_dest": "s3:minio-bucket/backup",
    "upload_path": "downloads",
    "description": "MinIO 私有云存储",
    "type": "s3"
  },
  "backblaze_b2": {
    "rclone_dest": "b2:bucket-name/folder",
    "upload_path": "torrents",
    "description": "Backblaze B2 存储",
    "type": "s3"
  }
}'
```

### rclone.conf 配置示例
```ini
# AWS S3 配置
[aws_s3]
type = s3
provider = AWS
access_key_id = your_access_key
secret_access_key = your_secret_key
region = us-east-1

# MinIO 配置
[minio]
type = s3
provider = MinIO
access_key_id = your_minio_access_key
secret_access_key = your_minio_secret_key
endpoint = http://minio-server:9000
region = us-east-1

# Backblaze B2 配置
[b2]
type = b2
account = your_account_id
key = your_application_key
```

## 4. FTP/SFTP 存储配置示例

### qbauto.conf 配置
```bash
STORAGE_CONFIGS='{
  "ftp_server": {
    "rclone_dest": "ftp://user:pass@ftp.server.com/path",
    "upload_path": "uploads",
    "description": "FTP 服务器存储",
    "type": "ftp"
  },
  "sftp_storage": {
    "rclone_dest": "sftp://user@server.com:port/path",
    "upload_path": "backup",
    "description": "SFTP 安全存储",
    "type": "ftp"
  }
}'
```

### rclone.conf 配置示例
```ini
# FTP 配置
[ftp_storage]
type = ftp
host = ftp.server.com
user = username
pass = password

# SFTP 配置（使用密钥文件）
[sftp_storage]
type = sftp
host = sftp.server.com
user = username
key_file = /path/to/private_key
```

### 安全配置选项
- 使用 SFTP 替代 FTP 以提高安全性
- 建议使用密钥认证而非密码
- 配置适当的端口和超时设置

## 5. WebDAV 存储配置示例

### qbauto.conf 配置
```bash
STORAGE_CONFIGS='{
  "nextcloud_storage": {
    "rclone_dest": "webdav://nextcloud.server.com/remote.php/dav/files/user",
    "upload_path": "qbittorrent",
    "description": "Nextcloud WebDAV 存储",
    "type": "webdav"
  },
  "owncloud_storage": {
    "rclone_dest": "webdav://owncloud.server.com/remote.php/webdav",
    "upload_path": "downloads",
    "description": "OwnCloud WebDAV 存储",
    "type": "webdav"
  }
}'
```

### rclone.conf 配置示例
```ini
# Nextcloud WebDAV 配置
[nextcloud]
type = webdav
url = https://nextcloud.server.com/remote.php/dav/files/username
vendor = nextcloud
user = username
pass = password

# OwnCloud WebDAV 配置
[owncloud]
type = webdav
url = https://owncloud.server.com/remote.php/webdav
vendor = owncloud
user = username
pass = password
```

## 完整配置示例

### 多存储配置示例
```bash
# qbauto.conf 中的完整存储配置示例
STORAGE_CONFIGS='{
  "primary_storage": {
    "rclone_dest": "onedrive",
    "upload_path": "qbittorrent",
    "description": "主存储 - OneDrive",
    "type": "rclone"
  },
  "backup_storage": {
    "rclone_dest": "s3:backup-bucket/qbittorrent",
    "upload_path": "backup",
    "description": "备份存储 - AWS S3",
    "type": "s3"
  },
  "local_cache": {
    "rclone_dest": "/mnt/cache",
    "upload_path": "cache",
    "description": "本地缓存存储",
    "type": "local"
  },
  "nas_archive": {
    "rclone_dest": "sftp://user@nas.local:22/mnt/archive",
    "upload_path": "archive",
    "description": "NAS 归档存储",
    "type": "ftp"
  },
  "cloud_sync": {
    "rclone_dest": "webdav://nextcloud.cloud.com/remote.php/dav/files/user",
    "upload_path": "sync",
    "description": "云同步存储",
    "type": "webdav"
  }
}'
```

### 对应的 rclone.conf 配置
```ini
# OneDrive 配置
[onedrive]
type = onedrive
client_id = your_client_id
client_secret = your_client_secret
region = cn
token = {"access_token":"your_token"}

# AWS S3 配置
[s3_backup]
type = s3
provider = AWS
access_key_id = your_aws_key
secret_access_key = your_aws_secret
region = us-east-1

# SFTP 配置
[sftp_nas]
type = sftp
host = nas.local
user = username
key_file = /root/.ssh/id_rsa

# WebDAV 配置
[webdav_sync]
type = webdav
url = https://nextcloud.cloud.com/remote.php/dav/files/username
vendor = nextcloud
user = username
pass = password
```

## 配置最佳实践

### 1. 存储命名规范
- 使用有意义的存储名称
- 避免使用特殊字符
- 保持名称简洁明了

### 2. 路径配置建议
- 使用绝对路径
- 避免路径过长
- 考虑跨平台兼容性

### 3. 安全配置
- 保护敏感信息（API密钥、密码等）
- 使用环境变量存储敏感数据
- 定期轮换访问凭证

### 4. 性能优化
- 根据存储类型调整并发设置
- 配置适当的超时和重试参数
- 监控存储性能指标

## 故障排除

### 常见问题
1. **连接失败**：检查网络连接和认证信息
2. **权限错误**：验证存储目录的读写权限
3. **配置错误**：确认配置格式和参数正确性