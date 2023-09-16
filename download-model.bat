@echo off

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

@rem HuggingFace user access token goes here between '=' and '"'
set "HF_TOKEN="

:start
echo.
echo Type the name of your desired Hugging Face model in the format organization/name or the URL to the model page.
echo.
echo Examples:
echo.
echo   facebook/opt-1.3b
echo   https://huggingface.co/facebook/opt-1.3b
echo   EleutherAI/pythia-1.4b-deduped
echo   https://huggingface.co/EleutherAI/pythia-1.4b-deduped
echo.
echo.
echo.
echo You can download a specific branch of a model's repo by using '--branch=BRANCH' or by using the full URL for the branch.
echo.
echo Examples:
echo.
echo   TheBloke/Wizard-Vicuna-7B-Uncensored-GPTQ --branch=gptq-4bit-32g-actorder_True
echo   https://huggingface.co/TheBloke/Wizard-Vicuna-7B-Uncensored-GPTQ --branch=gptq-4bit-32g-actorder_True
echo   https://huggingface.co/TheBloke/Wizard-Vicuna-7B-Uncensored-GPTQ/tree/gptq-4bit-32g-actorder_True
echo.
echo.
echo.
echo Other flags can also be used:
echo.
for /F "delims=" %%a in ('call python download-model.py --help') do echo %%a| findstr /C:"-h, --help" >nul && call :counter save || call :counter 1
set /A "FLAGS_LINE=%COUNTER_SAVE%+3"
for /F "skip=%FLAGS_LINE% delims=" %%a in ('call python download-model.py --help') do echo %%a
echo.

set /p "modelchoice=Input> "

set "modeldlcmd=python download-model.py %modelchoice:\=/%"
set "modelbranch=main"
echo %modelchoice%| findstr /C:"--branch=" >nul && (
  set "tempvar=%modelchoice:*--branch=%"
  set "tempvar=%tempvar:~1%"
  for /F "delims=" %%a in ("%tempvar%") do set "modelbranch=%%a"
  set "tempvar="
)
for /F "tokens=1,2* delims=/ " %%a in ("%modelchoice:\=/%") do (
  set "linklistcmd=python -c "exec^(\"import importlib\nlinks ^= importlib.import_module^('download-model'^).ModelDownloader^(^).get_download_links_from_huggingface^('%%a/%%b'^, '%modelbranch%'^)\nfor link in links[0]: print^(link^)\"^)""
)
echo %modelchoice:\=/%| findstr /C:"/tree/" >nul && for /F "tokens=3,4,6* delims=/ " %%a in ("%modelchoice:\=/%") do (
  set "modeldlcmd=python download-model.py %%a/%%b --branch=%%c %%d"
  set "modelbranch=%%c"
  set "linklistcmd=python -c "exec^(\"import importlib\nlinks ^= importlib.import_module^('download-model'^).ModelDownloader^(^).get_download_links_from_huggingface^('%%a/%%b'^, '%%c'^)\nfor link in links[0]: print^(link^)\"^)""
)
if "%modelchoice%" == "%modelchoice:*/tree/=%" echo %modelchoice%| findstr /C:"huggingface.co/" >nul && for /F "tokens=3,4* delims=/ " %%a in ("%modelchoice%") do (
  set "modeldlcmd=python download-model.py %%a/%%b %%c"
  set "linklistcmd=python -c "exec^(\"import importlib\nlinks ^= importlib.import_module^('download-model'^).ModelDownloader^(^).get_download_links_from_huggingface^('%%a/%%b'^, '%modelbranch%'^)\nfor link in links[0]: print^(link^)\"^)""
)
echo.
if "%modelchoice%" == "%modelchoice:*--specific-file=%" echo %modelchoice%| findstr /I /C:"GGML" /C:"GGUF" >nul && (
  echo GGML/GGUF model detected.
  echo Select a file to download or enter 'all' to download all files:
  for /F "usebackq tokens=7* delims=/" %%a in (`call %linklistcmd%`) do echo %%a%%b
  echo.
  set /p "filechoice=Input> "
  if /I "%filechoice%" == "all" set "filechoice="
  echo.
)

if defined filechoice set "modeldlcmd=%modeldlcmd% --specific-file=%filechoice%"

call %modeldlcmd%

:end
pause
set "modelchoice="
set "modelbranch="
set "modeldlcmd="
set "linklistcmd="
set "filechoice="
call :counter reset
cls
goto :start

:counter
if /I "%1" == "reset" (
  set "COUNTER="
  exit /b
) else if /I "%1" == "save" (
  set "COUNTER_SAVE=%COUNTER%"
  exit /b
)
set /A "COUNTER=%COUNTER%+%1"
exit /b
