@echo off
cd /d %~dp0
echo 当前目录：%cd%
echo 正在启动安装脚本...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-claude.ps1"
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo 脚本执行出错，错误码：%errorlevel%
    echo ========================================
)
echo.
pause
