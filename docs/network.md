# 独立代理服务：边界和待验收项

默认 agent 服务使用普通 Docker bridge，可以直接出站；没有全流量代理或 fail-closed 承诺。
不要把 ALL_PROXY 当作强制所有程序走代理的开关，也不要承诺服务端无法识别代理。

## 选择

1. 只需遵循代理变量的工具：按各工具官方支持配置 HTTP(S)/SOCKS 代理，
   并接受不遵循变量的进程可直接出站这一边界。
2. 需要透明转发：单独运行 mihomo/sing-box，按宿主平台设计 TUN/路由和防火墙。
   agent 不获得 NET_ADMIN；代理服务单独持有网络管理权限。
3. 有同机 SOCKS 服务时优先考虑复用，避免再起一套相同出口。
   仍需确认它服务的是目标出口，以及它是否支持所需 DNS、IPv6 和 UDP 行为。

## 可选 Compose 接线

compose.proxy.example.yaml 只是 mihomo 容器的 namespace 接线模板，
没有给出已验证的路由/防火墙配置。启用前需准备私有配置和固定的官方镜像引用：
docker compose -f compose.yaml -f compose.proxy.example.yaml config
docker compose -f compose.yaml -f compose.proxy.example.yaml up -d --no-build

此操作必须由用户在确认宿主和代理配置后运行；提案本身没有修改网络。
模板使用 network_mode: service:proxy。端口映射属于 proxy，不能继续发布在 agent 上；
agent 和 proxy 共享网络命名空间，包括 TUN、loopback 和本地监听端口。
这并不把代理隐藏起来。禁用或限制不必要的管理 API/控制端口。

proxy 默认只有 NET_ADMIN 和 /dev/net/tun，未开启 privileged。
实际镜像/宿主可能有额外兼容性要求，不能仅因失败就给 agent 加权。
depends_on: service_started 只保证进程启动顺序，不能证明 tunnel ready，也不提供阻断回落。
替换 proxy 后应一起重新创建 agent，不能假定旧 namespace 自动切换。

## 同宿主 SOCKS

容器中的 127.0.0.1 是该网络命名空间，不是宿主机，也不是另一个普通容器。
- 同一用户自定义 Docker 网络可使用已验证的 SOCKS 容器 DNS 名与监听端口；
  需要接入已有 network 时另行填写 external network 配置。
- 如果 SOCKS 已发布到宿主且允许 Docker bridge 访问，可用 host.docker.internal
  的 host-gateway 映射；仅监听宿主 127.0.0.1 的服务通常不能这样访问。
- 不要为图省事把带认证的 SOCKS 或管理端口公开到互联网。
- 真实服务器地址、用户、密码、订阅 URL 留在 gitignore 覆盖的私有配置中，不进镜像。

模板的 command 仅针对兼容 mihomo CLI 的镜像；sing-box 的入口参数和配置格式不同，
不能只换 image 名就认为工作。镜像、配置、TUN 与宿主 kernel 需共同验证。

## 路由与泄漏验收

在开放真实 agent 凭据/项目前，至少验证：

- 正常流量：从 agent 观察多个独立服务的出口 IP，与预期出口一致；
  SOCKS 的名字或服务器地理位置不能证明最终出口位置。
- DNS：系统 resolver、Docker embedded DNS、DoH/DoT、DNS hijack 的路径逐项确认；
  明确代理自身如何解析上游地址，防止 bootstrap 循环或直接解析泄漏。
- IPv4/IPv6：检查两类默认路由和真实请求；不支持 IPv6 时需要明确阻止，
  不能只设置某个应用的 ipv6:false 就声称无 IPv6 绕行。
- UDP/QUIC：核实上游 SOCKS 的 UDP 支持；不支持时明确阻断/降级并测试，
  不能默默回落直连。
- SSH：对管理来源和 Docker 子网保持正确回程路由，避免回复被 TUN 捕获；
  使用可信管理连接验证，不在唯一远程入口上盲改规则。
- 故障：停止代理进程、撤销上游连通、重启/重建 proxy 和 Docker 后分别测试；
  DNS、TCP、UDP 和 IPv6 不应在声称 fail-closed 时回落直连。
- 防火墙：若要求 fail-closed，需要由宿主/网关提供独立、经测试的出站约束；
  TUN auto-route、strict-route 和容器依赖关系不单独构成此保证。

当前未检查实际宿主网络、SOCKS 端点、防火墙、真实出口或返回路由。
这部分应另行审批和测试，不能作为镜像基础功能已经通过。

## 官方资料

- [Compose network_mode](https://docs.docker.com/reference/compose-file/services/#network_mode)
- [mihomo TUN](https://wiki.metacubex.one/en/config/inbound/tun/)
- [sing-box TUN](https://sing-box.sagernet.org/configuration/inbound/tun/)
