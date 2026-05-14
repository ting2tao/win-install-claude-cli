@echo off
cd /d %~dp0
echo Starting install...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-claude.ps1"
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo ERROR: exit code %errorlevel%
    echo ========================================
)
echo.
pause
