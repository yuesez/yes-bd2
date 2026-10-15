#Requires -Version 5.1
<#
检查自己的改动是不是还在（Leo 2026-10-15）。

有两件事会让改动消失，这个脚本负责查出来：
  1. 合并官方更新后，自己的改动被覆盖掉了；
  2. 安装目录被启动器更新覆盖，里面的改动没了。

「自己的改动」不用手写清单：跟 upstream/main 比一下就知道改了哪些文件。

    .\scripts\check_custom_changes.ps1              # 查源码版 + 安装版
    .\scripts\check_custom_changes.ps1 -SourceOnly  # 只查源码版
#>
[CmdletBinding()]
param(
    [switch]$SourceOnly,
    [string]$Install = "D:\Neowiz\yes-bd2\data\apps\yes-bd2\working"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $workspace @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = $output }
}

if (-not (Test-Path (Join-Path $workspace ".git"))) {
    throw "Not a git repository: $workspace"
}
$remotes = (Invoke-Git -Arguments @("remote")).Output
if ($remotes -notcontains "upstream") {
    throw "没有 upstream remote，无法判断哪些是你自己的改动。"
}

# 相对官方改过的文件（含新增）。
$diff = Invoke-Git -Arguments @("diff", "--name-only", "upstream/main...HEAD")
if ($diff.Code -ne 0) {
    throw "diff 失败，先确认 upstream/main 存在（跑一次 scripts\check_upstream.ps1）。"
}
$changed = @($diff.Output | Where-Object { $_ -match '\S' })
if ($changed.Count -eq 0) {
    Write-Host "==> 你跟官方 main 还没有差异（没有自己的改动）。"
    exit 0
}

# 只有 src\ 下的运行时代码会被工具加载；文档、脚本、测试、run.bat 不影响运行，
# 安装版里没有它们不算问题（安装版本来就不放这些东西）。
function Test-RuntimeFile {
    param([string]$Relative)
    $posix = $Relative -replace '\\', '/'
    if ($posix -notlike 'src/*') { return $false }
    if ($posix -notlike '*.py') { return $false }
    return $true
}

$runtime = @($changed | Where-Object { Test-RuntimeFile $_ })
$other = @($changed | Where-Object { -not (Test-RuntimeFile $_) })

Write-Host "==> 你自己改动了 $($changed.Count) 个文件（相对 upstream/main）"
Write-Host "  运行时代码 $($runtime.Count) 个（安装版必须一致）"
if ($other.Count -gt 0) {
    Write-Host "  其他 $($other.Count) 个（文档/脚本/测试，安装版不需要）: $($other -join ', ')"
}
Write-Host ""

$failed = @()

# ---- 1) 源码版：文件在不在 ----
Write-Host "==> 源码版 $workspace"
foreach ($rel in $changed) {
    $path = Join-Path $workspace ($rel -replace '/', '\')
    if (Test-Path -LiteralPath $path) {
        Write-Host "  OK    $rel" -ForegroundColor Green
    } else {
        Write-Host "  缺失  $rel" -ForegroundColor Red
        $failed += "源码版缺文件: $rel"
    }
}

# ---- 2) 安装版：运行时代码的内容对不对 ----
if (-not $SourceOnly) {
    Write-Host ""
    if (-not (Test-Path -LiteralPath $Install)) {
        Write-Host "==> 安装目录不存在，跳过: $Install" -ForegroundColor Yellow
    } elseif ($runtime.Count -eq 0) {
        Write-Host "==> 你没有改到运行时代码，安装版不用同步。"
    } else {
        Write-Host "==> 安装版 $Install"
        foreach ($rel in $runtime) {
            $from = Join-Path $workspace ($rel -replace '/', '\')
            $to = Join-Path $Install ($rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $from)) { continue }
            if (-not (Test-Path -LiteralPath $to)) {
                Write-Host "  没同步  $rel" -ForegroundColor Yellow
                $failed += "安装版缺文件: $rel（启动器更新可能覆盖了）"
                continue
            }
            $a = (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash
            if ($a -eq $b) {
                Write-Host "  一致    $rel" -ForegroundColor Green
            } else {
                Write-Host "  不一样  $rel" -ForegroundColor Yellow
                $failed += "安装版内容不同: $rel"
            }
        }
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "==> 你的改动都在。" -ForegroundColor Green
    exit 0
}

Write-Host "==> 有问题：" -ForegroundColor Red
$failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
Write-Host ""
Write-Host "  安装版被启动器覆盖时，从源码版同步回来即可：" -ForegroundColor Yellow
Write-Host "    （先备份，再逐个 Copy-Item；安装版不是 git 仓库，不能用 git 恢复）"
Write-Host "  源码版缺文件说明合并时误删了，用 git 找回：" -ForegroundColor Yellow
Write-Host "    git checkout upstream/main -- <文件>   # 拿官方版本"
Write-Host "    git checkout HEAD@{1} -- <文件>        # 拿合并前的版本"
exit 1
