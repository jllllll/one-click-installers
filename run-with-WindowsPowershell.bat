@echo off

cd /D "%~dp0"

@rem workaround for broken Windows installs
set "PATH=%PATH%;%SystemRoot%\system32\WindowsPowerShell\v1.0;%SystemRoot%\system32"

if not exist "%cd%\webui.ps1" ( echo webui.ps1 not found! && pause && goto eof )
call powershell.exe -executionpolicy Bypass ". '%cd%\webui.ps1'"
