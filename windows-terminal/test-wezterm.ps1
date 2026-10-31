param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$Fixture,[Parameter(Mandatory=$true)][string]$FakeTerminal)
$ErrorActionPreference='Stop'
$assets=Join-Path $Fixture 'WezTerm assets'
$desktop=Join-Path $Fixture 'WezTerm Desktop'
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup-wezterm.ps1')))
$restore=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore-wezterm.ps1')))
$manifest=Join-Path $assets 'install-state.json'
$commands=Join-Path $Fixture 'Commands'
foreach($theme in 'aurora','midnight','ember','paper','neon','black','code','hacker'){
    & $setup -SourceDirectory $SourceDirectory -Theme $theme -StartingDirectory $Fixture -AssetDirectory $assets -DesktopDirectory $desktop -CommandDirectory $commands -NoCommandPath -WezTermExecutable $FakeTerminal
    $backend=[IO.File]::ReadAllText((Join-Path $assets 'backend.json'))|ConvertFrom-Json
    if($backend.theme -ne $theme -or $backend.executable -ne $FakeTerminal){throw 'WezTerm backend differs'}
    $config=[IO.File]::ReadAllText((Join-Path $assets ('wezterm-'+$theme+'.lua')))
    if($config.Contains('__THEME__') -or -not $config.Contains('config.tab_bar_at_bottom = true')){throw 'WezTerm config was not generated'}
    $link=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Tmux Style WezTerm.lnk'))
    if($link.TargetPath -ne (Join-Path $commands 'tmx.exe') -or $link.Arguments -ne 'workspace TMUX' -or -not(Test-Path (Join-Path $commands 'tmx.exe'))){throw 'Persistent session shortcut/command differs'}
    $version=& (Join-Path $commands 'tmx.exe') version
    if($LASTEXITCODE -ne 0 -or $version.Trim() -ne ([IO.File]::ReadAllText((Join-Path $assets 'VERSION'))).Trim()){throw 'Installed command cannot run from PowerShell'}
    & $restore -StatePath $manifest
    if(Test-Path -LiteralPath (Join-Path $assets 'backend.json')){throw 'WezTerm restore left owned settings'}
}
# An upgrade can be rolled back to the prior installation; later edits are protected.
& $setup -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $Fixture -AssetDirectory $assets -CommandDirectory $commands -NoCommandPath -WezTermExecutable $FakeTerminal -NoShortcut
$oldHash=(Get-FileHash -LiteralPath (Join-Path $assets 'backend.json')).Hash
& $setup -SourceDirectory $SourceDirectory -Theme aurora -StartingDirectory $Fixture -AssetDirectory $assets -CommandDirectory $commands -NoCommandPath -WezTermExecutable $FakeTerminal -NoShortcut
$file=Join-Path $assets 'wezterm-black.lua'
$original=[IO.File]::ReadAllText($file)
[IO.File]::AppendAllText($file,"`n-- user edit")
$rejected=0
try{& $restore -StatePath $manifest}catch{if($_.Exception.Message -like 'WezTerm workspace changed*'){$rejected++}else{throw}}
try{& $setup -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $Fixture -AssetDirectory $assets -CommandDirectory $commands -NoCommandPath -WezTermExecutable $FakeTerminal -NoShortcut}catch{if($_.Exception.Message -like 'WezTerm workspace file changed*'){$rejected++}else{throw}}
if($rejected -ne 2 -or -not([IO.File]::ReadAllText($file).Contains('-- user edit'))){throw 'WezTerm edits were not protected'}
[IO.File]::WriteAllText($file,$original,[Text.UTF8Encoding]::new($false))
& $restore -StatePath $manifest
if((Get-FileHash -LiteralPath (Join-Path $assets 'backend.json')).Hash -ne $oldHash){throw 'WezTerm upgrade restore differs'}
& $restore -StatePath $manifest
$invalid=Join-Path $Fixture 'invalid-runtime.zip';[IO.File]::WriteAllText($invalid,'invalid')
$rejected=$false
try{& $setup -SourceDirectory $SourceDirectory -StartingDirectory $Fixture -AssetDirectory (Join-Path $Fixture 'Invalid runtime') -RuntimeArchive $invalid -NoShortcut}catch{if($_.Exception.Message -like '*checksum mismatch*'){$rejected=$true}else{throw}}
if(-not $rejected){throw 'Unverified WezTerm runtime accepted'}
$metrics=Join-Path $Fixture 'sample.json'
$proc=Start-Process -FilePath (Join-Path $SourceDirectory 'TmuxStyle.Metrics.exe') -ArgumentList ('--once "'+$metrics+'"') -Wait -PassThru -WindowStyle Hidden
if($proc.ExitCode -ne 0){throw 'Windows metric sampling failed'}
$sample=[IO.File]::ReadAllText($metrics)|ConvertFrom-Json
if($sample.cpu -lt 0 -or $sample.cpu -gt 100 -or $sample.ram -lt 0 -or $sample.ram -gt 100 -or $sample.totalGiB -le 0 -or $sample.usedGiB -gt $sample.totalGiB){throw 'Invalid Windows counter values'}
$savedEnv=@{}
foreach($key in 'TMUX_STYLE_BACKEND','TMUX_STYLE_ASSETS','TMUX_STYLE_GUI_PID','WEZTERM_PANE'){$savedEnv[$key]=[Environment]::GetEnvironmentVariable($key)}
try{
    $env:TMUX_STYLE_BACKEND='wezterm';$env:TMUX_STYLE_ASSETS=$assets;$env:TMUX_STYLE_GUI_PID='12345';$env:WEZTERM_PANE='7'
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'shell.ps1')))) -NoBanner -NoKeyBridge
    # There is no backend.json or terminal executable here. Theme must use OSC,
    # rather than trying to launch a new terminal or replace this shell.
    $signal=@(Set-TmuxStyleTheme black 6>&1)|Out-String
    if(-not $signal.Contains('SetUserVar=TmuxStyleTheme=YmxhY2s=') -or $global:TmuxStyleTheme -ne 'black'){throw 'Live theme signal/prompt differs'}
    $state=Get-TmuxStyleThemeStatePath
    if(-not $state.StartsWith($assets+'-state'+[IO.Path]::DirectorySeparatorChar)){throw 'Prompt writes inside watched config directory'}
    [IO.File]::WriteAllText($state,'{"theme":"paper"}')
    $global:LASTEXITCODE=37;$promptText=prompt
    if($global:TmuxStyleTheme -ne 'paper' -or $global:LASTEXITCODE -ne 37 -or $promptText -ne '  > '){throw 'Peer-pane prompt theme sync damaged shell state'}
    Import-Module PSReadLine
    foreach($paletteName in 'aurora','midnight','ember','paper','neon','black','code','hacker'){
        Update-TmuxStyleShellTheme $paletteName
        if((Get-PSReadLineOption).SelectionColor -ne ([string][char]27+'[0;7m')){throw 'Selection must reset and reverse the active terminal palette'}
    }
    Update-TmuxStyleShellTheme code
    $options=Get-PSReadLineOption
    if($options.CommandColor -eq $options.StringColor -or $options.KeywordColor -eq $options.VariableColor){throw 'Code Spectrum syntax roles are not distinct'}
    Update-TmuxStyleShellTheme hacker
    $options=Get-PSReadLineOption
    if($options.CommandColor -eq $options.CommentColor -or $options.ErrorColor -eq $options.CommandColor){throw 'Hacker syntax lacks readable comment/error contrast'}
    Update-TmuxStyleShellTheme black
    $options=Get-PSReadLineOption
    if($options.KeywordColor -ne $options.CommandColor -or $options.VariableColor -ne $options.TypeColor){throw 'Returning to Black retained a previous theme syntax role'}
}finally{
    foreach($key in $savedEnv.Keys){[Environment]::SetEnvironmentVariable($key,$savedEnv[$key])}
}
Write-Output 'PASS: WezTerm eight themes, isolated files, shortcuts, upgrade/restore, edit protection, runtime checksum rejection, live Windows counters.'
