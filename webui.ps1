$CMD_FLAGS = '--chat' # Not used if CMD_FLAGS.txt is present


$MINICONDA_DOWNLOAD_URL = $(
    if ($null -eq $IsWindows -or $IsWindows) {$IsOnWindows = $true; 'https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-Windows-x86_64.exe'}
    elseif ($IsLinux) {(
        'https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-Linux-{0}.sh' -f $(switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
            'x64' { if (Test-Path '/proc/sys/fs/binfmt_misc/WSLInterop') { $IsOnWSL = $true}; 'x86_64' }
            {$_ -imatch 'arm'} { $IsArm = $true; 'aarch64' }
            Default {Write-Error "Unknown system architecture: $_! This script runs only on x64 or arm64!"; pause; Exit-PSSession}
        })
    )}
    elseif ($IsMacOS) {(
        'https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-MacOSX--{0}.sh' -f $(switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
            'x64' { 'x86_64' }
            {$_ -imatch 'arm'} { 'arm64' }
            Default {Write-Error "Unknown system architecture: $_! This script runs only on x64 or arm64!"; pause; Exit-PSSession}
        })
    )}
    else {Write-Error "Could not identify operating system! This is likely a bug."; pause; Exit-PSSession}
)
$INSTALL_DIR_ROOT = if ($IsOnWSL) {Join-Path (Resolve-Path '~').Path 'text-gen-install'} else {$PSScriptRoot}
$INSTALL_DIR = Join-Path $INSTALL_DIR_ROOT 'installer_files'
$CONDA_ROOT_PREFIX = Join-Path $INSTALL_DIR 'conda'
$INSTALL_ENV_DIR = Join-Path $INSTALL_DIR 'env'


$ENV_VARS = @{
    PYTHONNOUSERSITE = '1'
    CUDA_PATH = $INSTALL_ENV_DIR
    CUDA_HOME = $INSTALL_ENV_DIR
}

if ($IsOnWindows) { $env:TMP=$env:TEMP = $INSTALL_DIR }
if ($IsOnWSL) { $ENV_VARS.'LD_LIBRARY_PATH' = '{0}/lib:/usr/lib/wsl/lib:{1}' -f $INSTALL_ENV_DIR,[Environment]::GetEnvironmentVariable('LD_LIBRARY_PATH') }

$UNSET_ENV_VARS = @(
    'PYTHONPATH'
    'PYTHONHOME'
)

$ENV_VARS.GetEnumerator().ForEach({[Environment]::SetEnvironmentVariable($_.Key,$_.Value)})
$UNSET_ENV_VARS.ForEach({[Environment]::SetEnvironmentVariable($_,$null)})


function PrintBigMessage([string]$message,[string]$textColor='White')
{
    [string[]]$messageOut = @("`n`n*******************************************************************")
    $message.Trim().Split("`n").ForEach({$messageOut += "* $_"})
    $messageOut += "*******************************************************************`n`n"
    Write-Host $messageOut -Separator "`n" -ForegroundColor $textColor
}

function DownloadModel
{
    $configChoice = Read-Host "1 - All model files`n2 - Configuration files only`n`nInput"
    switch ($configChoice)
    {
        '2' {$configSetting = '--text-only'; break}
        Default {}
    }
    Clear-Host
    $modelChoice = Read-Host 'Type the name of your desired Hugging Face model in the format organization/name or the URL to the model page.

Examples:

facebook/opt-1.3b
https://huggingface.co/facebook/opt-1.3b
EleutherAI/pythia-1.4b-deduped
https://huggingface.co/EleutherAI/pythia-1.4b-deduped

Input'

    $modelChoice = '{0}/{1}' -f $modelChoice.split('/')[-2,-1]
    python 'download-model.py' $modelChoice $configSetting
}

function InstallDependencies
{
    $gpuChoice = Read-Host "What is your GPU?`n
A) NVIDIA
B) Mac
C) None (I want to run in CPU mode)`n`nInput"

    switch ($gpuChoice)
    {
        'a' {$condaPackages = 'cuda ninja git -c nvidia/label/cuda-11.7.0 -c nvidia'; $pipPackages = 'torch==2.0.1+cu117 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu117'; break}
        {'b','c' -contains $_} {$condaPackages = 'ninja git'; $pipPackages = 'torch torchvision torchaudio'; break}
        Default {Write-Error 'Invalid choice. Exiting...'; pause; Exit-PSSession}
    }

    conda install -y -k $condaPackages.Split()
    if ($LASTEXITCODE -eq 1) {Write-Error 'Conda packages failed to install!'; pause; Exit-PSSession}
    python -m pip install $pipPackages.Split()
    if ($LASTEXITCODE -eq 1) {Write-Error 'pip packages failed to install!'; pause; Exit-PSSession}

    git clone 'https://github.com/oobabooga/text-generation-webui.git' $(Join-Path $INSTALL_DIR_ROOT 'text-generation-webui')
    if ($LASTEXITCODE -eq 1) {Write-Error 'text-generation-webui repository failed to download!'; pause; Exit-PSSession}
}

