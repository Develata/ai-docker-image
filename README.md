# ai-docker-image

Debian slim 上的 Claude Code、Codex 和 Bun 单用户开发环境。

本变更是待验证的实现提案；尚未完成镜像构建、SSH 实测、远程会话或代理验收。
仓库代码使用 MIT；内置第三方工具分别适用其许可证与服务条款，发布镜像前应检查再分发条件。

## 组成

- Claude Code 官方 native stable 通道、Codex 最新非预发布完整 native package、Bun 最新稳定版
- Git、Bash、CA、curl、jq、ripgrep、tmux、rsync、SSH/SFTP、常用文件和进程工具
- 默认 agent 非 root 用户，不安装 sudo、Node 或 npm，不开放 Docker socket
- 容器内非 root sshd 监听 2222，仅接受公钥；宿主机端口默认仅绑定 127.0.0.1
- 独立容器 home 卷持久化配置、认证和历史；两个示例项目分别 bind mount
- 镜像内 native 工具与持久化状态分开。启动时不运行下载/更新命令

这不是恶意代码安全沙箱。agent 能读写所有挂载给它的项目和账户凭据，并能修改自身可写工具目录。
Codex/Claude 内部沙箱依赖宿主内核、user namespaces、seccomp/AppArmor 等；不能据此假定已生效。
不通过 privileged、SYS_ADMIN 或关闭所有 seccomp 来掩盖兼容性问题。

## 首次运行

宿主机需要 Docker Engine 和 Docker Compose。示例面向 Linux；UID/GID、TUN 和文件权限在 Docker Desktop 上需另测。

1. 复制 .env.example 为 .env，填写两个已存在项目的绝对路径。
   Linux 上将 AGENT_UID / AGENT_GID 设为项目所有者对应数字；同一镜像只定义一个 agent 用户。
   如果只有一个项目，删除 Compose 的第二个挂载；添加项目时新增同样的 bind mount。
2. 创建 runtime 目录，把允许登录的公钥放入 runtime/authorized_keys。
   仅复制公钥，不能复制私钥。该文件需要容器 agent UID 可读；可使用 mode 0644，
   其父目录必须允许遍历。读取后容器复制为自己拥有的 mode 0600 文件。
3. 执行 bash scripts/build.sh，然后 docker compose up -d --no-build。
4. 查看 docker compose logs agent 输出的 SSH host key 指纹，通过可信方式核对后登录：
   ssh -p 2222 agent@127.0.0.1
   远程使用时，先 SSH 到宿主机，或在客户端创建宿主机本地转发：
   ssh -N -L 2222:127.0.0.1:2222 YOUR_HOST
   再在另一个终端执行上述容器 SSH 命令。不要关闭主机密钥检查。
5. 容器内 cd /workspaces/project-one，然后运行 claude 或 codex，按官方流程登录。
   不把真实 API key 放入 Dockerfile、build args、示例文件或公开提交。

sshd 配置关闭了容器内的 SSH forwarding。宿主机的外层 SSH 转发不受此配置控制。
默认无密码登录、无 root 登录、无 SSH agent forwarding。公钥变化后重启容器，使入口重新读取它。
首次 SSH 登录和 nonroot sshd 的兼容性仍需实际验收；TCP healthcheck 仅表示端口监听。
agent 使用不可用于 Unix 密码认证的 * 标记；不设置空密码或嵌入密码。
SSH 同时通过 AuthenticationMethods publickey、PasswordAuthentication no、
KbdInteractiveAuthentication no 和 PermitRootLogin no 限制认证方式。

## 持久化与权限

agent-home 是专用于容器的新 home 卷，不是宿主机真实 home：
- ~/.codex：Codex 配置、认证、历史和会话数据
- ~/.claude 与 ~/.claude.json：Claude 配置和登录状态，支持文件原子替换
- ~/.bun：用户通过 Bun 安装的全局包
- ~/.ssh-host：SSH host key，重建后保持主机身份
- 其他主动写入该 home 的文件同样会持久化

