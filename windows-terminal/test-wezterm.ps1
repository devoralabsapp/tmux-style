param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$Fixture,[Parameter(Mandatory=$true)][string]$FakeTerminal)
$ErrorActionPreference='Stop'
$assets=Join-Path $Fixture 'WezTerm assets'
$desktop=Join-Path $Fixture 'WezTerm Desktop'
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup-wezterm.ps1')))
$restore=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore-wezterm.ps1')))
$manifest=Join-Path $assets 'install-state.json'
foreach($theme in 'aurora','midnight','ember','paper','neon','black'){
    & $setup -SourceDirectory $SourceDirectory -Theme $theme -StartingDirectory $Fixture -AssetDirectory $assets -DesktopDirectory $desktop -WezTermExecutable $FakeTerminal
    $backend=[IO.File]::ReadAllText((Join-Path $assets 'backend.json'))|ConvertFrom-Json
    if($backend.theme -ne $theme -or $backend.executable -ne $FakeTerminal){throw 'WezTerm backend differs'}
    $config=[IO.File]::ReadAllText((Join-Path $assets ('wezterm-'+$theme+'.lua')))
    if($config.Contains('__THEME__') -or -not $config.Contains('config.tab_bar_at_bottom = true')){throw 'WezTerm config was not generated'}
    $link=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Tmux Style WezTerm.lnk'))
    if($link.TargetPath -ne $FakeTerminal -or -not $link.Arguments.Contains('wezterm-'+$theme+'.lua')){throw 'WezTerm shortcut differs'}
    & $restore -StatePath $manifest
    if(Test-Path -LiteralPath (Join-Path $assets 'backend.json')){throw 'WezTerm restore left owned settings'}
}
# An upgrade can be rolled back to the prior installation; later edits are protected.
& $setup -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $Fixture -AssetDirectory $assets -WezTermExecutable $FakeTerminal -NoShortcut
$oldHash=(Get-FileHash -LiteralPath (Join-Path $assets 'backend.json')).Hash
& $setup -SourceDirectory $SourceDirectory -Theme aurora -StartingDirectory $Fixture -AssetDirectory $assets -WezTermExecutable $FakeTerminal -NoShortcut
$file=Join-Path $assets 'wezterm-black.lua'
$original=[IO.File]::ReadAllText($file)
[IO.File]::AppendAllText($file,"`n-- user edit")
$rejected=0
try{& $restore -StatePath $manifest}catch{if($_.Exception.Message -like 'WezTerm workspace changed*'){$rejected++}else{throw}}
try{& $setup -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $Fixture -AssetDirectory $assets -WezTermExecutable $FakeTerminal -NoShortcut}catch{if($_.Exception.Message -like 'WezTerm workspace file changed*'){$rejected++}else{throw}}
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
Write-Output 'PASS: WezTerm six themes, isolated files, shortcuts, upgrade/restore, edit protection, runtime checksum rejection, live Windows counters.'
