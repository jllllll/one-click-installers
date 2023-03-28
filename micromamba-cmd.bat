@echo off

cd /D "%~dp0"

set INSTALL_ENV_DIR=%cd%\installer_files\env

if not exist "%INSTALL_ENV_DIR%\condabin\conda.bat" ( echo Conda not found. && goto end )
call "%INSTALL_ENV_DIR%\condabin\conda.bat" activate "%INSTALL_ENV_DIR%"

cmd /k "%*"

:end
pause
