param([Parameter(Mandatory=$true)][string]$AssetDirectory)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$repo='devoralabsapp/tmux-style'
$current=[IO.File]::ReadAllText((Join-Path $AssetDirectory 'VERSION')).Trim()
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$release=Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UserAgent 'TMX-Updater' -TimeoutSec 30
if($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v([0-9]{1,6}(?:\.[0-9]{1,6}){2})$'){
    throw 'GitHub did not return a stable TMX release.'
}
$latest=$Matches[1]
if([version]$latest -le [version]$current){"TMX $current is up to date.";return}

$file="TMX-Setup-$latest.exe"
$base="https://github.com/$repo/releases/download/v$latest"
$stage=Join-Path ([IO.Path]::GetTempPath()) ('tmx-update-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage|Out-Null
try{
    "Updating TMX $current to $latest..."
    $checksum=Join-Path $stage 'SHA256SUMS.txt'
    Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS.txt" -OutFile $checksum -TimeoutSec 30
    $pattern='^([0-9a-fA-F]{64})\s+'+[regex]::Escape($file)+'$'
    $matchesForFile=@(Select-String -LiteralPath $checksum -Pattern $pattern -CaseSensitive)
    if($matchesForFile.Count -ne 1){throw 'The TMX release checksum for Windows is missing or invalid.'}
    $expected=$matchesForFile[0].Matches[0].Groups[1].Value
    $installer=Join-Path $stage $file
    Invoke-WebRequest -UseBasicParsing -Uri "$base/$file" -OutFile $installer -TimeoutSec 120
    if((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ine $expected){
        throw 'TMX download checksum mismatch. Installation files were not changed.'
    }
    $log=Join-Path $stage 'update.log'
    $binaryVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($installer).FileVersion
    if($binaryVersion -cne ($latest+'.0')){throw 'The downloaded installer has a different version.'}
    $process=Start-Process -FilePath $installer -ArgumentList ('--update "'+$AssetDirectory.TrimEnd('\','/')+'" '+$current+' "'+$log+'"') -PassThru -WindowStyle Hidden
    $process.WaitForExit()
    if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Encoding UTF8}
    if($process.ExitCode -ne 0){throw ('TMX installer failed with exit code '+$process.ExitCode+'.')}
    if([IO.File]::ReadAllText((Join-Path $AssetDirectory 'VERSION')).Trim() -cne $latest){throw 'The installed version does not match the GitHub release.'}
    "Updated to TMX $latest. Existing sessions continue running."
}finally{
    foreach($name in 'SHA256SUMS.txt',$file,'update.log'){
        Remove-Item -LiteralPath (Join-Path $stage $name) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
}
