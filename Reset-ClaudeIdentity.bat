@echo off
setlocal
cd /d "%~dp0"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reset-ClaudeIdentity.ps1"
set "EC=%ERRORLEVEL%"

rem The script prompts for Enter itself on a clean exit (0) or partial wipe (2).
rem Any other code means PowerShell could not run it, so hold the window here.
if "%EC%"=="0" goto end
if "%EC%"=="2" goto end
echo.
echo PowerShell could not run the script (code %EC%).
echo The window is kept open so you can read the message above.
pause

:end
endlocal
