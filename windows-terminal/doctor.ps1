param(
    [string]$AssetDirectory,
    [ValidateSet('wezterm','windows-terminal')][string]$Backend,
    [string]$Engine='unknown',
    [int]$Sessions=-1,
    [int]$Panes=-1,
    [switch]$OwnedPane
)
$version='unknown'
$versionPath=Join-Path $AssetDirectory 'VERSION'
try{
    $value=[IO.File]::ReadAllText($versionPath).Trim()
    if($value -match '^\d+\.\d+\.\d+$'){$version=$value}
}catch{}
"TMX: $version"
'OS: Windows'
"Backend: $Backend"
"PowerShell: $($PSVersionTable.PSVersion)"
"SSH: $(if($env:SSH_CONNECTION -or $env:SSH_TTY){'yes'}else{'no'})"
"Context: $(if($OwnedPane){'owned-pane'}else{'outside'})"
'Configured prefix: Ctrl+A (2 seconds)'
'Configured scrollback limit: 20000 lines'
if($Backend -eq 'wezterm'){
    if($Engine -match '^wezterm \d{8}-\d{6}-[a-f0-9]+$'){"Engine: $Engine"}else{'Engine: unknown'}
    $renderer='webgpu'
    try{
        $rendererFile=Join-Path ($AssetDirectory.TrimEnd('\','/')+'-state') 'renderer.json'
        if(Test-Path -LiteralPath $rendererFile){
            $value=([IO.File]::ReadAllText($rendererFile)|ConvertFrom-Json).name
            if($value -in 'webgpu','software','opengl'){$renderer=$value}
        }
    }catch{}
    "Configured renderer: $renderer"
    if($Sessions -ge 0){"Sessions: $Sessions"}
    if($Panes -ge 0){"Panes: $Panes"}
}
if($OwnedPane){
    try{
        $size=$Host.UI.RawUI.WindowSize
        "Pane grid: $($size.Width)x$($size.Height)"
    }catch{}
}
