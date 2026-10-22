# 这个 fork 怎么改、怎么跟上官方

`yuesez/yes-bd2` 是 `nobell001/YES-BD2` 的 fork。这里的规矩很简单：
**每次动手改之前，先把官方最新的合进来**，改动永远做在官方最新版之上。

## 两个 remote

```text
origin    https://github.com/yuesez/yes-bd2.git      ← 你自己的 fork（推这里）
upstream  https://github.com/nobell001/YES-BD2.git   ← 官方（只读，拉这里）
```

## 分支

| 分支 | 用途 |
|---|---|
| `main` | 对照官方的镜子。**不要在这里改东西**，它要跟 `upstream/main` 保持一致。 |
| `my-changes` | 你自己的改动都放这里。 |

## 固定流程

```powershell
cd D:\YES-BD2

# 1. 动手前：看官方有没有更新（这一步是规矩，别跳过）
.\scripts\check_upstream.ps1

#    落后了就合进来（这个脚本会自己跑前后两遍测试来确认没被改坏）
.\scripts\merge_upstream_safely.ps1

# 2. 改东西
#    ...

# 3. 改完自查（只跑受影响的，比全量快很多）
.\scripts\run_checks.ps1 -Mode Focused -Tests tests.<你改的模块>

# 4. 提交并推回自己的 fork
git add -A
git commit -m "说清楚改了什么"
git push

# 5. 确认自己的改动还在（合并、官方更新、同步之后都值得跑一次）
.\scripts\check_custom_changes.ps1
```

`check_upstream.ps1` 也可以顺手推：`.\scripts\check_upstream.ps1 -Merge -Push`。

## ⚠️ `run_checks.ps1 -Mode Final` 现在会失败，这不是你的问题

实测（2026-10-15）：**官方纯净的 `main` 自己就有 164 个 lint 错误**——123 个
`E501`（行超 100 字符）+ 28 个 `I001`（import 未排序），散在约 40 个文件里。
也就是说官方自己过不了自己 CI 里的 `ruff check .`，那道关卡永远亮红。

所以**不要**用它来判断「我的改动有没有把东西改坏」——它失败不说明任何事。
要用「前后对比」：合并前后各跑一遍全量测试，只要没有**新的**失败就是干净的。
`merge_upstream_safely.ps1` 就是干这个的。

## 三个脚本的分工

| 脚本 | 什么时候跑 | 做什么 |
|---|---|---|
| `scripts\check_upstream.ps1` | **动手改之前**（规矩） | 看官方有没有新提交；`-AllowStale` 见下 |
| `scripts\merge_upstream_safely.ps1` | 真的落后、要合并时（用这个代替 `-Merge`） | 前后各跑一遍全量测试并对比，确认没引入新失败 |
| `scripts\check_custom_changes.ps1` | 合并后、同步安装版后 | 查自己的改动有没有被覆盖掉 |

`check_upstream.ps1` 在**取不到官方最新时会挡住**（exit 1）：网络/代理不通的时候，
说「已经是最新版」是骗自己——本地那份官方资料可能已经旧了。这种情况先修好网络再跑。
确实要硬着头皮继续才加 `-AllowStale`，那时它会明说「这只是本地旧资料里没有更新的」。

`merge_upstream_safely.ps1` 里的 `-Ref` 默认是 `upstream/main`，一般不用管；
`-SkipTests` 跳过测试（快但没验证），`-Push` 验证通过后顺手推。

