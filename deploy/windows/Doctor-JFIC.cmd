@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\doctor.ps1"
set "rc=%errorlevel%"
echo.
pause
exit /b %rc%
