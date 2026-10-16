#Requires -Version 5.1
<#
改动前先看看官方仓库有没有更新（Leo 2026-10-15）。

每次要改功能前跑一次，缺省就是「看」：fetch 官方 main，跟自己的分支比一比。
落后就把它合进来，这样你的改动一定是在官方最新版上做的，以后合并也不会打架。

    .\scripts\check_upstream.ps1                 # 只看，落后就提示
    .\scripts\check_upstream.ps1 -Merge          # 落后就自动合并
    .\scripts\check_upstream.ps1 -Merge -Push    # 合并完顺手推到自己的 fork

fetch 不成功时脚本会挡住（exit 1）：那时候说「已经是最新版」是骗自己，
本地这份官方资料可能已经旧了。确实要硬着头皮继续才加 -AllowStale。

国内这台机器直连 GitHub 是不通的（实测直连 21s 超时），必须走 Clash 代理；
而 Clash 节点偶尔会抽风（SSL 握手失败）。所以 fetch 默认重试 3 次。
#>
[CmdletBinding()]
param(
    [switch]$Merge,
    [switch]$Push,
    [switch]$AllowStale,
    [int]$FetchTries = 3,
    [string]$Python = ''
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $workspace @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = $output }
}

function Get-ProxyState {
    # Clash 之类代理的状态，fetch 失败时报出来，省得只看到一句 SSL 失败。
    $proxy = (& git -C $workspace config --get http.proxy)
    $port = $null
    if ($proxy -match ':(\d+)\s*$') { $port = [int]$Matches[1] }
    $listening = $false
    if ($port) {
        $listening = [bool](Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    }
    return @{ Proxy = $proxy; Port = $port; Listening = $listening }
}

function Get-CurrentBranch {
    $result = Invoke-Git -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
    if ($result.Code -ne 0) {
        throw "Not a git repository: $workspace"
    }
    return ($result.Output | Select-Object -First 1).Trim()
}

function Test-UpstreamRemote {
    $result = Invoke-Git -Arguments @("remote")
    return ($result.Output -contains "upstream")
}

$branch = Get-CurrentBranch
Write-Host "==> 工作分支: $branch"
if ($branch -eq "main") {
    Write-Host "  提醒: 你在 main 上。改动请开在自己的分支（例如 my-changes），" -ForegroundColor Yellow
    Write-Host "  main 留作对照官方的镜子。" -ForegroundColor Yellow
}

if (-not (Test-UpstreamRemote)) {
    Write-Host "==> 没有 upstream remote。先加一个：" -ForegroundColor Yellow
    Write-Host "  git remote add upstream https://github.com/nobell001/YES-BD2.git"
    exit 1
}

# 工作区脏就先说清楚：合并要求干净，否则容易把没提交的改动搅进去。
$dirty = (Invoke-Git -Arguments @("status", "--porcelain")).Output
if ($dirty) {
    Write-Host "==> 工作区有未提交的改动:" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "  $_" }
    if ($Merge) {
        throw "先 commit 或 stash 再合并（避免把半成品搅进合并里）。"
    }
    Write-Host "  合并前记得先处理掉。" -ForegroundColor Yellow
}

