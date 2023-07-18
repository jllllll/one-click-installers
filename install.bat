@echo off

@rem Based on the installer found here: https://github.com/Sygil-Dev/sygil-webui
@rem This script will install git and all dependencies needed for the webui
@rem using micromamba (an 8mb static-linked single-file binary, conda replacement).
@rem This enables a user to install this project without manually installing conda and git.

cd /D "%~dp0"

call :PrintBigMessage "WARNING: This script relies on Micromamba which may have issues when installed under a path with spaces." "         May also have issues with long paths."
set "SPCHARMESSAGE="WARNING: Special characters were detected in the installation path!" "         This can cause the installation to fail!""
echo "%CD%"| findstr /R /C:"[!#\$%&()\*+,;<=>?@\[\]\^`{|}~]" >nul && (
  call :PrintBigMessage %SPCHARMESSAGE%
)
set SPCHARMESSAGE=

pause
cls

echo What is your GPU?
echo.
echo A) NVIDIA
echo B) None (I want to run in CPU mode)
echo.
set /p "gpuchoice=Input> "
set gpuchoice=%gpuchoice:~0,1%

if /I "%gpuchoice%" == "A" (
    set "PACKAGES_TO_INSTALL=python=3.10 cuda-toolkit ninja git"
    set "CHANNEL=-c nvidia/label/cuda-11.7.0 -c nvidia -c conda-forge"
    set "PYTORCH_CMD=torch==2.0.1+cu117 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117"
) else if /I "%gpuchoice%" == "B" (
    set "PACKAGES_TO_INSTALL=python=3.10 ninja git"
    set "CHANNEL=-c conda-forge"
    set "PYTORCH_CMD=torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
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

set MAMBA_ROOT_PREFIX=%cd%\installer_files\mamba
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MICROMAMBA_DOWNLOAD_URL=https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-win-64
set REPO_URL=https://github.com/oobabooga/text-generation-webui.git
set umamba_exists=F

@rem figure out whether git and conda needs to be installed
call "%MAMBA_ROOT_PREFIX%\micromamba.exe" --version >nul 2>&1
if "%ERRORLEVEL%" EQU "0" set umamba_exists=T

@rem (if necessary) install git and conda into a contained environment
if "%PACKAGES_TO_INSTALL%" NEQ "" (
  @rem download micromamba
  if "%umamba_exists%" == "F" (
    echo "Downloading Micromamba from %MICROMAMBA_DOWNLOAD_URL% to %MAMBA_ROOT_PREFIX%\micromamba.exe"
  
    mkdir "%MAMBA_ROOT_PREFIX%" >nul
    mkdir "%TEMP%" >nul
    call curl -Lk "%MICROMAMBA_DOWNLOAD_URL%" > "%MAMBA_ROOT_PREFIX%\micromamba.exe" || ( echo. && echo Micromamba failed to download. && goto end )
  
    @rem test the mamba binary
    echo Micromamba version:
    call "%MAMBA_ROOT_PREFIX%\micromamba.exe" --version || ( echo. && echo Micromamba not found. && goto end )
  )
  
  @rem create micromamba hook
  if not exist "%MAMBA_ROOT_PREFIX%\condabin\micromamba.bat" (
    call "%MAMBA_ROOT_PREFIX%\micromamba.exe" shell hook >nul 2>&1
  )
  
  @rem create the installer env
  if not exist "%INSTALL_ENV_DIR%" (
    echo Packages to install: %PACKAGES_TO_INSTALL%
    call "%MAMBA_ROOT_PREFIX%\micromamba.exe" create -y --no-shortcuts --prefix "%INSTALL_ENV_DIR%" %CHANNEL% %PACKAGES_TO_INSTALL% || ( echo. && echo Conda environment creation failed. && goto end )
    call "%MAMBA_ROOT_PREFIX%\micromamba.exe" run --prefix "%INSTALL_ENV_DIR%" python -m pip install %PYTORCH_CMD%|| ( echo. && echo Pytorch installation failed.&& goto end )
  )
)

@rem check if conda environment was actually created
if not exist "%INSTALL_ENV_DIR%\python.exe" ( echo. && echo Conda environment is empty. && goto end )

@rem activate installer env
call "%MAMBA_ROOT_PREFIX%\condabin\micromamba.bat" activate "%INSTALL_ENV_DIR%" || ( echo. && echo MicroMamba hook not found. && goto end )

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

@rem Install llama-cpp-python built with cuBLAS support for NVIDIA GPU acceleration
for /F "tokens=2 delims==;" %%a in ('findstr /C:"llama-cpp-python==" requirements.txt') do python -m pip install llama-cpp-python==%%a --force-reinstall --no-deps --index-url=https://jllllll.github.io/llama-cpp-python-cuBLAS-wheels/AVX2/cu117

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
