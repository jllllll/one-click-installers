cd /D "%~dp0"
if not exist "%cd%\text-generation-webui-installer.ps1" ( echo text-generation-webui-installer.ps1 not found! && goto end )
call powershell.exe -executionpolicy Bypass ". '%cd%\text-generation-webui-installer.ps1'"

:end
pause
