@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-RazerDial.ps1" -AllowUpdates
if errorlevel 1 pause
endlocal
