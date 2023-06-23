@echo off

SET TextOnly=False &REM True or False for Text only mode

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

set INSTALL_ENV_DIR=%cd%\installer_files\env

@rem regenerate conda hooks to ensure portability
call "%INSTALL_ENV_DIR%\Scripts\conda.exe" init --no-user >nul 2>&1

if not exist "%INSTALL_ENV_DIR%\condabin\conda.bat" ( echo Conda not found. && goto end )
call "%INSTALL_ENV_DIR%\condabin\conda.bat" activate "%INSTALL_ENV_DIR%"

@rem set default cuda toolkit to the one in the environment
set "CUDA_PATH=%INSTALL_ENV_DIR%"

cd text-generation-webui || goto end

echo.
echo Type the name of your desired Hugging Face model in the format organization/name or the URL to the model page.
echo.
echo Examples:
echo facebook/opt-1.3b
echo https://huggingface.co/facebook/opt-1.3b
echo EleutherAI/pythia-1.4b-deduped
echo https://huggingface.co/EleutherAI/pythia-1.4b-deduped
echo.

set /p "modelchoice=Input> "
echo %modelchoice%| findstr /C:"huggingface.co/"&& for /F "tokens=3,4 delims=/" %%a in ("%modelchoice%") do set "modelchoice=%%a/%%b"

goto %TextOnly%

:False
call python download-model.py %modelchoice%
goto end

:True
call python download-model.py %modelchoice% --text-only

:end
pause
