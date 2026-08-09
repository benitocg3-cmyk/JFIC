@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -Command "$p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 0}else{exit 1}"
if not errorlevel 1 goto elevated

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:elevated
powershell -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1"
set "rc=%errorlevel%"
echo.
if "%rc%"=="0" (
    echo JFIC installation completed. You can now run Doctor-JFIC.cmd.
) else (
    echo JFIC installation failed. Review the messages above.
)
pause
exit /b %rc%
