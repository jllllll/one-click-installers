cd /D "%~dp0"

@rem workaround for broken Windows installs
set PATH=%PATH%;%SystemRoot%\system32

if not exist "%cd%\text-generation-webui-installer.ps1" ( echo text-generation-webui-installer.ps1 not found! && pause && goto eof )
call powershell.exe -executionpolicy Bypass ". '%cd%\text-generation-webui-installer.ps1'"
