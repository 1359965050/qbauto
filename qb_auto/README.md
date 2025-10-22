# qBittorrent 自动上传脚本

## 功能简介

这是一个用于 qBittorrent 的自动上传脚本，主要功能包括：

- ✅ 自动上传完成的文件到云存储（支持各种 rclone 远程存储）
- ✅ 支持吸血模式（上传完成后自动删除种子）
- ✅ 支持单个文件和目录上传
- ✅ 自动重试机制
- ✅ 详细的日志记录

## 安装步骤

### 1. 创建目录结构
```
mkdir -p /config/qbauto/log
```
### 2. 放置脚本文件
```
/config/qbauto/
├── qbauto.sh      # 主脚本
├── qbauto.conf    # 配置文件
└── log/           # 日志目录
```
### 3. 设置脚本权限
```
chmod +x /config/qbauto/qbauto.sh
```
### 4. 配置 qBittorrent
```
进入 工具 → 选项 → 下载

** torrent 完成时运行外部程序** 勾选

程序路径填写：/config/qbauto/qbauto.sh

参数填写："%N" "%F" "%D" "%R" "%C" "%Z" "%I"
```
### 5.配置说明

| 主要配置项  | 说明|
| ---------- | -----------|
|RCLONE_DEST|rclone 远程存储名称|
|UPLOAD_PATH|上传到远程存储的路径|
|LEECHING_MODE|吸血模式|
|QB_WEB_URL|qBittorrent WebUI 地址|
|QB_USERNAME/QB_PASSWORD|qBittorrent 登录凭据|

Rclone 配置文件解决方案
问题描述
脚本需要访问 rclone 配置文件，但配置文件可能位于不同位置。

解决方案
方法1：手动指定配置文件路径（推荐）

在 qbauto.conf 中设置：

bash
RCLONE_CONFIG=/config/rclone/rclone.conf
方法2：自动查找

如果未指定 RCLONE_CONFIG，脚本会自动搜索以下位置：

/config/rclone/rclone.conf

/etc/rclone/rclone.conf

/home/qbittorrent/.config/rclone/rclone.conf

/root/.config/rclone/rclone.conf

rclone 默认配置路径

方法3：查找现有配置文件

在容器内执行以下命令查找现有配置文件：

bash
# 查找所有 rclone.conf 文件
find / -name "rclone.conf" 2>/dev/null

# 检查常见位置
ls -la /config/rclone/ 2>/dev/null
ls -la /etc/rclone/ 2>/dev/null
ls -la ~/.config/rclone/ 2>/dev/null

# 查看 rclone 默认配置路径
rclone config file
方法4：复制配置文件到标准位置

bash
# 创建目录
mkdir -p /config/rclone/

# 复制配置文件（替换为实际路径）
cp /实际/路径/rclone.conf /config/rclone/rclone.conf

# 设置正确权限
chmod 644 /config/rclone/rclone.conf
Docker 环境特殊说明
如果使用 Docker，确保正确挂载 rclone 配置文件：

bash
# 在 docker run 命令中添加挂载
-v /宿主机/rclone配置目录:/config/rclone:rw
故障排除
1. 检查日志
查看详细日志：

bash
tail -f /config/qbauto/log/qbauto.log
2. 手动测试脚本
bash
# 模拟调用脚本
/config/qbauto/qbauto.sh "测试文件" "/downloads/测试路径"
3. 测试 rclone 连接
bash
# 测试远程存储连接
rclone lsd your_remote_name:

# 测试上传
rclone copy /local/path/file.txt your_remote_name:/remote/path/
4. 检查权限
确保脚本有足够权限：

bash
# 检查文件权限
ls -la /config/qbauto/qbauto.sh
ls -la /config/rclone/rclone.conf

# 检查目录权限
ls -la /config/qbauto/
常见问题
Q: 脚本报错 "rclone 配置文件不存在"
A: 参考上面的 "Rclone 配置文件解决方案"

Q: 上传成功但种子没有删除
A: 检查吸血模式配置和 qBittorrent API 连接

Q: 上传速度慢
A: 调整 rclone 传输参数或检查网络连接

更新日志
v1.0: 初始版本，支持基本上传和吸血模式

v1.1: 增加自动重试机制和更好的错误处理

v1.2: 改进 rclone 配置文件自动查找功能

技术支持
如有问题，请检查日志文件并提供错误信息。

text

## 使用方法

1. 将 `qbauto.sh` 保存为可执行文件
2. 根据你的环境修改 `qbauto.conf` 中的配置
3. 将 `README.md` 作为使用文档参考

这些文件已经包含了我们测试成功的所有功能，包括自动查找 rclone 配置文件的智能机制。
