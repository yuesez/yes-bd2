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

#    落后了就合进来，然后跑一次测试确认没被官方改坏
.\scripts\check_upstream.ps1 -Merge
.\scripts\run_checks.ps1 -Mode Final

# 2. 改东西
#    ...

# 3. 改完自查（只跑受影响的，比全量快很多）
.\scripts\run_checks.ps1 -Mode Focused -Tests tests.<你改的模块>

# 4. 提交并推回自己的 fork
git add -A
git commit -m "说清楚改了什么"
git push
```

`check_upstream.ps1` 也可以顺手推：`.\scripts\check_upstream.ps1 -Merge -Push`。

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

## 注意

- `run.bat` 里的游戏路径是按这台电脑填的（`D:\Neowiz\Browndust2\Browndust2_10000002`）。
- **不要** `git push --tags`：官方 `build.yml` 是 tag 触发的，推 tag 会让你 fork 的
  Actions 去跑发布流程。
- 想贡献回官方就在 GitHub 开 PR：
  `https://github.com/nobell001/YES-BD2/compare/main...yuesez:my-changes`
