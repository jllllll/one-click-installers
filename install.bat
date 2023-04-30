@echo off

echo WARNING: This script relies on Micromamba and Conda which may have issues on some systems when installed under a path with spaces.
echo          May also have issues with long paths.&& echo.

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
  set "PACKAGES_TO_INSTALL=pytorch[version=2,build=py3.10_cuda11.7*] torchvision torchaudio pytorch-cuda=11.7 cuda-toolkit ninja git"
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
SET "TEMP=%cd%\installer_files\temp"
SET "TMP=%cd%\installer_files\temp"

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

set PYTHON_VERSION=3.10
set MAMBA_ROOT_PREFIX=%cd%\installer_files\mamba
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MICROMAMBA_DOWNLOAD_URL=https://github.com/mamba-org/micromamba-releases/releases/download/1.4.0-0/micromamba-win-64
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

@rem activate installer env
call "%INSTALL_ENV_DIR%\condabin\conda.bat" activate "%INSTALL_ENV_DIR%" || ( echo. && echo Conda activation failed. && goto end )

@rem install dependencies using conda
if not exist "%INSTALL_ENV_DIR%\Library\git-cmd.exe" (
  echo Packages to install: %PACKAGES_TO_INSTALL%
  call conda install -y %CHANNEL% %PACKAGES_TO_INSTALL%
)

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
