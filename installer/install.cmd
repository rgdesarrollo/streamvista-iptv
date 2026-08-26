@echo off
setlocal EnableExtensions

set "APP_NAME=StreamVista IPTV"
set "INSTALL_DIR=%LOCALAPPDATA%\StreamVista IPTV"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\StreamVista IPTV"

if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%" >nul 2>nul

tar -xf "%~dp0app.zip" -C "%INSTALL_DIR%"
if errorlevel 1 (
  echo Installation failed while unpacking the application files.
  pause
  exit /b 1
)

mkdir "%START_MENU%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$shell = New-Object -ComObject WScript.Shell; $exe = Join-Path $env:LOCALAPPDATA 'StreamVista IPTV\streamvista_iptv.exe'; $icon = Join-Path $env:LOCALAPPDATA 'StreamVista IPTV\streamvista.ico'; $desktop = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'StreamVista IPTV.lnk')); $desktop.TargetPath = $exe; $desktop.WorkingDirectory = Split-Path $exe; $desktop.IconLocation = $icon; $desktop.Save(); $menu = $shell.CreateShortcut((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\StreamVista IPTV\StreamVista IPTV.lnk')); $menu.TargetPath = $exe; $menu.WorkingDirectory = Split-Path $exe; $menu.IconLocation = $icon; $menu.Save()"

start "" "%INSTALL_DIR%\streamvista_iptv.exe"
exit /b 0
