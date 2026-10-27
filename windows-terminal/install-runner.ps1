param(
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [ValidateSet('aurora','midnight','ember','paper','neon')][string]$Theme='aurora',
    [string]$StartingDirectory=$HOME,
    [switch]$NoShortcut,[switch]$Launch,[switch]$InstallTerminal
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $StartingDirectory -PathType Container)){throw 'Starting directory does not exist.'}
$terminal=Get-Command wt.exe -ErrorAction SilentlyContinue
if(-not $terminal){
    if(-not $InstallTerminal){throw 'Install Windows Terminal first, or enable the Microsoft Terminal download option.'}
    $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
    if(-not $winget){throw 'App Installer (winget) is missing. Install Windows Terminal from Microsoft Store, then run this installer again.'}
    Write-Output 'Installing the official Microsoft Windows Terminal package...'
    & $winget.Source install --id Microsoft.WindowsTerminal --exact --source winget --scope user --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
    if($LASTEXITCODE -ne 0){throw ('Windows Terminal installation failed: '+$LASTEXITCODE)}
    $terminal=Get-Command wt.exe -ErrorAction Stop
}
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup.ps1')))
. $setup -SourceDirectory $SourceDirectory -DefaultTheme $Theme -DefaultDirectory $StartingDirectory -NoShortcut:$NoShortcut
. $setup -SourceDirectory $SourceDirectory -Apply
Write-Output 'Installed five themes and tmux-style key mappings. F12 toggles pass-through.'
if($Launch){
    $names=@{aurora='Aurora';midnight='Midnight';ember='Ember';paper='Paper';neon='Neon'}
    $profile='Tmux Style - '+$names[$Theme]
    & $terminal.Source -w new new-tab -p $profile -d $StartingDirectory ';' split-pane -V -s 0.35 -p $profile -d $StartingDirectory ';' split-pane -H -s 0.5 -p $profile -d $StartingDirectory ';' move-focus first
}
