param([string]$StatePath=(Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\wezterm\install-state.json'))
$ErrorActionPreference='Stop'
$state=[IO.File]::ReadAllText($StatePath)|ConvertFrom-Json
foreach($entry in $state.files){
    $hash=if(Test-Path -LiteralPath $entry.path){(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash}else{'MISSING'}
    if($hash -ne $entry.installedHash){throw ('WezTerm workspace changed since installation. Compare the backup before restoring: '+$entry.path)}
}
$root=Split-Path -Parent $StatePath
$cli=Join-Path $root 'tmx.ps1'
if(Test-Path -LiteralPath $cli){& ([scriptblock]::Create([IO.File]::ReadAllText($cli))) -AssetDirectory $root -Arguments @('__check-no-sessions')}
$metrics=Join-Path $root 'TmuxStyle.Metrics.exe'
if(Test-Path -LiteralPath $metrics){
    foreach($directory in $root,($root.TrimEnd('\','/')+'-state')){
        Start-Process -FilePath $metrics -ArgumentList ('--stop "'+(Join-Path $directory 'metrics.json')+'"') -Wait -WindowStyle Hidden
    }
    foreach($process in @(Get-Process -Name TmuxStyle.Metrics -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $metrics})){
        if(-not $process.WaitForExit(5000)){throw 'Close Tmux Style WezTerm windows before restoring.'}
    }
}
$recovery=Join-Path $root ('backups\before-restore-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $recovery|Out-Null
$moved=@();$index=0
try{
    foreach($entry in $state.files){
        $target=Join-Path $recovery ($index.ToString()+'-'+[IO.Path]::GetFileName($entry.path))
        Move-Item -LiteralPath $entry.path -Destination $target
        $moved+=@{from=$entry.path;to=$target};$index++
    }
    foreach($entry in $state.files){if($entry.backup){Copy-Item -LiteralPath $entry.backup -Destination $entry.path}}
}catch{
    foreach($entry in $moved){Copy-Item -LiteralPath $entry.to -Destination $entry.from -Force}
    throw
}
if($state.previousState){Copy-Item -LiteralPath $state.previousState -Destination $StatePath -Force}
else{Remove-Item -LiteralPath $StatePath}
if($state.addedCommandPath){
    $userPath=[string][Environment]::GetEnvironmentVariable('PATH','User')
    [Environment]::SetEnvironmentVariable('PATH',((@($userPath.Split(';')|Where-Object {$_.TrimEnd('\','/') -ine $state.commandDirectory.TrimEnd('\','/')})) -join ';'),'User')
}
Write-Output 'Previous WezTerm workspace files restored. Windows Terminal settings were untouched.'