function UpdateDependencies
{
    Join-Path $INSTALL_DIR_ROOT 'text-generation-webui' | Set-Location -ErrorAction Stop

    git pull

    # Loop through each "git+" requirement and uninstall it   Workaround for git+ packages not updating properly
    (Get-Content 'requirements.txt').where({$_ -match 'git\+'}).foreach({. {python -m pip uninstall -y $_.split('/')[-1].split('@')[0]} | Out-Default})

    python -m pip install -r requirements.txt --upgrade
    if ($LASTEXITCODE -eq 1) {pause; Exit-PSSession}

    # Installs/Updates dependencies from all requirements.txt
    $extensions = Get-ChildItem $(Join-Path $(Join-Path $INSTALL_DIR_ROOT 'text-generation-webui') 'extensions') -Include 'requirements.txt' -File -Recurse -Depth 1
    $extensions.where({$_.Directory.Name -ne 'superbooga'}).foreach({. {python -m pip install -r $_.FullName --upgrade} | Out-Default})

    # The following dependencies are for CUDA, not CPU
    $torchVersion = (python -m pip show torch).where({$_ -match 'Version:'}).split()[-1]
    if ($torchVersion -notmatch '\+cu') {return}

    New-Item 'repositories' -ItemType 'Directory' -ErrorAction SilentlyContinue > $null

    Set-Location 'repositories'

    # Install or update exllama as needed
    if (!(Test-Path $(Join-Path $(Resolve-Path '.') 'exllama'))) {git clone 'https://github.com/turboderp/exllama.git'}
    else {Push-Location 'exllama' -ErrorAction Stop; git pull; Pop-Location}
    
    # Fix build issue with exllama in Linux/WSL
    if ($IsLinux -and !(Test-Path $(Join-Path $INSTALL_ENV_DIR 'lib64'))) {ln -s "$INSTALL_ENV_DIR/lib" "$INSTALL_ENV_DIR/lib64"}

    # Install or update GPTQ-for-LLaMa as needed
    if (!(Test-Path $(Join-Path $(Resolve-Path '.') 'GPTQ-for-LLaMa'))) {git clone 'https://github.com/oobabooga/GPTQ-for-LLaMa.git' -b 'cuda'; Push-Location 'GPTQ-for-LLaMa' -ErrorAction Stop}
    else {Push-Location 'GPTQ-for-LLaMa'; git pull}
    # Compile and install GPTQ-for-LLaMa
    $sitePackages = python -c "import site`nfor sitedir in site.getsitepackages():`n`tif 'site-packages' in sitedir:`n`t`tprint(sitedir);break"
    if ($LASTEXITCODE -ne 0 -or $sitePackages -in $null,'') {Write-Error 'Could not find the path to your Python packages!'; pause; Exit-PSSession}
    $gptqInstallPath = Join-Path $sitePackages 'quant_cuda*'
    if (!(Test-Path $gptqInstallPath))
    {
        Copy-Item 'setup_cuda.py' 'setup.py' -Force
        python -m pip install .
    }
    Pop-Location
    if (!(Test-Path $gptqInstallPath))
    {
        if ($IsArm -or $IsMacOS) {Write-Error "ERROR: GPTQ CUDA kernel compilation failed.`n       You will not be able to use GPTQ-based models."}
        else {
            PrintBigMessage "WARNING: GPTQ-for-LLaMa compilation failed, but this is FINE and can be ignored!`nThe installer will proceed to install a pre-compiled wheel."
            if ($IsOnWindows) {python -m pip install 'https://github.com/jllllll/GPTQ-for-LLaMa-Wheels/raw/main/quant_cuda-0.0.0-cp310-cp310-win_amd64.whl'}
            elseif ($IsLinux) {python -m pip install 'https://github.com/jllllll/GPTQ-for-LLaMa-Wheels/raw/Linux-x64/quant_cuda-0.0.0-cp310-cp310-linux_x86_64.whl'}
            if ($LASTEXITCODE -eq 0) {Write-Output "`nWheel installation success!"}
            else {Write-Error "ERROR: GPTQ wheel installation failed.`n       You will not be able to use GPTQ-based models."}
        }
    }
    Set-Location $INSTALL_DIR_ROOT
}


