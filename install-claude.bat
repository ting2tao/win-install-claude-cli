@echo off
cd /d %~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File install-claude.ps1
pause
