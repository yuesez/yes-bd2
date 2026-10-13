@echo off
rem YES-BD2 源码方式启动（方案 A）
rem 这个脚本属于你自己，不会被上游更新覆盖。
rem 首次使用前请确认下面的游戏路径跟你的安装位置一致。

chcp 65001 >nul
cd /d "%~dp0"

rem ---- 游戏路径（你的安装位置）----
set "OK_BD2_GAME_PATH=D:\Neowiz\Browndust2\BrownDust2_10000002\BrownDust II.exe"
set "OK_BD2_INSTALL_DIR=D:\Neowiz\Browndust2\BrownDust2_10000002"

rem 如果以后找到了 Starter（启动器 exe），把下面这行的 rem 去掉并改成实际路径
rem set "OK_BD2_LAUNCHER_PATH=D:\Neowiz\Browndust2\Browndust2Starter.exe"

if not exist ".venv\Scripts\python.exe" (
    echo.
    echo   找不到 .venv，请先按 README「从源码运行」建立虚拟环境：
    echo   py -3.12 -m venv .venv
    echo   .\.venv\Scripts\pip install -r requirements.txt
    echo.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" main.py
