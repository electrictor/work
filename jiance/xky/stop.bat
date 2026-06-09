@echo off
cd /d "%~dp0"
set TASK_NAME=MessageMonitor
echo Stopping MessageMonitor...
schtasks /end /tn %TASK_NAME% >nul 2>&1
schtasks /delete /tn %TASK_NAME% /f >nul
if %errorlevel% equ 0 (
    echo Task stopped and removed successfully.
) else (
    echo No active task found or already removed.
)
pause
