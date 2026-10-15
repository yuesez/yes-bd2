#Requires -Version 5.1
<#
合并官方更新，并确认没有把东西改坏（Leo 2026-10-15）。

「确认无回归」不能靠 run_checks.ps1 -Mode Final：官方 main 自己就有 164 个 lint
错误（123 个 E501 + 28 个 import 排序），那道 ruff 关卡永远失败，说明不了任何事。
所以这里改成**前后对比**：

    合并前跑一遍全量测试，记下失败的测试 -> 合并 -> 再跑一遍 -> 比一比。
    只要没有「新的」失败，这次合并就是干净的。

本机本来就有一个失败（test_launcher_seen_through_the_english_link，需要 Windows
开发者模式才能建符号链接），它前后的名字一样，不会被当成新回归。

    .\scripts\merge_upstream_safely.ps1              # 落后就合，并验证
    .\scripts\merge_upstream_safely.ps1 -SkipTests   # 不跑测试（快，但没验证）
    .\scripts\merge_upstream_safely.ps1 -Push        # 验证通过后推到自己的 fork
#>
[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$Push,
    [string]$Ref = "upstream/main",
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $env:TEMP "yes-bd2-merge-check"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $workspace @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = $output }
}

function Resolve-VenvPython {
    if ($Python) { return $Python }
    $candidate = Join-Path $workspace ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "找不到 .venv 里的 python，用 -Python 指定。"
}

function Get-FailingTests {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $names = & {
        Get-Content -LiteralPath $LogPath |
            Select-String -Pattern '^(?:FAIL|ERROR): (\S+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value }
    }
    return @($names | Sort-Object -Unique)
}

function Get-TestSummary {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    $ran = (Get-Content -LiteralPath $LogPath |
        Select-String -Pattern '^Ran (\d+) tests' |
        Select-Object -Last 1)
    $verdict = (Get-Content -LiteralPath $LogPath |
        Select-String -Pattern '^(OK|FAILED)' |
        Select-Object -Last 1)
    return @{
        Ran = if ($ran) { $ran.Matches[0].Groups[1].Value } else { "?" }
        Verdict = if ($verdict) { $verdict.Line.Trim() } else { "?" }
    }
}

function Invoke-Suite {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    $python = Resolve-VenvPython
    Write-Host "==> 跑全量测试（$Label）..." -ForegroundColor Cyan
    Push-Location $workspace
    try {
        & $python -m unittest discover -s tests -v *> $LogPath
    } finally {
        Pop-Location
    }
    $summary = Get-TestSummary -LogPath $LogPath
    $failing = Get-FailingTests -LogPath $LogPath
    Write-Host "  跑了 $($summary.Ran) 个测试；$($summary.Verdict)"
    Write-Host "  失败的测试: $(if ($failing.Count) { $failing.Count } else { 0 }) 个"
    return @{ Failing = $failing; Summary = $summary }
}

$branch = (Invoke-Git -Arguments @("rev-parse", "--abbrev-ref", "HEAD")).Output |
    Select-Object -First 1
$branch = $branch.Trim()
Write-Host "==> 工作分支: $branch"

if ($branch -eq "main") {
    throw "你在 main 上。合并请在自己的分支做（例如 my-changes）。"
}

$dirty = (Invoke-Git -Arguments @("status", "--porcelain")).Output
if ($dirty) {
    Write-Host "==> 工作区有未提交的改动:" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "  $_" }
    throw "先 commit 再合并（合并要能干净回退）。"
}

# 只有合并真正的 upstream/main 才需要先确认官方资料是新的。
# 用 -Ref 指向别的 ref（本地分支、临时 ref）时不必联网，也不该被网络挡住。
if ($Ref -eq "upstream/main") {
    $fetch = Invoke-Git -Arguments @("fetch", "upstream", "--tags")
    if ($fetch.Code -ne 0) {
        Write-Host "==> 取不到官方最新（网络/代理？），不合并。" -ForegroundColor Red
        $fetch.Output | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" }
        Write-Host "  网络恢复后再跑；只是想合并本地 ref 的话用 -Ref 指定。" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "==> 合并的是 $Ref（不是 upstream/main），跳过联网检查。" -ForegroundColor Yellow
}

$behind = [int]((Invoke-Git -Arguments @("rev-list", "--count", "$branch..$Ref")).Output |
    Select-Object -First 1)
if ($behind -eq 0) {
    Write-Host "==> 官方没有新提交，不用合并。" -ForegroundColor Green
    exit 0
}

Write-Host "==> 官方有 $behind 个新提交:" -ForegroundColor Yellow
(Invoke-Git -Arguments @("log", "--oneline", "--no-decorate", "$branch..$Ref")).Output |
    Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

$beforeLog = Join-Path $reportDir "before-$branch.txt"
$afterLog = Join-Path $reportDir "after-$branch.txt"

$before = $null
if (-not $SkipTests) {
    $before = Invoke-Suite -Label "合并前" -LogPath $beforeLog
} else {
    Write-Host "==> -SkipTests：跳过测试，直接合并。" -ForegroundColor Yellow
}

$before_sha = (Invoke-Git -Arguments @("rev-parse", "HEAD")).Output | Select-Object -First 1
Write-Host ""
Write-Host "==> 合并 $Ref 到 $branch ..."
$merge = Invoke-Git -Arguments @("merge", $Ref, "--no-edit")
$merge.Output | ForEach-Object { Write-Host "  $_" }
if ($merge.Code -ne 0) {
    Write-Host ""
    Write-Host "==> 有冲突，需要人工决定：" -ForegroundColor Red
    Write-Host "  看冲突文件:    git status"
    Write-Host "  用官方版本:    git checkout --theirs <文件>; git add <文件>"
    Write-Host "  留你的版本:    git checkout --ours   <文件>; git add <文件>"
    Write-Host "  改完提交:      git commit"
    Write-Host "  整个放弃:      git merge --abort        （回到 $before_sha）"
    exit 1
}
Write-Host "  合并完成。"

$newFails = @()
if (-not $SkipTests -and $null -ne $before) {
    $after = Invoke-Suite -Label "合并后" -LogPath $afterLog
    $newFails = @($after.Failing | Where-Object { $before.Failing -notcontains $_ })
    Write-Host ""
    if ($newFails.Count -eq 0) {
        Write-Host "==> 没有新的失败，这次合并是干净的。" -ForegroundColor Green
        Write-Host "  （合并前就有 $($before.Failing.Count) 个失败，合并后 $($after.Failing.Count) 个，名单相同）"
    } else {
        Write-Host "==> 合并后多了 $($newFails.Count) 个失败的测试：" -ForegroundColor Red
        $newFails | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "  可能是官方这次改动带来的，也可能是跟你的改动打架。" -ForegroundColor Yellow
        Write-Host "  想回退这次合并：git reset --hard $before_sha" -ForegroundColor Yellow
        Write-Host "  报告留在: $beforeLog / $afterLog" -ForegroundColor Yellow
        exit 1
    }
}

if ($Push) {
    Write-Host "==> 推送到 origin ..."
    $push = Invoke-Git -Arguments @("push")
    $push.Output | ForEach-Object { Write-Host "  $_" }
    if ($push.Code -ne 0) { throw "推送失败。" }
    Write-Host "==> 已推送。" -ForegroundColor Green
}

Write-Host ""
Write-Host "==> 记得确认自己的改动还在："
Write-Host "  .\scripts\check_custom_changes.ps1"

