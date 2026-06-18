@echo off
setlocal

for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0Helpers\.env") do (
    set "%%A=%%B"
)

set "ACTION=%~1"
if not defined ACTION set "ACTION=menu"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Helpers\Operations.ps1" -Action "%ACTION%"
set "EXITCODE=%ERRORLEVEL%"

if "%EXITCODE%" neq "0" pause
exit /b %EXITCODE%