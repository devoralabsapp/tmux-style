param(
    [string]$SourceDirectory=$PSScriptRoot,
    [ValidateSet('aurora','midnight','ember','paper','neon','black')][string]$Theme='aurora',
    [string]$StartingDirectory=$HOME,
    [string]$AssetDirectory=(Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\wezterm'),
    [string]$DesktopDirectory=[Environment]::GetFolderPath('DesktopDirectory'),
    [string]$WezTermExecutable,[string]$RuntimeArchive,
    [switch]$InstallTerminal,[switch]$NoShortcut,[switch]$Launch
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if(-not $SourceDirectory){throw 'Provide SourceDirectory when running as a script block.'}
if(-not(Test-Path -LiteralPath $StartingDirectory -PathType Container)){throw 'Starting directory does not exist.'}
$AssetDirectory=[IO.Path]::GetFullPath($AssetDirectory)
$statePath=Join-Path $AssetDirectory 'install-state.json'
function File-Hash([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash};return 'MISSING'}
if(Test-Path -LiteralPath $statePath){
    $previous=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
    foreach($entry in $previous.files){
        if((File-Hash $entry.path) -ne $entry.installedHash){throw ('WezTerm workspace file changed since installation. Back up your changes before upgrading: '+$entry.path)}
    }
}
New-Item -ItemType Directory -Path $AssetDirectory -Force|Out-Null
$pin=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'wezterm-runtime.json'))|ConvertFrom-Json
if(-not $WezTermExecutable){
    # Reuse an explicitly installed copy if available; otherwise install portable
    # WezTerm in this workspace only. Never change .wezterm.lua or default apps.
    if(Test-Path -LiteralPath (Join-Path $AssetDirectory 'backend.json')){
        $oldBackend=[IO.File]::ReadAllText((Join-Path $AssetDirectory 'backend.json'))|ConvertFrom-Json
        if(Test-Path -LiteralPath $oldBackend.executable){$WezTermExecutable=$oldBackend.executable}
    }
    if(-not $WezTermExecutable){$command=Get-Command wezterm.exe -ErrorAction SilentlyContinue;if($command){$WezTermExecutable=$command.Source}}
    if(-not $WezTermExecutable){
        $runtime=Join-Path $AssetDirectory ('runtime\'+$pin.version)
        $WezTermExecutable=Join-Path $runtime ($pin.folder+'\wezterm.exe')
        if(-not(Test-Path -LiteralPath $WezTermExecutable)){
            if(-not $InstallTerminal -and -not $RuntimeArchive){throw 'WezTerm is missing. Enable the official terminal download option.'}
            $archive=$RuntimeArchive
            if(-not $archive){
                $archive=Join-Path $AssetDirectory ($pin.folder+'.zip')
                Write-Output 'Downloading the official portable WezTerm package (SHA-256 checked)...'
                [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -UseBasicParsing -Uri $pin.url -OutFile $archive -TimeoutSec 180
            }
            if((File-Hash $archive) -ne $pin.sha256){throw 'WezTerm download checksum mismatch. Installation stopped.'}
            New-Item -ItemType Directory -Path $runtime -Force|Out-Null
            Expand-Archive -LiteralPath $archive -DestinationPath $runtime -Force
        }
    }
}
if(-not(Test-Path -LiteralPath $WezTermExecutable -PathType Leaf)){throw 'WezTerm executable was not found.'}
$WezTermExecutable=[IO.Path]::GetFullPath($WezTermExecutable)
$backup=Join-Path $AssetDirectory ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$files=New-Object Collections.Generic.List[object]
function Save-OwnedFile([string]$Path){
    $saved=$null
    if(Test-Path -LiteralPath $Path){$saved=Join-Path $backup ($files.Count.ToString()+'-'+[IO.Path]::GetFileName($Path));Copy-Item -LiteralPath $Path -Destination $saved}
    $files.Add([pscustomobject]@{path=$Path;backup=$saved;installedHash=$null})
}
$metrics=Join-Path $AssetDirectory 'TmuxStyle.Metrics.exe'
if(Test-Path -LiteralPath $metrics){
    $stop=Start-Process -FilePath $metrics -ArgumentList ('--stop "'+(Join-Path $AssetDirectory 'metrics.json')+'"') -PassThru -Wait -WindowStyle Hidden
    # Wait only for a collector from this exact installation, not another workspace.
    $owned=@(Get-Process -Name TmuxStyle.Metrics -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $metrics})
    foreach($process in $owned){if(-not $process.WaitForExit(5000)){throw 'Close Tmux Style WezTerm windows before upgrading.'}}
}
try{
    foreach($name in 'shell.ps1','restore-wezterm.ps1','TmuxStyle.Metrics.exe','tmux-style.ico','wezterm-palettes.json','wezterm-runtime.json','WEZTERM_LICENSE.md'){
        $target=Join-Path $AssetDirectory $name;Save-OwnedFile $target
        Copy-Item -LiteralPath (Join-Path $SourceDirectory $name) -Destination $target -Force
    }
    $template=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'wezterm.lua'))
    foreach($slug in 'aurora','midnight','ember','paper','neon','black'){
        $target=Join-Path $AssetDirectory ('wezterm-'+$slug+'.lua');Save-OwnedFile $target
        [IO.File]::WriteAllText($target,$template.Replace('__THEME__',$slug),[Text.UTF8Encoding]::new($false))
    }
    $target=Join-Path $AssetDirectory 'backend.json';Save-OwnedFile $target
    $backend=[pscustomobject]@{executable=$WezTermExecutable;startingDirectory=[IO.Path]::GetFullPath($StartingDirectory);theme=$Theme}
    [IO.File]::WriteAllText($target,($backend|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $config=Join-Path $AssetDirectory ('wezterm-'+$Theme+'.lua')
    if(-not $NoShortcut){
        New-Item -ItemType Directory -Path $DesktopDirectory -Force|Out-Null
        $target=Join-Path $DesktopDirectory 'Tmux Style WezTerm.lnk';Save-OwnedFile $target
        $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut($target)
        # wezterm-gui avoids a console flash; the CLI accepts the same arguments.
        $gui=Join-Path (Split-Path -Parent $WezTermExecutable) 'wezterm-gui.exe'
        $shortcut.TargetPath=if(Test-Path -LiteralPath $gui){$gui}else{$WezTermExecutable}
        $shortcut.Arguments='--config-file "'+$config+'" start --always-new-process --cwd "'+$StartingDirectory+'"'
        $shortcut.WorkingDirectory=$StartingDirectory;$shortcut.IconLocation=(Join-Path $AssetDirectory 'tmux-style.ico')+',0';$shortcut.Save()
    }
    foreach($entry in $files){$entry.installedHash=File-Hash $entry.path}
    $priorState=$null
    if(Test-Path -LiteralPath $statePath){$priorState=Join-Path $backup 'previous-state.json';Copy-Item -LiteralPath $statePath -Destination $priorState}
    $state=[pscustomobject]@{backend='wezterm';files=@($files.ToArray());previousState=$priorState;backup=$backup}
    [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}catch{
    foreach($entry in $files){if($entry.backup){Copy-Item -LiteralPath $entry.backup -Destination $entry.path -Force}elseif(Test-Path -LiteralPath $entry.path){Remove-Item -LiteralPath $entry.path}}
    throw
}
Write-Output ('Installed WezTerm workspace: '+$config)
Write-Output ('Backups: '+$backup)
Write-Output 'Native bottom bar: tabs, local Windows CPU/RAM, hostname, date/time. F12 toggles pass-through.'
if($Launch){
    try{
        Start-Process -FilePath $WezTermExecutable -ArgumentList ('--config-file "'+$config+'" start --always-new-process --cwd "'+$StartingDirectory+'"') -WindowStyle Hidden|Out-Null
    }catch{Write-Output ('Configuration installed successfully. Workspace launch failed: '+$_.Exception.Message)}
}
