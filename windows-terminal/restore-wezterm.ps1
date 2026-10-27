param([string]$StatePath=(Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\wezterm\install-state.json'))
$ErrorActionPreference='Stop'
$state=[IO.File]::ReadAllText($StatePath)|ConvertFrom-Json
foreach($entry in $state.files){
    $hash=if(Test-Path -LiteralPath $entry.path){(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash}else{'MISSING'}
    if($hash -ne $entry.installedHash){throw ('WezTerm workspace changed since installation. Compare the backup before restoring: '+$entry.path)}
}
$root=Split-Path -Parent $StatePath
$metrics=Join-Path $root 'TmuxStyle.Metrics.exe'
if(Test-Path -LiteralPath $metrics){
    Start-Process -FilePath $metrics -ArgumentList ('--stop "'+(Join-Path $root 'metrics.json')+'"') -Wait -WindowStyle Hidden
    foreach($process in @(Get-Process -Name TmuxStyle.Metrics -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $metrics})){
        if(-not $process.WaitForExit(5000)){throw 'Close Tmux Style WezTerm windows before restoring.'}
    }
}
foreach($entry in $state.files){
    if($entry.backup){Copy-Item -LiteralPath $entry.backup -Destination $entry.path -Force}
    else{Remove-Item -LiteralPath $entry.path}
}
if($state.previousState){Copy-Item -LiteralPath $state.previousState -Destination $StatePath -Force}
else{Remove-Item -LiteralPath $StatePath}
Write-Output 'Previous WezTerm workspace files restored. Windows Terminal settings were untouched.'
