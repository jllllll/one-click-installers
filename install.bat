@echo off

cd /D "%~dp0"

call :PrintBigMessage "WARNING: This script relies on Micromamba and Conda which may have issues when installed under a path with spaces." "         May also have issues with long paths."
set "SPCHARMESSAGE="WARNING: Special characters were detected in the installation path!" "         This can cause the installation to fail!""
echo "%CD%"| findstr /R /C:"[!#\$%&()\*+,;<=>?@\[\]\^`{|}~]" >nul && (
  call :PrintBigMessage %SPCHARMESSAGE%
)
set SPCHARMESSAGE=

pause
cls

@rem Based on the installer found here: https://github.com/Sygil-Dev/sygil-webui
@rem This script will install conda and git with all dependencies for this project
@rem using micromamba (an 8mb static-linked single-file binary, conda replacement).
@rem This enables a user to install this project without manually installing conda and git.

echo What is your GPU?
echo.
echo A) NVIDIA
echo B) None (I want to run in CPU mode)
echo.
set /p "gpuchoice=Input> "
set gpuchoice=%gpuchoice:~0,1%

if /I "%gpuchoice%" == "A" (
  set "PACKAGES_TO_INSTALL=cuda-toolkit ninja git"
  set "CHANNEL=-c nvidia/label/cuda-11.7.0 -c nvidia -c conda-forge"
) else if /I "%gpuchoice%" == "B" (
  set "PACKAGES_TO_INSTALL=ninja git"
  set "CHANNEL=-c conda-forge"
) else (
  echo Invalid choice. Exiting...
  exit
)

@rem better isolation for virtual environment
SET "CONDA_SHLVL="
SET PYTHONNOUSERSITE=1
SET "PYTHONPATH="
SET "PYTHONHOME="
SET "TEMP=%cd%\installer_files\temp"
SET "TMP=%cd%\installer_files\temp"

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

set PYTHON_VERSION=3.10
set MAMBA_ROOT_PREFIX=%cd%\installer_files\mamba
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MICROMAMBA_DOWNLOAD_URL=https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64
set REPO_URL=https://github.com/oobabooga/text-generation-webui.git

if not exist "%INSTALL_ENV_DIR%" (
  @rem download micromamba
  echo "Downloading Micromamba from %MICROMAMBA_DOWNLOAD_URL% to %MAMBA_ROOT_PREFIX%\micromamba.exe"
  mkdir "%MAMBA_ROOT_PREFIX%" >nul
  mkdir "%TEMP%" >nul
  call curl -L "%MICROMAMBA_DOWNLOAD_URL%" > "%MAMBA_ROOT_PREFIX%\micromamba.exe"

  @rem test the mamba binary
  echo Micromamba version:
  call "%MAMBA_ROOT_PREFIX%\micromamba.exe" --version || ( echo. && echo Micromamba not found. && goto end )

  @rem create the installer env and install conda into it
  call "%MAMBA_ROOT_PREFIX%\micromamba.exe" create -y --no-shortcuts --always-copy --prefix "%INSTALL_ENV_DIR%" -c main conda "python=%PYTHON_VERSION%"
  echo. && echo Removing Micromamba && echo.
  del /q /s "%MAMBA_ROOT_PREFIX%" >nul
  rd /q /s "%MAMBA_ROOT_PREFIX%" >nul
  if not exist "%INSTALL_ENV_DIR%\condabin\conda.bat" ( echo. && echo Conda install failed. && goto end )
)

@rem regenerate conda hooks to ensure portability
call "%INSTALL_ENV_DIR%\Scripts\conda.exe" init --no-user >nul 2>&1

@rem activate installer env
call "%INSTALL_ENV_DIR%\condabin\conda.bat" activate "%INSTALL_ENV_DIR%" || ( echo. && echo Conda activation failed. && goto end )

@rem install dependencies using conda
if not exist "%INSTALL_ENV_DIR%\Library\git-cmd.exe" (
  echo Packages to install: %PACKAGES_TO_INSTALL%
  call conda install -y %CHANNEL% %PACKAGES_TO_INSTALL%
  if /I "%gpuchoice%" == "A" call python -m pip install torch==2.0.1+cu117 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117|| ( echo. && echo Pytorch installation failed.&& goto end )
  if /I "%gpuchoice%" == "B" call python -m pip install torch torchvision torchaudio|| ( echo. && echo Pytorch installation failed.&& goto end )
)

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

@rem clone the repository
if exist text-generation-webui\ (
  cd text-generation-webui
  git pull
) else (
  git clone https://github.com/oobabooga/text-generation-webui.git
  cd text-generation-webui || goto end
)

@rem Loop through each "git+" requirement and uninstall it   workaround for inconsistent git package updating
for /F "delims=" %%a in (requirements.txt) do echo "%%a"| findstr /C:"git+" >nul&& for /F "tokens=4 delims=/" %%b in ("%%a") do for /F "delims=@" %%c in ("%%b") do python -m pip uninstall -y %%c

@rem install the pip requirements
call python -m pip install -r requirements.txt --upgrade

@rem install all extension requirements except for superbooga
for /R extensions %%I in (requirements.t?t) do (
  echo %%~I| FINDSTR "extensions\superbooga" >nul 2>&1 || call python -m pip install -r %%~I --upgrade
)

@rem skip gptq and exllama install if cpu only
if /I not "%gpuchoice%" == "A" goto end

@rem install exllama and gptq-for-llama below
if not exist repositories\ (
  mkdir repositories
)
cd repositories || goto end

@rem download or update exllama as needed
if not exist exllama\ (
  git clone https://github.com/turboderp/exllama.git
) else pushd exllama && git pull && popd

@rem download gptq and compile locally and if compile fails, install from wheel
if not exist GPTQ-for-LLaMa\ (
  git clone https://github.com/oobabooga/GPTQ-for-LLaMa.git -b cuda
)
cd GPTQ-for-LLaMa || goto end
if not exist "%INSTALL_ENV_DIR%\lib\site-packages\quant_cuda*" (
  @rem change from deprecated install method  python setup_cuda.py install
  cp setup_cuda.py setup.py
  call python -m pip install .
)
set "gptqMessage="WARNING: GPTQ-for-LLaMa compilation failed, but this is FINE and can be ignored!" "The installer will proceed to install a pre-compiled wheel.""
if not exist "%INSTALL_ENV_DIR%\lib\site-packages\quant_cuda*" (
  call :PrintBigMessage %gptqMessage%
  
  @rem workaround for python bug
  cd ..

  call python -m pip install https://github.com/jllllll/GPTQ-for-LLaMa-Wheels/raw/main/quant_cuda-0.0.0-cp310-cp310-win_amd64.whl && echo Wheel installation success! || (
    echo.
    echo ERROR: GPTQ wheel installation failed. You will not be able to use GPTQ-based models.
    goto end
  )
)



@rem below are functions for the script   next line skips these during normal execution
goto end

:GetHighestCompute
if not defined HIGHEST_COMPUTE (
  set "HIGHEST_COMPUTE=%1"
) else if %1 GTR %HIGHEST_COMPUTE% set "HIGHEST_COMPUTE=%1"
exit /b

:PrintBigMessage
echo. && echo.
echo *******************************************************************
for %%M in (%*) do echo * %%~M
echo *******************************************************************
echo. && echo.
exit /b

:end
pause
