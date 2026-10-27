param([string]$StatePath=(Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\install-state.json'))
$ErrorActionPreference='Stop'
$state=Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
$commonPath=Join-Path (Split-Path -Parent $StatePath) 'common.ps1'
if(Test-Path $commonPath){. ([scriptblock]::Create([IO.File]::ReadAllText($commonPath)))}
function File-Hash([string]$Path) {
    if(Test-Path -LiteralPath $Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    return 'MISSING'
}
if((File-Hash $state.settingsPath) -ne $state.installedHash){
    if(-not $state.expectedSettings -or -not(Test-Path $state.expectedSettings) -or -not(Test-TmuxStyleNormalization (Read-TmuxStyleJson $state.expectedSettings) (Read-TmuxStyleJson $state.settingsPath))){
        throw 'Terminal settings changed since installation. Compare the backup before restoring, to preserve newer changes.'
    }
}
if($state.settingsBackup){
    Copy-Item -LiteralPath $state.settingsBackup -Destination $state.settingsPath -Force
} else {
    # It did not exist before installation. Only remove this exact owned file.
    Remove-Item -LiteralPath $state.settingsPath
}
if($state.shortcutPath -and (File-Hash $state.shortcutPath) -eq $state.shortcutHash){
    if($state.shortcutBackup){Copy-Item -LiteralPath $state.shortcutBackup -Destination $state.shortcutPath -Force}
    else {Remove-Item -LiteralPath $state.shortcutPath}
}
$bridge=Join-Path (Split-Path -Parent $StatePath) 'TmuxStyle.Keys.exe'
if(Test-Path -LiteralPath $bridge){& $bridge --stop;Start-Sleep -Milliseconds 500}
foreach($asset in @($state.assetBackups)){
    if($null -eq $asset){continue}
    if($asset.backup){Copy-Item -LiteralPath $asset.backup -Destination $asset.path -Force}
    elseif(Test-Path -LiteralPath $asset.path){Remove-Item -LiteralPath $asset.path}
}
Write-Output 'Previous Terminal settings restored. Open a new window to use them.'
