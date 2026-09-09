@echo off
REM ==============================================================================
REM OpenMRS 3.x — Windows One-Command Orchestrator Launcher
REM ==============================================================================
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Script encountered an error.
    pause
)
endlocal
