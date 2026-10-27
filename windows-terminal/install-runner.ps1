param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [ValidateSet('windows-terminal','wezterm')][string]$Backend='windows-terminal',
    [ValidateSet('aurora','midnight','ember','paper','neon','black','code','hacker')][string]$Theme='aurora',
    [string]$StartingDirectory=$HOME,
    [string]$SettingsPath=(Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    [string]$AssetDirectory=(Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows'),
    [string]$DesktopDirectory=[Environment]::GetFolderPath('DesktopDirectory'),
    [string]$TerminalExecutable,
    [switch]$NoShortcut,[switch]$Launch,[switch]$InstallTerminal
)
$ErrorActionPreference='Stop'
if($Backend -eq 'wezterm'){
    & ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup-wezterm.ps1')))) -SourceDirectory $SourceDirectory -Theme $Theme -StartingDirectory $StartingDirectory -AssetDirectory (Join-Path $AssetDirectory 'wezterm') -DesktopDirectory $DesktopDirectory -WezTermExecutable $TerminalExecutable -NoShortcut:$NoShortcut -Launch:$Launch -InstallTerminal:$InstallTerminal
    return
}
if(-not(Test-Path -LiteralPath $StartingDirectory -PathType Container)){throw 'Starting directory does not exist.'}
$terminalExe=$TerminalExecutable
if(-not $terminalExe){$terminalCommand=Get-Command wt.exe -ErrorAction SilentlyContinue;if($terminalCommand){$terminalExe=$terminalCommand.Source}}
if(-not $terminalExe){
    if(-not $InstallTerminal){throw 'Install Windows Terminal first, or enable the Microsoft Terminal download option.'}
    $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
    if(-not $winget){throw 'App Installer (winget) is missing. Install Windows Terminal from Microsoft Store, then run this installer again.'}
    Write-Output 'Installing the official Microsoft Windows Terminal package...'
    & $winget.Source install --id Microsoft.WindowsTerminal --exact --source winget --scope user --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
    if($LASTEXITCODE -ne 0){throw ('Windows Terminal installation failed: '+$LASTEXITCODE)}
    $terminalExe=(Get-Command wt.exe -ErrorAction Stop).Source
}
if(-not(Test-Path -LiteralPath $terminalExe -PathType Leaf)){throw 'Windows Terminal executable was not found.'}
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup.ps1')))
& $setup -SourceDirectory $SourceDirectory -DefaultTheme $Theme -DefaultDirectory $StartingDirectory -SettingsPath $SettingsPath -AssetDirectory $AssetDirectory -DesktopDirectory $DesktopDirectory -TerminalExecutable $terminalExe -NoShortcut:$NoShortcut
& $setup -SourceDirectory $SourceDirectory -Apply
Write-Output 'Installed eight themes and tmux-style key mappings. F12 toggles pass-through.'
if($Launch){
    $names=@{aurora='Aurora';midnight='Midnight';ember='Ember';paper='Paper';neon='Neon';black='Command Line'; code='Code Spectrum'; hacker='Hacker Matrix'}
    $profile='Tmux Style - '+$names[$Theme]
    try{
        & $terminalExe -w new new-tab -p $profile -d $StartingDirectory ';' split-pane -V -s 0.35 -p $profile -d $StartingDirectory ';' split-pane -H -s 0.5 -p $profile -d $StartingDirectory ';' move-focus first
        if($LASTEXITCODE -ne 0){throw ('Terminal returned exit code '+$LASTEXITCODE)}
    }catch{
        Write-Output ('Configuration installed successfully. Workspace launch failed: '+$_.Exception.Message)
        Write-Output 'Open Tmux Style Workspace on Desktop, or start a Tmux Style profile in Terminal.'
    }
}
