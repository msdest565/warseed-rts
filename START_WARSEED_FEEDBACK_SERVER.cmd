@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_feedback_server.ps1" -Lan
set "WARSEED_EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%WARSEED_EXIT_CODE%"=="0" echo WARSEED feedback server stopped with an error.
pause
exit /b %WARSEED_EXIT_CODE%
