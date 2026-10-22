#Requires -Version 5.1
<#
把源码版（D:\YES-BD2）里自己的改动同步到安装版（启动器跑的 working 目录）。

Leo 2026-10-22：每次启动器更新都会把安装目录整个覆盖，自己的改动和这些改动新增的
配置键就都没了。手工拷贝容易漏（文件清单会变），所以由 git 现算：

    相对 upstream/main 改过的 src\*.py  -> 从源码版拷到安装版

只拷运行时代码；文档、测试、脚本本来就不该进安装目录。
配置键不在这里补（那是工具运行时自己写的），需要的键在跑完脚本后用工具界面设一次。

    .\scripts\sync_to_install.ps1              # 同步并校验
    .\scripts\sync_to_install.ps1 -DryRun      # 只列出会拷哪些文件
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Install = "D:\Neowiz\yes-bd2\data\apps\yes-bd2\working"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $workspace @Arguments 2>&1
    return @{ Code = $LASTEXITCODE; Output = $output }
}

if (-not (Test-Path -LiteralPath $Install)) {
    throw "安装目录不存在: $Install"
}
if (-not (Test-Path -LiteralPath (Join-Path $workspace ".git"))) {
    throw "不是 git 仓库: $workspace"
}

# 自己改过的运行时代码（相对 upstream/main）。
$diff = Invoke-Git -Arguments @("diff", "--name-only", "upstream/main...HEAD")
if ($diff.Code -ne 0) {
    throw "diff 失败；先跑一次 scripts\check_upstream.ps1 确认 upstream/main 存在。"
}
$changed = @(
    $diff.Output |
        Where-Object { $_ -match '\S' } |
        ForEach-Object { ($_ -replace '\\', '/') } |
        Where-Object { $_ -like 'src/*' -and $_ -like '*.py' }
)
if ($changed.Count -eq 0) {
    Write-Host "==> 没有改到运行时代码，安装版不用同步。" -ForegroundColor Yellow
    exit 0
}

# 先确认两边版本接近：安装版是启动器发行的 tag，源码版是仓库里的 pyproject.toml。
# 不一致就说明安装版落后（或超前），只拷文件会因缺依赖而崩（2026-10-22 踩过）。
$pyproject = Join-Path $workspace "pyproject.toml"
$sourceVersion = if (Test-Path -LiteralPath $pyproject) {
    (Select-String -Path $pyproject -Pattern '^version\s*=\s*"([^"]+)"' |
        Select-Object -First 1).Matches.Groups[1].Value
} else { "?" }
$installConfig = Join-Path $Install "src\config.py"
$installVersion = if (Test-Path -LiteralPath $installConfig) {
    (Select-String -Path $installConfig -Pattern 'version = "([^"]+)"' |
        Select-Object -First 1).Matches.Groups[1].Value
} else { "?" }
Write-Host "==> 版本参考：源码 pyproject.toml = $sourceVersion / 安装版 = $installVersion"
Write-Host "  （安装版是发行 tag，源码版是 dev 版本，两者不一定相同；"
Write-Host "    真正判断兼容性靠下面的导入校验。）"

Write-Host ""
Write-Host "==> 将同步 $($changed.Count) 个运行时文件"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path (Split-Path -Parent $Install) "working-custom-backup-$stamp"
$copied = 0
foreach ($rel in $changed) {
    $from = Join-Path $workspace ($rel -replace '/', '\')
    $to = Join-Path $Install ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $from)) {
        Write-Host "  跳过（源码版没有）: $rel" -ForegroundColor Yellow
        continue
    }
    $same = (Test-Path -LiteralPath $to) -and
        ((Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -eq
         (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash)
    if ($same) {
        Write-Host "  已一致: $rel"
        continue
    }
    if ($DryRun) {
        Write-Host "  会拷贝: $rel" -ForegroundColor Cyan
        continue
    }
    if (Test-Path -LiteralPath $to) {
        $backupFile = Join-Path $backup ($rel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path $backupFile) | Out-Null
        Copy-Item -LiteralPath $to -Destination $backupFile -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
    Write-Host "  已拷贝: $rel" -ForegroundColor Green
    $copied++
}

if ($DryRun) {
    Write-Host ""
    Write-Host "==> -DryRun：没有改动任何文件。" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
if ($copied -gt 0) {
    Write-Host "==> 备份在: $backup" -ForegroundColor Cyan
}

# 校验：用安装版自己的 Python 导入一次，确认没有缺依赖。
Push-Location $Install
try {
    $python = Join-Path $Install "..\python\python.exe"
    if (Test-Path -LiteralPath $python) {
        Write-Host "==> 用安装版的 Python 校验导入..."
        $check = & $python -c "import src.tasks.PVPTask, src.ui.shell.pvp_panel; print('OK')" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  导入 OK ✅" -ForegroundColor Green
        } else {
            Write-Host "  导入失败，可能缺依赖：" -ForegroundColor Red
            $check | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
            Write-Host "  用备份还原: $backup" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "  找不到安装版的 python，跳过导入校验。" -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "==> 完成。" -ForegroundColor Green
Write-Host "  如果这是新功能，打开工具后可能需要在任务设定里设一次相关选项。"
Write-Host "  确认自己的改动都在：.\scripts\check_custom_changes.ps1"
