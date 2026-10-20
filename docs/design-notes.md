# 设计记录

## 本次实现提案

从仅含文档的仓库扩展为单镜像、单非 root 用户的 Claude Code + Codex + Bun 环境。
基础为 Debian stable-slim，构建时解析 stable/native 软件，不运行 npm 安装链。
SSH/SFTP 与 tmux 是基础接入；两种工具各自的官方远程能力按自己的账户要求和生命周期使用。

配置使用专用容器 home 卷，项目逐个 bind mount。home 包含 .codex、.claude、
.claude.json 和用户 Bun globals；不是用户真实宿主 home。
native 工具安装在 /opt/agent-tools。Codex 默认以前台 --no-daemon 模式运行，
入口不重定向 package 目录、不修改 daemon settings。
默认 launcher 直接使用镜像内 native package，旧 home 中同名命令不会在默认 PATH 下优先。
高级 daemon 模式的包持久化、自动更新和生命周期不由本实现管理。

镜像默认不自动升级。标准升级是拉取/构建新镜像后重建容器；
显式手动更新只改当前容器层。fresh build 使用 --pull --no-cache。
构建记录 resolved versions、下载/二进制 SHA-256、Debian 包版本与 custom hook hash。

独立透明代理只是可选集成。已有同机 SOCKS 可以复用，但其可达地址、最终出口、
DNS/IPv6/UDP、故障阻断和 SSH 回程未验证。agent 不持有网络管理权。
不把代理变量当全流量保证，也不承诺服务方无法识别代理。

## 保留边界

- 不安装 sudo，不默认安装 Node/npm，不挂载 Docker socket，不给 agent privileged
- 自定义工具通过 fork 的 build-time shell hook 添加；失败停止构建，无内嵌凭据
- 没有自动构建发布、CI、服务器修改或网络部署
- 保留已有 MIT LICENSE；第三方软件遵循各自许可与服务条款
- 本提案尚未通过实际构建/运行验收，参见 validation.md
