@echo off

@echo Starting the web UI...

cd /D "%~dp0"

@rem better isolation for virtual environment
SET "CONDA_SHLVL="
SET PYTHONNOUSERSITE=1
SET "PYTHONPATH="
SET "TEMP=%cd%\installer_files\temp"
SET "TMP=%cd%\installer_files\temp"

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

set INSTALL_ENV_DIR=%cd%\installer_files\env
set MINICONDA_DIR=%cd%\installer_files\miniconda3

if not exist "%MINICONDA_DIR%\Scripts\activate.bat" ( echo Miniconda not found. && goto end )
call "%MINICONDA_DIR%\Scripts\activate.bat" activate "%INSTALL_ENV_DIR%"
cd text-generation-webui

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

call python server.py --auto-devices --chat --model-menu

:end
pause
