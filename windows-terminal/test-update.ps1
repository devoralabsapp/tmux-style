param([string]$SourceDirectory,[string]$Fixture,[string]$FakeTerminal,[string]$InstallerPath)
$ErrorActionPreference='Stop'
$old=Join-Path $Fixture 'Previous TMX package'
$assets=Join-Path $Fixture 'TMX update assets'
$commands=Join-Path $Fixture 'TMX update commands'
$desktop=Join-Path $Fixture 'TMX update desktop'
New-Item -ItemType Directory -Path $old|Out-Null
Get-ChildItem -LiteralPath $SourceDirectory -File|Copy-Item -Destination $old
[IO.File]::WriteAllText((Join-Path $old 'VERSION'),'0.0.1')
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $old 'setup-wezterm.ps1')))
& $setup -SourceDirectory $old -AssetDirectory $assets -StartingDirectory $Fixture -WezTermExecutable $FakeTerminal -CommandDirectory $commands -DesktopDirectory $desktop -Theme prism -NoCommandPath
$command=Join-Path $commands 'tmx.exe'
$version=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'VERSION')).Trim()
$assetName="TMX-Setup-$version.exe"
$digest=(Get-FileHash -LiteralPath $InstallerPath).Hash
$releaseTag='v0.0.1'
$corrupt=$true
$savedDefault=Join-Path ($assets+'-state') 'default-theme.json'
[IO.File]::WriteAllText($savedDefault,'{"theme":"hacker"}')
$kept=@($command,(Join-Path $commands 'tmx-location.txt'),(Join-Path $assets 'backend.json'),(Join-Path $desktop 'Tmux Style WezTerm.lnk'),$savedDefault)
$hashes=@(foreach($path in $kept){(Get-FileHash -LiteralPath $path).Hash})
function Invoke-RestMethod($Uri,$UserAgent,$TimeoutSec){
    if($Uri -cne 'https://api.github.com/repos/devoralabsapp/tmux-style/releases/latest'){throw "Unexpected API URL: $Uri"}
    [pscustomobject]@{tag_name=$releaseTag;prerelease=$false;draft=$false}
}
function Invoke-WebRequest([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec){
    $base="https://github.com/devoralabsapp/tmux-style/releases/download/v$version"
    if($Uri -ceq "$base/SHA256SUMS.txt"){[IO.File]::WriteAllText($OutFile,"$digest  $assetName");return}
    if($Uri -cne "$base/$assetName"){throw "Unexpected asset URL: $Uri"}
    if($corrupt){[IO.File]::WriteAllText($OutFile,'corrupt')}else{Copy-Item -LiteralPath $InstallerPath -Destination $OutFile}
}
$cli=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $assets 'tmx.ps1')))
if((& $cli -AssetDirectory $assets -Arguments @('update')) -notmatch '0\.0\.1 is up to date'){throw 'Same release was downloaded'}
$releaseTag='v'+$version
$rejected=$false
try{& $cli -AssetDirectory $assets -Arguments @('update')}catch{
    if($_.Exception.Message -notlike '*checksum mismatch*'){throw}
    $rejected=$true
}
if(-not $rejected -or (& $command version) -ne '0.0.1'){throw 'Unverified download changed the installed version'}
$corrupt=$false
# Deny overwriting the shim, as Windows does while tmx.exe is running.
$runningCommand=[IO.File]::OpenRead($command)
try{& $cli -AssetDirectory $assets -Arguments @('update')}finally{$runningCommand.Dispose()}
if((& $command version) -ne $version -or (& $cli -AssetDirectory $assets -Arguments @('update')) -notmatch 'is up to date'){throw 'The verified EXE did not upgrade the command'}
$after=@(foreach($path in $kept){(Get-FileHash -LiteralPath $path).Hash})
if(($after -join ',') -ne ($hashes -join ',')){throw 'Update changed the launcher or user preferences'}
$restore=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $assets 'restore-wezterm.ps1')))
& $restore -StatePath (Join-Path $assets 'install-state.json')
if((& $command version) -ne '0.0.1'){throw 'Could not restore the installation before tmx update'}
