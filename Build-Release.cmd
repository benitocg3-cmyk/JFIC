@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\eng\Package-Ubuntu.ps1"
if errorlevel 1 pause & exit /b 1
pause
