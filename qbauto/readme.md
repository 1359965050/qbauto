qBittorrent 自动上传脚本
一个功能强大的 qBittorrent 自动上传脚本，支持文件过滤、黑名单检测、多平台通知和智能重试机制。

📋 功能特性
核心功能
🔄 自动上传: 自动将 qBittorrent 下载完成的文件上传到云存储

🚫 黑名单过滤: 根据关键词自动过滤和删除不需要的内容

📁 文件类型过滤: 支持白名单和黑名单文件类型过滤

💾 吸血模式: 上传完成后自动删除种子和文件

🔍 上传验证: 验证上传文件的完整性和大小

智能管理
🏥 健康检查: 系统状态监控和自愈机制

🌐 网络检测: 网络质量检测和连接测试

💽 存储检查: 本地和远程存储空间监控

📊 性能监控: 详细的性能统计和报告

🔄 智能重试: 自适应重试机制和指数退避

通知系统
📱 多平台通知: 支持 Telegram、Server 酱（旧版和Turbo版）

🎯 任务类型推送: 可配置不同任务类型的通知开关

📈 统计摘要: 定期统计报告和性能分析

🛠 系统要求
必需组件
操作系统: Linux (推荐 Ubuntu/Debian/CentOS)

qBittorrent: 4.3.0+ (支持 WebUI)

rclone: 1.60.0+

bash: 4.4+

核心工具: curl, jq, find, stat

可选组件
bc: 用于精确计算

lsof: 用于文件锁定检测

📥 安装步骤
1. 下载脚本
bash
git clone <repository-url>
cd qbauto
2. 目录结构
text
/config/qbauto/
├── qbauto.sh              # 主脚本
├── qbauto.conf           # 配置文件
├── modules/              # 功能模块
│   ├── core.sh          # 核心功能
│   ├── config.sh        # 配置管理
│   ├── upload.sh        # 上传功能
│   ├── notify.sh        # 通知系统
│   └── ...             # 其他模块
└── log/                 # 日志目录
3. 权限设置
bash
chmod +x qbauto.sh
chmod +x modules/*.sh
4. rclone 配置
bash
# 将 rclone 配置文件复制到指定位置
cp /path/to/your/rclone.conf /config/qbauto/rclone.conf
chmod 600 /config/qbauto/rclone.conf
🚀 使用方法
基本使用
bash
# 手动执行上传
./qbauto.sh "种子名称" "/path/to/downloads"

# 作为 qBittorrent 完成下载后执行脚本
# 在 qBittorrent 设置中配置：
# Tools -> Options -> Downloads -> Run external program on torrent completion
# 命令: /config/qbauto/qbauto.sh "%N" "%F"
命令行选项
bash
# 健康检查
./qbauto.sh health-check

# 测试通知
./qbauto.sh test-notify

# 准备 rclone 配置
./qbauto.sh prepare-rclone-config
qBittorrent 集成
打开 qBittorrent WebUI

进入 工具 → 选项 → 下载

在 Torrent 完成时运行外部程序 中输入：

text
/path/to/qbauto.sh "%N" "%F"
勾选 仅当 torrent 按顺序下载时运行

🔧 故障排除
常见问题
1. 权限问题
bash
# 检查脚本权限
chmod +x qbauto.sh modules/*.sh

# 检查目录权限
chmod 755 /config/qbauto
chmod 600 /config/qbauto/rclone.conf
2. rclone 连接失败
检查 rclone.conf 文件路径和权限

验证远程存储名称是否正确

测试 rclone 连接：rclone lsd remote_name:

3. qBittorrent API 连接失败
确认 WebUI 已启用

检查用户名和密码

验证 API 地址和端口

4. 通知发送失败

检查通知配置参数

验证网络连接

查看详细日志输出

日志查看

bash
# 查看实时日志
tail -f /config/qbauto/log/qbauto.log

# 查看 rclone 上传日志
tail -f /config/qbauto/log/rclone.log

# 查看性能统计
cat /config/qbauto/log/performance.csv

🛡️ 许可证
本项目采用 MIT 许可证。详见 LICENSE 文件。

🤝 贡献
欢迎提交 Issue 和 Pull Request！

📞 支持
如果遇到问题，请：

查看日志文件获取详细错误信息

检查配置文件是否正确

查阅本 README 的故障排除部分

提交 Issue 并提供相关日志

注意: 使用本脚本前，请确保您有权限上传相关内容，并遵守相关服务条款和法律法规。