`check_custom_changes.ps1` 不用维护清单：它用 `git diff upstream/main...HEAD` 自己
算出你改了哪些文件，再逐个比对源码版和安装版。以后你再加新功能，它自动把新文件也
算进去。只有 `src\` 下的 `.py` 会被当成「必须一致」——文档、脚本、测试、`run.bat`
不影响工具运行，安装版里没有它们不算问题。

## 为什么必须先合再改

官方一直在动（光是镜中之战的倍数/场数界面，2026-10-14 就被重写过一次）。
如果在旧代码上写功能，等下次合并时两边都改了同一块，就要手工解冲突；
先在最新版上写，冲突基本不会发生。

## 改动会丢 / 不会丢

- ✅ **不会丢**：你自己 commit 过的东西。合并时 git 逐文件三方合并，只有你和官方
  改了同一处才会冲突。
- ❌ **会丢**：直接改安装目录 `D:\Neowiz\yes-bd2\data\apps\yes-bd2\working\` 里的
  代码。那是启动器的运行副本，官方一更新就整个覆盖。

所以：**改动一律做在 `D:\YES-BD2`，跑也用 `run.bat`。**
安装目录只在需要「用启动器界面跑自己的改动」时才手动同步（见下）。

## 安装版 vs 源码版

两个目录是分开的，各有各的 `configs\`（任务设定不互通）：

| | 源码版（改动用这个） | 安装版 |
|---|---|---|
| 位置 | `D:\YES-BD2` | `D:\Neowiz\yes-bd2\data\apps\yes-bd2\working\` |
| 启动 | 双击 `D:\YES-BD2\run.bat` | 双击桌面 `yes-bd2`（走启动器、会自动更新） |
| 版本 | 官方最新 main | 官方发行版（可能是旧 tag，且会被启动器覆盖） |
| 你的改动 | 在这里 | 需要手动同步，且下次更新会被覆盖 |

要同步到安装版（仅在你想用启动器界面跑自己的改动时）：

```powershell
# 逐个拷贝你改过的文件（先备份！）
# 改动清单：git diff --name-only upstream/main..my-changes
```

### ⚠️ 安装版落后太多时，不能只拷文件

2026-10-22 实测：源码版合到官方最新后，安装版还是 `v0.1.42`（落后 83 个提交）。
把新的 `PVPTask.py` 单独拷过去会直接崩：

```
ImportError: cannot import name 'FIELD_FOLLOWERS_KEY' from 'src.tasks.BaseBD2Task'
```

因为新版 `PVPTask.py` 依赖官方同时改的 `BaseBD2Task`、`wait_limits`、`pvp_dialog` 等
一整套文件。**只同步「我改的那几个文件」只在两边版本接近时可行**；版本差得远时，
要么让启动器把安装版整个更新到最新再同步，要么直接用源码版（`run.bat`）。

### 用脚本同步（官方更新之后再跑）

每次启动器更新都会覆盖安装目录，自己的改动就没了。别手工拷，用：

```powershell
.\scripts\sync_to_install.ps1 -DryRun   # 先看会拷哪些文件
.\scripts\sync_to_install.ps1           # 备份 + 拷贝 + 用安装版 Python 校验导入
```

它会用 `git diff upstream/main...HEAD` 自己算出你改过哪些 `src\*.py`，自动备份被覆盖
的文件到 `working-custom-backup-<时间>`，最后用安装版自己的 Python 跑一次导入校验——
缺依赖会当场报错并提示用哪个备份还原（就是上面那个 ImportError 的教训）。

**配置键不会被脚本补**：工具运行时自己写的 `configs\*.json` 在更新后可能丢掉新功能的键
（2026-10-22：`按星期切换倍率` 等 5 个键就丢了，其余设置都在）。同步后打开工具，
在对应的任务设定里看一眼、重设一下即可。

## 网络：访问 GitHub 需要走代理

这台机器**直连 GitHub 是不通的**，git 已配好代理（`http.proxy`）。
代理偶尔会抽风（表现为 `schannel: failed to receive handshake` 或连接超时），
所以两个脚本的 fetch 都会重试；重试仍失败时会直接告诉你代理端口在不在听。

代理不通的时候把代理软件重启一下、或换个节点，再跑脚本即可，不需要改本仓库配置。

## 注意

- `run.bat` 里的游戏路径是按这台电脑填的（`D:\Neowiz\Browndust2\Browndust2_10000002`）。
- **不要** `git push --tags`：官方 `build.yml` 是 tag 触发的，推 tag 会让你 fork 的
  Actions 去跑发布流程。
- 想贡献回官方就在 GitHub 开 PR：
  `https://github.com/nobell001/YES-BD2/compare/main...yuesez:my-changes`

## 改过的功能：镜中之战「按星期切换倍率」

**要打开开关才生效**（面板上那一行点一下）。2026-10-16 踩过一次：界面上明明看得见
两个时段，跑起来却毫无变化——因为开关还是「关闭」，而当时按钮只写「关闭」两个字，
看不出差在哪一步。现在按钮会直接写出结果，例如：

```text
按星期 关闭 ▾ · 正在用上方 40倍 × MAX场
按星期 开   ▾ · 今天 周五~周日 1倍 × 40场
```

另外要记住：**开关打开后，上面那格「战斗场数」完全被忽略**，改它没用——时段自己的
场数说了算。（当时是 `MAX`，所以打开前每次只打 1 场，打开后变成打满时段场数。）

时段的边界是游戏日：每天 08:00（北京时间）换日，周一 08:00 整才切到周一到周四。
