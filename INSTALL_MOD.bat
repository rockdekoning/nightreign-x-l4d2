@echo off
rem Nightfall: one-click install of the mod into Left 4 Dead 2 (no Nightreign files needed).
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Nightfall installer

if not exist "addon\addoninfo.txt" (
    echo ERROR: I can't find the "addon" folder next to this file.
    echo You probably ran this from inside the ZIP. Right-click the ZIP, choose "Extract All",
    echo then run INSTALL_MOD.bat from the extracted folder.
    goto :fail
)

set "L4D2="
for %%P in (
    "%ProgramFiles(x86)%\Steam"
    "%ProgramFiles%\Steam"
    "C:\Steam" "C:\SteamLibrary"
    "D:\Steam" "D:\SteamLibrary" "D:\Games\Steam"
    "E:\Steam" "E:\SteamLibrary" "E:\Games\Steam"
    "F:\Steam" "F:\SteamLibrary"
) do (
    if not defined L4D2 if exist "%%~P\steamapps\common\Left 4 Dead 2\left4dead2\" set "L4D2=%%~P\steamapps\common\Left 4 Dead 2"
)

if not defined L4D2 (
    echo I could not find Left 4 Dead 2 automatically.
    echo.
    echo In Steam: right-click Left 4 Dead 2 - Manage - Browse local files.
    echo Copy the address from the top of the window that opens and paste it here.
    echo.
    set /p "L4D2=Left 4 Dead 2 folder: "
    set "L4D2=!L4D2:"=!"
)

if not exist "!L4D2!\left4dead2\" (
    echo ERROR: "!L4D2!" is not a Left 4 Dead 2 folder ^(no "left4dead2" folder inside it^).
    goto :fail
)
echo Found Left 4 Dead 2: !L4D2!
if not exist "!L4D2!\left4dead2\addons\" mkdir "!L4D2!\left4dead2\addons"

rem Build nightfall.vpk with the packer that ships with L4D2
set "BUILD=%TEMP%\nightfall_build"
if exist "%BUILD%" rmdir /s /q "%BUILD%"
mkdir "%BUILD%\nightfall"
xcopy "addon" "%BUILD%\nightfall" /e /i /q /y >nul

if exist "!L4D2!\bin\vpk.exe" (
    "!L4D2!\bin\vpk.exe" "%BUILD%\nightfall" >nul
)
if exist "%BUILD%\nightfall.vpk" (
    copy /y "%BUILD%\nightfall.vpk" "!L4D2!\left4dead2\addons\nightfall.vpk" >nul
    echo Installed: !L4D2!\left4dead2\addons\nightfall.vpk
) else (
    rem No packer available: install the files directly instead
    xcopy "addon\modes" "!L4D2!\left4dead2\modes" /e /i /q /y >nul
    xcopy "addon\scripts" "!L4D2!\left4dead2\scripts" /e /i /q /y >nul
    echo Installed the mod files directly into !L4D2!\left4dead2
)
rmdir /s /q "%BUILD%" 2>nul

echo.
echo ============================================================
echo  DONE. Now:
echo   1. Close Left 4 Dead 2 if it is open, then start it.
echo   2. Open the console with the ~ key ^(see HOW_TO_PLAY.md^).
echo   3. Type:   map c1m1_hotel nightfall
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