首次创建命名卷时 Docker 会复制镜像的 /home/agent 和对应所有权。
旧卷不会因重新构建 UID/GID 自动变更。启动失败时先检查所有者，不能让入口以 root
递归 chown 所有挂载目录。不要让多个容器同时使用同一个 home 卷。
项目 bind mounts 不会被入口 chown；它们必须事先具有正确权限。

native CLI 安装在 /opt/agent-tools，不在 home 卷中。
默认 codex launcher 使用 --no-daemon，直接运行当前镜像内的完整 native package。
入口不创建、移动或修改 ~/.codex/packages，也不改写 daemon settings。
已有 daemon/package 状态可能随 home 持久化，但默认前台模式不会选择它们。
这不覆盖用户主动绕过 launcher 或改写 shell PATH 的情况。

不要挂载整个宿主机 home、/var/run/docker.sock、宿主根目录或凭据目录。
备份 home 卷时要视为敏感数据；不要上传到公开仓库。
docker compose down 默认保留命名卷；down -v 会删除它，不能作为普通升级命令。

## 更新

每次需要最新稳定工具时运行 bash scripts/build.sh。它使用 --pull --no-cache，
刷新 Debian 基础镜像、apt 索引和 native 稳定版本。普通 docker compose build
可能复用缓存，不保证取到当天最新版本。Debian 包使用发行版维护的版本，
不承诺每一个工具都等于其上游最新版本。

镜像升级的标准路径是：
- 使用自己的已发布镜像时，在 .env 中设置 AGENT_IMAGE，然后 docker compose pull agent
- docker compose up -d --no-build --force-recreate agent

本仓库没有自动发布镜像；默认 ai-agent:local 使用本机构建。
本地构建升级后同样执行 force-recreate。不要用 docker compose restart 代替换镜像。
保存好项目和会话后再重建，tmux/运行进程不会跨容器重建继续运行。

容器内可以显式运行：
- agent-tools-update claude
- agent-tools-update codex
- agent-tools-update bun
- agent-tools-update all

这会更新 agent 可写的 /opt/agent-tools，保留旧 binary 供现有进程使用，
只影响此容器可写层，重建容器后回到镜像版本。不会自动清理正在使用的旧 binary。
更新后退出并重新启动相应 CLI 或 foreground remote 会话，新进程才会使用新版本。
已经运行的进程不会自动切换版本。
本镜像不管理可选 Codex daemon 的安装、更新或生命周期。

本镜像统一使用 agent-tools-update 管理 native 版本。上游 claude update / codex update
可能在各自默认用户路径安装另一份，不保证改变本镜像 wrapper 指向的版本；不要混用更新方式。

bun add -g 和 bun update -g 操作用户的 Bun 全局包，不能更新本镜像的 native Claude/Codex。
native wrapper 在默认 PATH 中优先，因此 home 内旧同名命令不会默认遮住镜像版本。
bun upgrade 只更新 Bun 自身，且不会更新其他 CLI；统一使用 agent-tools-update 记录结果。
Bun 并非完整 Node 兼容层，部分包、MCP server 或项目仍明确需要 Node；
先确认需求，再在 fork 的构建脚本中有意添加。
默认 no-Node 检查位于 custom hook 之前；有意加入 Node 的 fork
运行 EXPECT_NO_NODE=0 bash tests/check.sh，其他检查仍保持开启。

Claude launcher 设置 DISABLE_AUTOUPDATER=1；
Codex launcher 使用 --no-daemon，并关闭启动时更新检查。
容器启动不会执行工具下载、升级或 daemon 配置修改。
这些是默认行为，不是阻止容器内用户主动修改配置或调用其他模式的安全边界。