Write-Host "==> 取官方最新（fetch upstream，最多试 $FetchTries 次）..."
$fetch = $null
$fetchOk = $false
for ($try = 1; $try -le [Math]::Max(1, $FetchTries); $try++) {
    $fetch = Invoke-Git -Arguments @("fetch", "upstream", "--tags")
    if ($fetch.Code -eq 0) {
        $fetchOk = $true
        if ($try -gt 1) { Write-Host "  第 $try 次成功。" -ForegroundColor Green }
        $fetch.Output | Where-Object { $_ -match '\S' } | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
        break
    }
    if ($try -lt [Math]::Max(1, $FetchTries)) {
        # Clash 节点偶发抽风：等几秒再试，比直接放弃有用。
        Write-Host "  第 $try 次失败，$($try * 4) 秒后重试..." -ForegroundColor Yellow
        Start-Sleep -Seconds ($try * 4)
    }
}
if (-not $fetchOk) {
    Write-Host "  连不上官方仓库，重试 $FetchTries 次都失败。" -ForegroundColor Red
    $fetch.Output | Select-Object -Last 2 | ForEach-Object { Write-Host "  $_" }
    $state = Get-ProxyState
    if ($state.Port) {
        if ($state.Listening) {
            Write-Host "  代理 $($state.Proxy) 端口在听，但连不通——多半是 Clash 节点挂了，" -ForegroundColor Yellow
            Write-Host "  去 Clash Verge 换个节点，或确认它是「规则/全局」模式而不是直连。" -ForegroundColor Yellow
        } else {
            Write-Host "  代理 $($state.Proxy) 端口没在听——Clash 没开或改过端口。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  git 没配代理；国内直连 GitHub 是不通的（实测 21s 超时）。" -ForegroundColor Yellow
        Write-Host "  试试：git config --global http.proxy http://127.0.0.1:7897" -ForegroundColor Yellow
    }
}

# 本次结果的「新鲜度」：从 FETCH_HEAD 的写入时间看官方资料有多旧。
$freshness = ""
$headPath = Join-Path $workspace ".git\FETCH_HEAD"
if (Test-Path -LiteralPath $headPath) {
    $age = (Get-Date) - (Get-Item -LiteralPath $headPath).LastWriteTime
    if ($age.TotalMinutes -lt 1) {
        $freshness = "刚刚"
    } elseif ($age.TotalHours -lt 1) {
        $freshness = "$([int]$age.TotalMinutes) 分钟前"
    } else {
        $freshness = "$([math]::Round($age.TotalHours, 1)) 小时前"
    }
}
if (-not $fetchOk) {
    # fetch 失败时 upstream/main 还停在旧位置，说「已是最新」就是骗自己：
    # 那会让人以为可以动手改，其实没看过官方最新。这里必须挡住。
    Write-Host ""
    Write-Host "==> 没有取到官方最新，无法判断你是不是在最新版上。" -ForegroundColor Red
    if ($freshness) {
        Write-Host "  本地这份官方资料是 $freshness 的（.git\FETCH_HEAD）。" -ForegroundColor Yellow
    }
    Write-Host "  请先让网络/代理恢复正常再跑一次。也可以用 -AllowStale 硬着头皮继续，" -ForegroundColor Yellow
    Write-Host "  但那样不保证改动是基于官方最新版。" -ForegroundColor Yellow
    if (-not $AllowStale) {
        exit 1
    }
    Write-Host "  （已指定 -AllowStale，下面用本地这份旧资料继续。）" -ForegroundColor Yellow
}

$behind = [int]((Invoke-Git -Arguments @("rev-list", "--count", "$branch..upstream/main")).Output | Select-Object -First 1)
$ahead = [int]((Invoke-Git -Arguments @("rev-list", "--count", "upstream/main..$branch")).Output | Select-Object -First 1)

Write-Host ""
if ($freshness -and $fetchOk) {
    Write-Host "==> 与 upstream/main 的差距（官方资料: $freshness）"
} else {
    Write-Host "==> 与 upstream/main 的差距（本地旧资料，未取到官方最新）"
}
Write-Host "  你领先: $ahead 个提交（你自己的改动）"
Write-Host "  你落后: $behind 个提交（官方的新内容）"

if ($behind -eq 0) {
    Write-Host ""
    if ($fetchOk) {
        Write-Host "==> 已经是最新版，可以直接动手改。" -ForegroundColor Green
    } else {
        Write-Host "==> 没取到官方最新，只能说「本地这份资料里没有更新的」。" -ForegroundColor Yellow
    }
    exit 0
}

Write-Host ""
Write-Host "==> 官方有 $behind 个新提交:" -ForegroundColor Yellow
$log = Invoke-Git -Arguments @("log", "--oneline", "--no-decorate", "$branch..upstream/main")
$log.Output | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
if ($log.Output.Count -gt 30) {
    Write-Host "  ...（还有 $($log.Output.Count - 30) 条）"
}

if (-not $Merge) {
    Write-Host ""
    Write-Host "==> 要合进来再改，就加 -Merge：" -ForegroundColor Yellow
    Write-Host "  .\scripts\check_upstream.ps1 -Merge"
    exit 0
}

Write-Host ""
Write-Host "==> 合并 upstream/main 到 $branch ..."
$merge = Invoke-Git -Arguments @("merge", "upstream/main", "--no-edit")
$merge.Output | ForEach-Object { Write-Host "  $_" }
if ($merge.Code -ne 0) {
    Write-Host ""
    Write-Host "==> 有冲突，需要人工决定。" -ForegroundColor Red
    Write-Host "  看哪些文件冲突:  git status"
    Write-Host "  接受官方版本:      git checkout --theirs <文件> && git add <文件>"
    Write-Host "  保留你的版本:      git checkout --ours   <文件> && git add <文件>"
    Write-Host "  改完:              git commit"
    Write-Host "  放弃这次合并:      git merge --abort"
    throw "合并未完成。"
}

Write-Host "==> 合并完成。" -ForegroundColor Green
$after = [int]((Invoke-Git -Arguments @("rev-list", "--count", "upstream/main..$branch")).Output | Select-Object -First 1)
Write-Host "  现在你领先 upstream/main $after 个提交（都是你自己的）。"

if ($Push) {
    Write-Host "==> 推送到 origin ..."
    $push = Invoke-Git -Arguments @("push")
    $push.Output | ForEach-Object { Write-Host "  $_" }
    if ($push.Code -ne 0) {
        throw "推送失败。"
    }
    Write-Host "==> 已推送。" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> 下一步：确认能跑再动手改" -ForegroundColor Cyan
Write-Host "  .\scripts\run_checks.ps1 -Mode Focused -Tests tests.<你关心的测试>"
