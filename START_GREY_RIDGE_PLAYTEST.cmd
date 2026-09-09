@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_isolated_playtest.ps1" -ExecutablePath "%~dp0build\windows\warseed-debug.exe" -Evaluate
set "WARSEED_EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%WARSEED_EXIT_CODE%"=="0" echo WARSEED playtest did not complete successfully.
pause
exit /b %WARSEED_EXIT_CODE%
