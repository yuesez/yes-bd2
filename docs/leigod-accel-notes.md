# 雷神加速器自动化：调研结论与方案

（2026-10-16 调研，覆盖 GUI/CLI/配置文件/官方 API/客户端 IPC 五条路线）

## 一、这台机器的会话结构（最关键的前提）

```
会话 1（你的桌面）                会话 2（桌面分身 = 游戏所在）
├ CloneDesktop.exe  (桌面分身)     ├ pythonw.exe        ← 工具在这里跑
└ pythonw.exe       (启动器)       ├ BrownDust II.exe   ← 游戏
                                  ├ leigod.exe         ← 加速器 GUI
                                  ├ leishenSdk.exe     ← 加速服务（网络加速本体）
                                  └ networktunnel_proxy.exe × 4
```

**HWND / UI Automation 是会话隔离的**：从会话 1 看不到、点不到会话 2 的窗口
（实测：从会话 1 列举 `leigod.exe` 的窗口 → **0 个**）。
**回环 TCP / 命名管道不受会话隔离**，可以跨会话。

实测限制：
- 从会话 1 `Stop-Process` **杀不掉**会话 2 的 `leigod.exe`（5 个进程仍在）
- 从会话 1 启动带 `--remote-debugging-port=9222` 的第二个实例 **被单例锁弹掉**
  （进程数不变、9222 没开）

**结论：加速器 GUI 必须由「会话 2 里的工具自己」启动**——这是唯一可行入口。
工具本来就在会话 2，所以这是顺理成章的。

## 二、五条路线的可行性

| 路线 | 开始加速 | 暂停时长 | 判断 |
|---|---|---|---|
| **官方 REST API** | ❌ 无公开接口 | ✅ 有 | token 失效则需账号密码 |
| **客户端 IPC（CDP 走回环）** | ✅ | ✅ | **推荐**；需带调试端口启动 |
| **SDK socket `127.0.0.1:10908`** | ✅ method 100006 | ✅ 100007 | 明文 JSON 但握手凭据要从日志抓，脆 |
| CLI 参数 | ❌ | ❌ | 只有 `--clientpid=`，无加速开关 |
| 配置文件切换 | ❌ | ❌ | 状态在内存 + 加密 `store.cfg` |

### 官方 API（实测）

```text
https://webapi.leigod.com/api/user/info    ← 通
  → {"code":400006,"msg":"账号未登录"}       ← 本地 2023 年的 token 已失效

暂停:  POST /api/user/pause     {"account_token": ..., "lang": "zh_CN"}
恢复:  POST /api/user/recover   {"account_token": ..., "lang": "zh_CN"}
登录:  POST /api/auth/login     {username, password: md5(明文), ...} → account_token
详情:  POST /api/user/info      → pause_status_id（1 = 已暂停）
```
参考实现：<https://github.com/DemoJ/leigod>、npm `leigod-api`

### 客户端 IPC（从加速器自己的日志逐行验证）

日志：`F:\LeiGod_Acc\resources\llogs\main-YYYY-MM-DD.log`

```text
# 开始加速
ipc handle get-game-tools  [{"game_id":"3478"}]
ipc handle stop-acc        [{"reason":"other"}]
ipc handle start-acc       [{"game_id":3478,"game_name":"棕色尘埃2","area_id":14375,
                             "subarea_id":0,"line_id":-1,"manual":0,"line_type":0,
                             "district":5,"game_type":"0","disableOther":false,
                             "isFreeTime":false,"os_type":0,"dyn_routine":1,
                             "banipv6":1,"lock_engin_rule":0,"assign_id":2219,
                             "save_selection":0}]
→ notify accelerating-status-change {"id":"3478","status":"before-start"} → "running"

# 暂停时长（用户点「暂停时长」按钮的完整流程）
ipc handle pause-user-time [{}]
ipc handle get-stop-acc-data []
ipc handle stop-acc        [{"reason":"timePause"}]
→ notify accelerating-status-change status:"normal"

# 恢复时长
ipc handle recover-user-time [{}]
```

渲染进程暴露的桥接：`window.leigodSimplify.invoke(channel, ...)` / `.notify`
→ 可用 **CDP `Runtime.evaluate`** 调用（回环 WebSocket，跨会话可行）。

### SDK socket（明文 JSON，`0.0.0.0:10908`）

```json
// 握手
{"method":100034,"param":{"cmd":"init","data":{"business_id":"pcop_...","channel_id":"...","acess_token":"..."}},"id":1}
// 开始加速
{"method":100006,"param":{"game_id":3478,"game_name":"棕色尘埃2","area_id":14375,"line_id":-1,...},"id":1}
→ {"code":200,"data":{"acc_result":0,"describe":"ok"}}
// 停止
{"method":100007,"param":{"game_id":3478,"_reason":"timePause","reason":{"code":555,"message":"timePause"}},"id":1}
```
回环且明文，但握手凭据（`business_id`/`channel_id`/`acess_token`）不在明文文件里，
只能每次从 `socket-*.log` 抓上次的——所以列为备选。

## 三、关键标识

| 项 | 值 | 来源 |
|---|---|---|
| 棕色尘埃2 game_id | **3478** | `lcache\gameTools\3478`、`game_path_updated.json`（`reg_name":"棕色塵埃2"`） |
| 子游戏 id | 7874（steam app 3938980） | 同上 |
| 客户端 GUI | `F:\LeiGod_Acc\leigod.exe` | Electron 11.0.23 |
| 启动器 | `F:\LeiGod_Acc\leigod_launcher.exe` | 快捷方式指向它；**不透传参数** |
| 加速服务 | `F:\LeiGod_Acc\resources\leishenSdk\leishenSdk.exe` | 监听 0.0.0.0:10908 |
| 加速状态缓存 | `resources\leishenSdk\datacenter\acc_trait.json` | 只读参考，含 game_id/线路/延迟 |

## 四、选定方案

**由工具（会话 2 内）负责加速器的生命周期：**

```
工具启动
 ├─ ① 若 leigod.exe 没在跑 → 直接启动
 │      F:\LeiGod_Acc\leigod.exe --remote-debugging-port=9222
 │      （launcher 不透传参数，必须直接起 exe；二进制里确认有该开关）
 ├─ ② 等 http://127.0.0.1:9222/json 有响应（回环，跨会话可连）
 ├─ ③ CDP Runtime.evaluate 调
 │      window.leigodSimplify.invoke('start-acc', {game_id:3478, ...})
 │      轮询 get-acc-info 直到 status == "running"
 ├─ ④ 开游戏、跑任务（原流程不变）
 └─ ⑤ 收尾（finally）：
        invoke('pause-user-time', {})   → 暂停计时
        invoke('stop-acc', {reason:'timePause'})  → 停止加速
```

## 五、尚未验证的一步（必须知道）

**CDP 是否真能开端口，我无法从会话 1 验证**——因为单例锁要求先退出会话 2 里的
现有实例，而我没权限动它。

验证方法（二选一）：
1. 在桌面分身的工具里加好这个功能后，第一次运行时会自己重启客户端并打印结果；
2. 手动验证：在分身桌面里退出雷神，然后运行
   `F:\LeiGod_Acc\leigod.exe --remote-debugging-port=9222`，
   再用浏览器打开 `http://127.0.0.1:9222/json` 看有没有 JSON。

若该开关被应用主动屏蔽（`app.commandLine` 里删掉），备选是 SDK socket `10908`
或官方 API + 账号密码。
