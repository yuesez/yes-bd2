# 用 Clash 替代雷神加速游戏：实测结论

（2026-10-16 实测于本机；回答「Clash 能不能在桌面分身下运行」）

## 结论：能，而且比雷神更适合自动化

**桌面分身（会话 2）里的游戏流量会被 Clash 自动盖住**——因为 TUN 模式走的是
**系统级路由表**，不属于任何会话。不需要在分身里单独装 Clash、也不需要设分身
的系统代理。

证据（Clash `/connections` 实时记录，`network` 列就是接入方式）：

```text
tcp/Tun   android.clients.google.com  -> 🇺🇸美国02-0.1倍 | ... > 🐟漏网之鱼
udp/Tun   134.195.101.179:35941       -> 🇺🇸美国02-0.1倍 | ... > 🐟漏网之鱼
tcp/Inner dns.cloudflare.com          -> 🇯🇵AWS日本03 | ...
```

`Tun` = 透明接管，`udp/Tun` = **UDP 也走代理**（游戏必需）。

## 为什么之前不行：服务没跑

`clash_verge_service` 一直是 **Stopped**，`verge.yaml` 里留着
`Service startup failed or unavailable before sidecar fallback`。
**TUN 开关依赖这个服务**，所以：

| | 状态 |
|---|---|
| 之前 `enable_tun_mode` | `null`（从没开成功过） |
| 修复动作 | 以管理员启动 `clash_verge_service` |
| 之后 `enable_tun_mode` | `true`，且能持久保存 |

启动命令（需要 UAC 确认一次）：

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-Command',`
  'Start-Service -Name ''clash_verge_service'''
```

## 生效后的状态

```text
tun.enable = True      tun.device = 'Meta'     inet4 = 198.18.0.1/30
网卡: Meta (Meta Tunnel) Status=Up ifIndex=63

默认路由（TUN 优先）:
  0.0.0.0/0 -> 198.18.0.2  on Meta      RouteMetric=0
  0.0.0.0/0 -> 192.168.1.1 on 以太网 2   RouteMetric=0

DNS: Meta 服务器 = 198.18.0.2（53 已被劫持）
```

## 可自动化性（Clash 的最大优势）

外部控制 API 可用，**无需 GUI**：

```text
external-controller: 127.0.0.1:9097
secret: 15 字符，存在 clash-verge.yaml 的 secret 字段
Authorization: Bearer <secret>
```

已实测可用：

| 接口 | 用途 |
|---|---|
| `GET /version` | v1.19.11 (mihomo) |
| `GET /configs` | 读 mode / tun / mixed-port（**PATCH tun 无效，受 GUI 管**） |
| `GET /proxies` | 85 个节点/策略组，可读当前选择 |
| `PUT /proxies/<组>` | 切换节点（例：选一个支持 UDP 的日本/新加坡节点） |
| `GET /connections` | 实时连接，可验证流量是否走了代理 |

## 与雷神对比

| | 雷神 | Clash |
|---|---|---|
| 控制方式 | GUI/CDP，调试端口启动受单例锁与权限限制 | **纯 REST API，无 GUI 依赖** |
| 会话限制 | 客户端在会话 2，会话 1 动不了 | **TUN 系统级，跨会话自动生效** |
| 节点选择 | 固定线路 | 85 个节点可脚本切换 |
| 游戏优化 | 专业游戏驱动、专线 | 通用代理，延迟未必更优 |
| 「暂停时长」 | API 可暂停计时 | 无此概念（不吃时长） |

**用途建议**：连不上时用它换地区节点（很合适）；追求低延迟打 PVP，雷神仍可能更好。

## 已知限制

- **TUN 开关只能通过 Clash Verge GUI 切换**：外部 API `PATCH /configs {tun}` 会被
  忽略（实测 enable 仍为 false，内核是 GUI 的子进程而非服务托管）。
- TUN 需要服务在跑；服务停了 TUN 也起不来。所以**开机后服务没自启的话要先启动它**
  （当前 StartType=Manual）。
- 节点是否支持 UDP 决定游戏能否真正加速；`/connections` 里看到 `udp/Tun` 才算数。
- TUN 会把**全部**流量送进内核，规则模式下国内直连（`DIRECT`）不走节点，但 DNS 仍被
  劫持到 198.18.0.2。
