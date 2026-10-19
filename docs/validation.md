# 实施前后验收

当前状态：只做了连接器读源码和文本审阅，没有构建/运行容器，没有更改宿主机或公开仓库。

## 构建和安装

- 对 scripts/*.sh、custom/install.sh、tests/check.sh 逐个运行 bash -n
- docker compose config；可选 proxy override 另行校验，使用支持 !reset 的 Compose
- 在 amd64、arm64 真实运行环境构建并 smoke test；检查官方版本 API、资产名称、
  manifest schema、GPG 指纹、完整包布局；上游变更应 fail-fast
- 检查 claude/codex/bun --version、版本清单和 hash；sudo 不应存在
- 未扩展的默认构建不应包含 Node/npm；有意安装 Node 的 fork 使用 EXPECT_NO_NODE=0，
  并验证新增工具的版本、hash 和必要性
- 验证 custom hook 失败会使整个构建失败，构建日志与 image history 不含凭据
- 核对镜像大小、额外包必要性和第三方工具再分发条件

## SSH 与权限

- 非 root sshd 能真正完成公钥认证和建立 PTY，不能仅做 nc 探测
- agent 的 uid/gid 与项目 bind mount 写权限匹配；一个可写项目和一个只读测试项目
- 密码、交互式密码、root 登录、SSH agent forwarding 被拒绝；SFTP 能工作
- 首次连接核对 host key 指纹，重建后保持一致；公钥撤销重启后生效
- 对不存在、空、不可读的 authorized_keys，入口给出清晰错误，不回退密码
- cap_drop:ALL、no-new-privileges 下测试 sshd；不以 root/privileged 绕过失败
- 分别验收 Codex/Claude 自己的 sandbox；宿主 user namespaces、seccomp/AppArmor
  可能使其失败。未验收前不能宣传额外 sandbox 隔离保证

## 持久化与更新

- 写入 .codex、.claude、.claude.json 后重建，认证和配置仍存在；验证 .claude.json
  的原子重写，多个项目读写，各自文件不会混进镜像
- fresh home 正常；旧 UID/GID home 清晰报错，不递归修改宿主项目权限
- 换镜像后默认 native CLI 与 build manifest 一致；旧 home 中同名全局命令不遮住它
- Bun 全局包可以由非 root 增加/更新，bun update -g 不影响 native CLI
- 手动 agent-tools-update 后版本和当前安装清单更新；旧进程的 binary 没被截断；
  重建后回到新镜像版本
- 默认 codex 与 remote-control 不启动或连接 daemon；即使 home 中已有 daemon 状态也要验证
- 持续运行和容器重启期间不出现未请求的 CLI 更新下载；确认 Claude 自动更新被禁用
- 修改 key、镜像和持久化目录时不要同时运行多个容器共享同一 home

## 官方远程与生命周期

- Claude 订阅登录和 remote-control 的真实账户可用性、出站 HTTPS、断网恢复
- 验收 Codex foreground remote 的账户可用性、断网恢复和进程生命周期；
  不自动配对/授权外部客户端
- 高级 daemon 模式另行设计和验收，不将其结果混入默认前台模式的保证
- SSH 断线 tmux 继续，重新登录可接回；容器重建后进程终止且历史仍在
- 测试 no-new-privileges 环境中的 remote helpers，不用未验证的权限放大作为默认配置

## 网络

仅在启用单独代理后执行 docs/network.md 的路由、DNS、IPv6、UDP、故障和 SSH 回程验收。
在这些测试前，透明覆盖、最终出口和 fail-closed 均未确认。
