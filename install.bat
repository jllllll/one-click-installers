@echo off

@rem This script will install miniconda and git with all dependencies for this project
@rem This enables a user to install this project without manually installing conda and git.

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

cd /D "%~dp0"
echo "%cd%"| findstr /C:" " >nul && echo This script relies on Miniconda which can not be silently installed under a path with spaces. && goto end
echo WARNING: This script relies on Miniconda which will fail to install if the path is too long.&& echo.

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
  set "PACKAGES_TO_INSTALL=python=3.10 pytorch[version=2,build=py3.10_cuda11.7*] torchvision torchaudio pytorch-cuda=11.7 cuda-toolkit ninja git"
  set "CHANNEL=-c pytorch -c nvidia/label/cuda-11.7.0 -c nvidia -c conda-forge"
) else if /I "%gpuchoice%" == "B" (
  set "PACKAGES_TO_INSTALL=pytorch torchvision torchaudio cpuonly git"
  set "CHANNEL=-c pytorch -c conda-forge"
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
)

@rem check if conda environment was actually created
if not exist "%INSTALL_ENV_DIR%\python.exe" ( echo. && echo Conda environment is empty. && goto end )

@rem activate installer env
call conda activate "%INSTALL_ENV_DIR%" || ( echo. && echo Conda environment activation failed. && goto end )

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

@rem clone the repository and install the pip requirements
if exist text-generation-webui\ (
  cd text-generation-webui
  git pull
) else (
  git clone https://github.com/oobabooga/text-generation-webui.git
  cd text-generation-webui || goto end
)
call python -m pip install -r requirements.txt --upgrade

@rem install all extension requirements except for superbooga
for /R extensions %%I in (requirements.t?t) do (
  echo %%~I| FINDSTR "extensions\superbooga" >nul 2>&1 || call python -m pip install -r %%~I --upgrade
)

@rem Latest bitsandbytes requires minimum compute 7.0   will try to install old version if needed
set "MIN_COMPUTE=70"
set "OLD_BNB=https://github.com/jllllll/bitsandbytes-windows-webui/raw/main/bitsandbytes-0.38.1-py3-none-any.whl"
if exist "%INSTALL_ENV_DIR%\bin\__nvcc_device_query.exe" (
  for /f "delims=" %%G in ('call "%INSTALL_ENV_DIR%\bin\__nvcc_device_query.exe"') do (
    for %%C in (%%G) do (
      call :GetHighestCompute %%C
    )
  )
)
set "bnbInstallFailMessage="You will be unable to use --load-in-8bit until you install bitsandbytes 0.38.1!""
set "bnbInstallSuccessMessage="Older version of bitsandbytes has been installed to maintain compatibility." "You will be unable to use --load-in-4bit!""
if defined HIGHEST_COMPUTE (
  if %HIGHEST_COMPUTE% LSS %MIN_COMPUTE% (
    call python -m pip install %OLD_BNB% --force-reinstall --no-deps && call :PrintBigMessage "WARNING: GPU with compute < 7.0 detected!" %bnbInstallSuccessMessage% || ^
call :PrintBigMessage "WARNING: GPU with compute < 7.0 detected!" %bnbInstallFailMessage% 
  )
)


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
