@echo off
cd /d "%~dp0"

echo.
echo  +----------------------------------------------+
echo  ^|       Message Monitor - XKY Monitor         ^|
echo  +----------------------------------------------+
echo.

if not exist config.json (
    echo  [ERROR] config.json not found!
    pause
    exit /b 1
)

if not exist cookies.txt (
    echo  +------------------------------------------+
    echo  ^|  First-time setup: cookies.txt needed   ^|
    echo  +------------------------------------------+
    echo  ^|  1. Run export-cookies.ps1              ^|
    echo  ^|  2. Login to console.xiekeyun.com       ^|
    echo  ^|  3. Press Enter, then re-run start.bat  ^|
    echo  +------------------------------------------+
    pause
    exit /b 1
)

echo  [1/2] Creating scheduled task (every 10 min) ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-task.ps1"
echo     Done

echo.
echo  [2/2] Running first check ...
echo  -----------------------------------------------
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-messages.ps1"
echo.
echo  -----------------------------------------------
echo.
echo  +----------------------------------------------+
echo  ^|  Setup complete! Checking every 10 min.     ^|
echo  ^|                                              ^|
echo  ^|  Edit frequency : taskschd.msc               ^|
echo  ^|  Stop monitor   : stop.bat                   ^|
echo  +----------------------------------------------+
echo.
pause