if ($IsOnWindows)
{
    if ($INSTALL_DIR_ROOT -match ' ') {Write-Host "`nThis script relies on Miniconda which can not be silently installed under a path with spaces.`n" -ForegroundColor Red; pause; Exit-PSSession}
    if ($(Compare-Object $INSTALL_DIR_ROOT.ToCharArray() '!#$%&()*+,;<=>?@[]^`{|}~'.ToCharArray() -excludeDifferent)) {PrintBigMessage "WARNING: Special characters were detected in the installation path!`n         This can cause the installation to fail!" 'Yellow'}
}

$ProgressPreference = 'SilentlyContinue'
$CONDA_HOOK = Join-Path $(Join-Path $(Join-Path $CONDA_ROOT_PREFIX 'shell') 'condabin') 'conda-hook.ps1'
if (!(Test-Path $CONDA_HOOK)) {
    New-Item $INSTALL_DIR -ItemType 'Directory' -ErrorAction SilentlyContinue > $null

    Invoke-RestMethod $MINICONDA_DOWNLOAD_URL -OutFile $(Join-Path $INSTALL_DIR "miniconda_installer$( if ($IsOnWindows) {'.exe'} else {'.sh'} )") -ErrorAction Stop

    if (!$IsOnWindows) {
        chmod u+x "$INSTALL_DIR/miniconda_installer.sh"
        bash "$INSTALL_DIR/miniconda_installer.sh" -b -p $CONDA_ROOT_PREFIX
    }
    else {Start-Process "$INSTALL_DIR\miniconda_installer.exe" -ArgumentList "/InstallationType=JustMe /NoShortcuts=1 /AddToPath=0 /RegisterPython=0 /NoRegistry=1 /S /D=$CONDA_ROOT_PREFIX".Split(' ') -Wait}

    if (!(Test-Path $CONDA_HOOK)) {Write-Error 'Miniconda failed to install.'; pause; Exit-PSSession}
}

. $CONDA_HOOK -ErrorAction Stop

While ($null -ne [Environment]::GetEnvironmentVariable('CONDA_PREFIX')) {conda deactivate}

if (!(Test-Path $INSTALL_ENV_DIR)) {
    conda create $(if ($IsOnWindows) {'--no-shortcuts'}) -y -k --prefix $INSTALL_ENV_DIR 'python=3.10'

    conda activate "$INSTALL_ENV_DIR"

    if ([Environment]::GetEnvironmentVariable('CONDA_PREFIX') -ne $INSTALL_ENV_DIR) {Write-Error 'Conda environment could not be activated! Is it empty?'}

    InstallDependencies
    UpdateDependencies
}
else {
    conda activate "$INSTALL_ENV_DIR"

    if ([Environment]::GetEnvironmentVariable('CONDA_PREFIX') -ne $INSTALL_ENV_DIR) {Write-Error 'Conda environment could not be activated! Is it empty?'}
}

do {
    Set-Location $PSScriptRoot

    if (Test-Path $(Join-Path $PSScriptRoot 'CMD_FLAGS.txt'))
    {
        $cmdChoice = "`n6 - Refresh CMD_FLAGS"
        $CMD_FLAGS = [regex]::Split((Get-Content $(Join-Path $PSScriptRoot 'CMD_FLAGS.txt')).where({$_ -ne ''}).trim(), ' +(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)')
    } elseif ($cmdChoice) {Clear-Variable cmdChoice}
    if ($cmdChoice) {$cmdFlags = "`nCMD_FLAGS = '{0}'" -f $($CMD_FLAGS -join ' ')} else {$cmdFlags = "{0}`n`nYou must restart the installer for changes to CMD_FLAGS to take effect!" -f $(Get-Content $PSCommandPath).where({$_ -match '^\$CMD_FLAGS'})[0].split('#')[0]}

    $operationChoice = Read-Host "$cmdFlags

1 - Lauch the Webui
2 - Update the WebUI
3 - Download AI model
4 - Open command-line in virtual environment
5 - Exit$cmdChoice

Choose the operation that you would like to perform"

    switch ($operationChoice)
    {
        '1' {Write-Output "`n`n"; Join-Path $INSTALL_DIR_ROOT 'text-generation-webui' | Set-Location -ErrorAction Stop; python 'server.py' $CMD_FLAGS.split(); break}
        '2' {UpdateDependencies; break}
        '3' {Clear-Host; Join-Path $INSTALL_DIR_ROOT 'text-generation-webui' | Set-Location -ErrorAction Stop; DownloadModel; break}
        '4' {Join-Path $INSTALL_DIR_ROOT 'text-generation-webui' | Set-Location -ErrorAction Stop; if ($PSEdition -eq 'Desktop') {powershell} else {pwsh}; break}
        '5' {Exit-PSSession}
        Default {Clear-Host}
    }
} until ($operationChoice -eq '5')