/usr/local/share/agent-image/build-manifest.json 保存构建时三种工具的版本、源和 SHA-256；
debian-packages.tsv 保存 Debian 包版本；custom-hook.sha256 记录 hook 内容。
/opt/agent-tools/*/installed.json 反映当前手动安装状态。
Claude 安装后校验官方签名 manifest 与 native binary；
官方安装脚本在这一步校验之前已经运行，不能称为“所有代码均在执行前验证”。
Codex/Bun 在解包前校验 GitHub 发布资产提供的 SHA-256。
SHA-256 与源元数据来自同一发布方，不等同于独立供应链审计。
记录版本不使“每次最新”的构建可复现；需要严格复现时另行固定基础镜像 digest 与全部版本。

## 会话与官方远程接入

SSH 后运行 tmux new -A -s work，可在 SSH 断开后重新接入。
容器停止/重建会结束 tmux 和 CLI 进程；持久化历史不等同于进程仍在运行。

Claude Remote Control：
- 首先完成受支持的 Claude 订阅账户登录；API key/自定义 API 地址不等同于可用的 Remote Control
- 在项目目录的 tmux 会话中执行 claude remote-control
- 依赖出站 HTTPS 和持续运行的本地进程，不需要公开额外入站 HTTP 端口
- 以所安装版本的 --help 和官方账户可用性为准

Codex：
- SSH 中直接运行 codex 是基础路径；launcher 强制使用 --no-daemon
- 在 tmux 中运行 codex remote-control，当前官方实现会继承 launcher 的前台模式
- 远程账户可用性、配对流程、网络行为和所需权限必须按实际安装版本验收
- 默认模式不启动或复用 shared daemon，也不自动配对远程客户端
- 需要 daemon 或 agents overview 时，作为独立高级配置处理；它不属于当前默认验收范围
- 高级模式需另行确认 updater 设置、持久化 package 的版本选择与升级生命周期；
  不能仅凭 codex --version 推断 daemon 版本，也不能假定换镜像会更新持久化 daemon 包

## Fork 扩展

编辑 custom/install.sh 后重新构建。它是 build-time root hook，以 bash -euo pipefail 执行，
任何失败都会使构建失败。Lean/elan 或其他特定项目工具在这里安装，默认不额外携带编译工具链。
将软件安装到 /opt 或 /usr/local，不要安装到将被卷覆盖的 home；明确设置所有权和 PATH。
对下载内容检查官方 hash/签名，并记录版本。不要把凭据写进 hook 或镜像层。
基础 hook 为空；不做运行时拉取、自动安装或静默错误回退。

## 可选网络

默认 Compose 使用普通 Docker 网络，不承诺代理或出站限制。
透明代理通过独立 mihomo/sing-box 服务提供，agent 自身没有 NET_ADMIN 或 privileged。
参见 [网络边界与验收](docs/network.md) 和 compose.proxy.example.yaml。
可复用同一宿主机已有 SOCKS 服务，但须先确定可达地址、认证、DNS/UDP 支持及真实出口。
ALL_PROXY 只影响遵循它的程序，不覆盖所有流量，也不使代理不可见。

## 验证

bash tests/check.sh 提供基础语法、Compose 和已构建镜像 smoke 检查。
它会运行一个临时容器并初始化/访问配置卷，不能把它当纯只读检查。
[验收清单](docs/validation.md) 列出了必须人工验证的 SSH、权限、升级和网络场景。
当前提案未运行这些检查，不能据此宣布生产可用。

## 官方资料

- [Claude 安装、更新和签名](https://code.claude.com/docs/en/setup)
- [Claude Remote Control](https://code.claude.com/docs/en/remote-control)
- [Codex package 布局](https://github.com/openai/codex/blob/main/scripts/codex_package/README.md)
- [Codex daemon 生命周期](https://github.com/openai/codex/blob/main/codex-rs/app-server-daemon/README.md)
- [Bun 安装](https://bun.com/docs/installation)
- [MIT License](LICENSE)
