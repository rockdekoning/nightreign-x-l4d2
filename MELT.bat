@echo off
rem Nightfall melt: convert models from your own Nightreign install and install the mod into L4D2.
rem First run creates tools\melt_config.json; fill in the paths, then run this again.
setlocal
cd /d "%~dp0"
where python >nul 2>nul || (echo Python 3 is required: https://www.python.org/downloads/ & pause & exit /b 1)
if not exist "tools\melt_config.json" (
    python tools\melt.py setup
    echo.
    echo Edit tools\melt_config.json, then run MELT.bat again.
    pause
    exit /b 0
)
python tools\melt.py check || (pause & exit /b 1)
python tools\melt.py build %*
pause
