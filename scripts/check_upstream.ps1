#Requires -Version 5.1
<#
改动前先看看官方仓库有没有更新（Leo 2026-10-15）。

每次要改功能前跑一次，缺省就是「看」：fetch 官方 main，跟自己的分支比一比。
落后就把它合进来，这样你的改动一定是在官方最新版上做的，以后合并也不会打架。

    .\scripts\check_upstream.ps1                 # 只看，落后就提示
    .\scripts\check_upstream.ps1 -Merge          # 落后就自动合并
    .\scripts\check_upstream.ps1 -Merge -Push    # 合并完顺手推到自己的 fork
#>
[CmdletBinding()]
param(
    [switch]$Merge,
    [switch]$Push,
    [string]$Python = ''
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $workspace @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = $output }
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

Write-Host "==> 取官方最新（fetch upstream）..."
$fetch = Invoke-Git -Arguments @("fetch", "upstream", "--tags")
if ($fetch.Code -ne 0) {
    Write-Host "  连不上官方仓库（网络/代理？）。下面是本地已有的资料：" -ForegroundColor Yellow
    $fetch.Output | ForEach-Object { Write-Host "  $_" }
} else {
    $fetch.Output | Where-Object { $_ -match '\S' } | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
}

$behind = [int]((Invoke-Git -Arguments @("rev-list", "--count", "$branch..upstream/main")).Output | Select-Object -First 1)
$ahead = [int]((Invoke-Git -Arguments @("rev-list", "--count", "upstream/main..$branch")).Output | Select-Object -First 1)

Write-Host ""
Write-Host "==> 与 upstream/main 的差距"
Write-Host "  你领先: $ahead 个提交（你自己的改动）"
Write-Host "  你落后: $behind 个提交（官方的新内容）"

if ($behind -eq 0) {
    Write-Host ""
    Write-Host "==> 已经是最新版，可以直接动手改。" -ForegroundColor Green
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
