@echo off
setlocal
title StreamVista - crear EXE
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter no esta disponible en PATH.
  pause
  exit /b 1
)

if not exist "windows\CMakeLists.txt" (
  call flutter create --platforms=windows .
  if errorlevel 1 goto :failed
)

call flutter pub get
if errorlevel 1 goto :failed
call flutter build windows --release
if errorlevel 1 goto :failed

echo.
echo LISTO. Tu aplicacion esta en:
echo %CD%\build\windows\x64\runner\Release
explorer "%CD%\build\windows\x64\runner\Release"
goto :end

:failed
echo.
echo No se pudo crear el EXE. Copia el texto de esta ventana y envialo.

:end
pause
