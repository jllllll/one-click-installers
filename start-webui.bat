@echo off

set "CMD_FLAGS=--chat"

@echo Starting the web UI...

cd /D "%~dp0"

@rem better isolation for virtual environment
SET "CONDA_SHLVL="
SET PYTHONNOUSERSITE=1
SET "PYTHONPATH="
SET "PYTHONHOME="
SET "TEMP=%cd%\installer_files\temp"
SET "TMP=%cd%\installer_files\temp"

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

set MAMBA_ROOT_PREFIX=%cd%\installer_files\mamba
set INSTALL_ENV_DIR=%cd%\installer_files\env

if not exist "%MAMBA_ROOT_PREFIX%\condabin\micromamba.bat" (
  call "%MAMBA_ROOT_PREFIX%\micromamba.exe" shell hook >nul 2>&1
)
call "%MAMBA_ROOT_PREFIX%\condabin\micromamba.bat" activate "%INSTALL_ENV_DIR%" || ( echo MicroMamba hook not found. && goto end )

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

cd text-generation-webui

call python server.py %CMD_FLAGS%

:end
pause
