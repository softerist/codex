@echo off
setlocal
title Codex Clean Reinstall Toolkit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Codex-Reinstall.ps1" %*
set "toolExit=%ERRORLEVEL%"
if errorlevel 1 (
    echo.
    echo The toolkit stopped with an error.
    if "%~1"=="" pause
)
endlocal & exit /b %toolExit%
