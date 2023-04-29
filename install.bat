@echo off

@rem Based on the installer found here: https://github.com/Sygil-Dev/sygil-webui
@rem This script will install git and all dependencies
@rem using micromamba (an 8mb static-linked single-file binary, conda replacement).
@rem This enables a user to install this project without manually installing conda and git.

echo WARNING: This script relies on Micromamba which may have issues on some systems when installed under a path with spaces.
echo          May also have issues with long paths.&& echo.

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
    set "PACKAGES_TO_INSTALL=python=3.10.9 pytorch[version=2,build=py3.10_cuda11.7*] torchvision torchaudio pytorch-cuda=11.7 cuda-toolkit ninja git"
    set "CHANNEL=-c pytorch -c nvidia/label/cuda-11.7.0 -c nvidia -c conda-forge"
) else if /I "%gpuchoice%" == "B" (
    set "PACKAGES_TO_INSTALL=pytorch torchvision torchaudio cpuonly git"
    set "CHANNEL=-c conda-forge -c pytorch"
) else (
    echo Invalid choice. Exiting...
    exit
)

cd /D "%~dp0"

@rem better isolation for virtual environment
SET "CONDA_SHLVL="
SET PYTHONNOUSERSITE=1
SET "PYTHONPATH="

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

set MAMBA_ROOT_PREFIX=%cd%\installer_files\mamba
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MICROMAMBA_DOWNLOAD_URL=https://github.com/mamba-org/micromamba-releases/releases/download/1.4.0-0/micromamba-win-64
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

        mkdir "%MAMBA_ROOT_PREFIX%"
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
    )
)

@rem check if conda environment was actually created
if not exist "%INSTALL_ENV_DIR%\python.exe" ( echo. && echo Conda environment is empty. && goto end )

@rem activate installer env
call "%MAMBA_ROOT_PREFIX%\condabin\micromamba.bat" activate "%INSTALL_ENV_DIR%" || ( echo. && echo MicroMamba hook not found. && goto end )

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

@rem clone the repository and install the pip requirements
if exist text-generation-webui\ (
  cd text-generation-webui
  git pull
) else (
  git clone https://github.com/oobabooga/text-generation-webui.git
  call python -m pip install https://github.com/jllllll/bitsandbytes-windows-webui/raw/main/bitsandbytes-0.38.1-py3-none-any.whl
  cd text-generation-webui || goto end
)
call python -m pip install -r requirements.txt --upgrade
call python -m pip install -r extensions\api\requirements.txt --upgrade
call python -m pip install -r extensions\elevenlabs_tts\requirements.txt --upgrade
call python -m pip install -r extensions\google_translate\requirements.txt --upgrade
call python -m pip install -r extensions\silero_tts\requirements.txt --upgrade
call python -m pip install -r extensions\whisper_stt\requirements.txt --upgrade

@rem skip gptq install if cpu only
if /I not "%gpuchoice%" == "A" goto end

@rem download gptq and compile locally and if compile fails, install from wheel
if not exist repositories\ (
  mkdir repositories
)
cd repositories || goto end
if not exist GPTQ-for-LLaMa\ (
  git clone https://github.com/oobabooga/GPTQ-for-LLaMa.git -b cuda
)

cd GPTQ-for-LLaMa || goto end
call python -m pip install -r requirements.txt
if not exist "%INSTALL_ENV_DIR%\lib\site-packages\quant_cuda*" (
  @rem change from deprecated install method  python setup_cuda.py install
  cp setup_cuda.py setup.py
  call python -m pip install .
)
if not exist "%INSTALL_ENV_DIR%\lib\site-packages\quant_cuda*" (
  echo. && echo CUDA kernel compilation failed. Will try to install from wheel.&& echo.
  
  @rem workaround for python bug
  cd ..

  call python -m pip install https://github.com/jllllll/GPTQ-for-LLaMa-Wheels/raw/main/quant_cuda-0.0.0-cp310-cp310-win_amd64.whl || ( echo. && echo Wheel installation failed. && goto end )
)

:end
pause
