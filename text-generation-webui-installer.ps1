<# This script will install git and all dependencies
using micromamba (an 8mb static-linked single-file binary, conda replacement).
This enables a user to install this project without manually installing conda and git. #>

Write-Warning '
This script relies on Micromamba which may have issues on some systems when installed under a path with spaces.
May also have issues with long paths.
'

$env:MAMBA_ROOT_PREFIX= "$PSScriptRoot\installer_files\mamba"
$installerEnvDir = "$PSScriptRoot\installer_files\env"
$micromambaDownloadUrl = 'https://github.com/mamba-org/micromamba-releases/releases/download/1.4.0-0/micromamba-win-64'
$webuiRepoUrl = 'https://github.com/oobabooga/text-generation-webui.git'
$bitsandbytesWindowsWheel = 'https://github.com/jllllll/bitsandbytes-windows-webui/raw/main/bitsandbytes-0.37.2-py3-none-any.whl'
$gptqRepoUrl = 'https://github.com/oobabooga/GPTQ-for-LLaMa.git'
$gptqBackupWheel = 'https://github.com/jllllll/GPTQ-for-LLaMa-Wheels/raw/main/quant_cuda-0.0.0-cp310-cp310-win_amd64.whl' # Not guaranteed to work!




cls
do {
	$gpuChoice = Read-Host "What is your GPU?`nA) NVIDIA`nB) None (I want to run in CPU mode)`n"
	if ($gpuChoice -notmatch '^A|B$') {
		cls
		Write-Warning 'Invalid input. Please use A or B'
	}
} until ($gpuChoice -match '^A|B$')

switch ($gpuChoice)
{
	'A' {
		$packages = 'python=3.10.9','torchvision','torchaudio','pytorch-cuda=11.7','cuda-toolkit','conda-forge::ninja','conda-forge::git'
		$packageChannels = '-c pytorch','-c nvidia/label/cuda-11.7.0','-c nvidia'
	}

	'B' {
		$packages = 'pytorch torchvision torchaudio cpuonly git'
		$packageChannels = '-c conda-forge -c pytorch'
	}
}

$ProgressPreference = 'SilentlyContinue'
$micromambaExe = $env:MAMBA_ROOT_PREFIX + '\micromamba.exe'

# figure out whether micromamba needs to be installed and download micromamba
if (!(Test-Path $env:MAMBA_ROOT_PREFIX)) {mkdir $env:MAMBA_ROOT_PREFIX > $null}
if (!(Test-Path $micromambaExe)) {Invoke-RestMethod $micromambaDownloadUrl -OutFile $micromambaExe}
if (!(Test-Path $micromambaExe)) {Write-Error 'Unable to download micromamba.';pause;exit}

# micromamba hook
. $micromambaExe shell hook -s powershell | Out-String | Invoke-Expression

# create the installer env
if (!(Test-Path ($installerEnvDir + '\python.exe')))
{
	micromamba create -y --prefix $installerEnvDir $packageChannels.split() $packages
}

# activate installer env
if (Test-Path ($installerEnvDir + '\python.exe')) {micromamba activate $installerEnvDir}

# clone the repository and install the pip requirements
if (!(Test-Path "$PSScriptRoot\text-generation-webui"))
{
	git clone $webuiRepoUrl "$PSScriptRoot\text-generation-webui"
	python -m pip install $bitsandbytesWindowsWheel
	cd "$PSScriptRoot\text-generation-webui"
}
else {cd "$PSScriptRoot\text-generation-webui"; git pull}
python -m pip install -r requirements.txt --upgrade
python -m pip install -r extensions\api\requirements.txt --upgrade
python -m pip install -r extensions\elevenlabs_tts\requirements.txt --upgrade
python -m pip install -r extensions\google_translate\requirements.txt --upgrade
python -m pip install -r extensions\silero_tts\requirements.txt --upgrade
python -m pip install -r extensions\whisper_stt\requirements.txt --upgrade

# skip gptq install if cpu only
if ($gpuChoice -eq 'A')
{
	# download gptq and compile locally and if compile fails, install from wheel
	if (!(Test-Path '.\repositories')) {mkdir 'repositories' > $null}
	if (!(Test-Path '.\repositories\GPTQ-for-LLaMa'))
	{
		git clone $gptqRepoUrl '.\repositories\GPTQ-for-LLaMa' -b cuda
		cd '.\repositories\GPTQ-for-LLaMa'
		python -m pip install -r requirements.txt
		python setup_cuda.py install
		if (!(Test-Path "$installerEnvDir\lib\site-packages\quant_cuda-0.0.0-py3.10-win-amd64.egg"))
		{
			Write-Warning 'CUDA kernal compilation failed. Will try to install from wheel.'
			python -m pip install $gptqBackupWheel; if ($LASTEXITCODE -ne 0) {Write-Error 'Wheel installation failed.';pause;exit}
		}
	}
}

pause
