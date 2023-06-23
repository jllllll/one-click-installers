@echo off

@rem This script will install miniconda and git with all dependencies for this project
@rem This enables a user to install this project without manually installing conda and git.

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

cd /D "%~dp0"

echo "%cd%"| findstr /C:" " >nul && call :PrintBigMessage "This script relies on Miniconda which can not be silently installed under a path with spaces." && goto end
call :PrintBigMessage "WARNING: This script relies on Miniconda which will fail to install if the path is too long."
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
) else if /I "%gpuchoice%" == "B" (
  set "PACKAGES_TO_INSTALL=python=3.10 ninja git"
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

set MINICONDA_DIR=%cd%\installer_files\miniconda3
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MINICONDA_DOWNLOAD_URL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe
set REPO_URL=https://github.com/oobabooga/text-generation-webui.git

if not exist "%MINICONDA_DIR%\Scripts\conda.exe" (
  @rem download miniconda
  echo Downloading Miniconda installer from %MINICONDA_DOWNLOAD_URL%
  call curl -LOk "%MINICONDA_DOWNLOAD_URL%"

  @rem install miniconda
  echo. && echo Installing Miniconda To "%MINICONDA_DIR%" && echo Please Wait... && echo.
  start "" /W /D "%cd%" "Miniconda3-latest-Windows-x86_64.exe" /InstallationType=JustMe /NoShortcuts=1 /AddToPath=0 /RegisterPython=0 /NoRegistry=1 /S /D=%MINICONDA_DIR% || ( echo. && echo Miniconda installer not found. && goto end )
  del /q "Miniconda3-latest-Windows-x86_64.exe"
  if not exist "%MINICONDA_DIR%\Scripts\activate.bat" ( echo. && echo Miniconda install failed. && goto end )
)

@rem activate miniconda
call "%MINICONDA_DIR%\Scripts\activate.bat" || ( echo Miniconda hook not found. && goto end )

@rem create the installer env
if not exist "%INSTALL_ENV_DIR%" (
  echo Packages to install: %PACKAGES_TO_INSTALL%
  call conda create --no-shortcuts -y -k -p "%INSTALL_ENV_DIR%" %CHANNEL% %PACKAGES_TO_INSTALL% || ( echo. && echo Conda environment creation failed. && goto end )
  if /I "%gpuchoice%" == "A" call conda run --live-stream -p "%INSTALL_ENV_DIR%" python -m pip install torch==2.0.1+cu117 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117|| ( echo. && echo Pytorch installation failed.&& goto end )
  if /I "%gpuchoice%" == "B" call conda run --live-stream -p "%INSTALL_ENV_DIR%" python -m pip install torch torchvision torchaudio|| ( echo. && echo Pytorch installation failed.&& goto end )
)

@rem check if conda environment was actually created
if not exist "%INSTALL_ENV_DIR%\python.exe" ( echo. && echo Conda environment is empty. && goto end )

@rem activate installer env
call conda activate "%INSTALL_ENV_DIR%" || ( echo. && echo Conda environment activation failed. && goto end )

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
