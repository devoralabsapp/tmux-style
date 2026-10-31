param(
    [string]$AssetDirectory=$PSScriptRoot,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($AssetDirectory)
$state=$root.TrimEnd('\','/')+'-state'
$backend=[IO.File]::ReadAllText((Join-Path $root 'backend.json'))|ConvertFrom-Json
$names=@('aurora','midnight','ember','paper','neon','black','code','hacker')
$defaultPath=Join-Path $state 'default-theme.json'
if(Test-Path -LiteralPath $defaultPath){$savedDefault=[IO.File]::ReadAllText($defaultPath)|ConvertFrom-Json;if($names -contains $savedDefault.theme){$backend.theme=$savedDefault.theme}}
function Session-Key([string]$Name){
    if($Name -cnotmatch '^[a-zA-Z0-9_-]{1,32}$'){throw 'Use a session name of 1-32 letters, numbers, underscores or hyphens.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Name))).Replace('-','').Substring(0,16).ToLowerInvariant())}finally{$sha.Dispose()}
}
function Session-Path([string]$Name){Join-Path $state ('session-'+(Session-Key $Name)+'.json')}
function Invoke-Mux([string]$Name,[string[]]$Command,[switch]$AllowFailure){
    $old=@{}
    foreach($key in 'TMX_SESSION','TMX_SESSION_KEY','WEZTERM_UNIX_SOCKET','WEZTERM_PANE'){$old[$key]=[Environment]::GetEnvironmentVariable($key)}
    try{
        $env:TMX_SESSION=$Name;$env:TMX_SESSION_KEY=Session-Key $Name
        $env:WEZTERM_UNIX_SOCKET=Join-Path $state ('mux-'+$env:TMX_SESSION_KEY+'.sock')
        Remove-Item Env:WEZTERM_PANE -ErrorAction SilentlyContinue
        # Windows PowerShell turns native stderr into ErrorRecords. A missing
        # socket is expected while probing an absent session, not a script error.
        $ErrorActionPreference='Continue'
        $output=@(& $backend.executable --config-file (Join-Path $root ('wezterm-'+$backend.theme+'.lua')) cli --no-auto-start @Command 2>&1)
        $result=$LASTEXITCODE
        $ErrorActionPreference='Stop'
        if($result -ne 0){if($AllowFailure){return};throw ('TMX could not reach session '+$Name+': '+($output -join ' '))}
        return ($output -join "`n")
    }finally{foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key])}}
}
function Session-Panes([string]$Name){
    $json=Invoke-Mux $Name @('list','--format','json') -AllowFailure
    # Windows PowerShell 5.1 returns a JSON array as one pipeline object;
    # explicitly enumerate it so [] is empty and pane counts are accurate.
    if($json){foreach($item in (ConvertFrom-Json -InputObject $json)){$item}}
}
function Start-SessionProcess([string]$Name,[string]$Executable,[string]$ProcessArguments,[switch]$ShowWindow){
    $oldName=$env:TMX_SESSION;$oldKey=$env:TMX_SESSION_KEY;$oldCwd=$env:TMX_CWD
    try{
        $env:TMX_SESSION=$Name;$env:TMX_SESSION_KEY=Session-Key $Name
        $env:TMX_CWD=$PWD.ProviderPath
        $style=if($ShowWindow){'Normal'}else{'Hidden'}
        if($ShowWindow){
            $log=Join-Path $state ('gui-'+[Guid]::NewGuid().ToString('N')+'.log')
            Start-Process -FilePath $Executable -ArgumentList $ProcessArguments -WindowStyle $style -RedirectStandardError $log|Out-Null
        }else{Start-Process -FilePath $Executable -ArgumentList $ProcessArguments -WindowStyle $style|Out-Null}
    }finally{$env:TMX_SESSION=$oldName;$env:TMX_SESSION_KEY=$oldKey;$env:TMX_CWD=$oldCwd}
}
function Attach-Session([string]$Name){
    if(-not @(Session-Panes $Name).Count){throw ('Session not found: '+$Name+'. Run tmx list or tmx new '+$Name+'.')}
    $gui=Join-Path (Split-Path -Parent $backend.executable) 'wezterm-gui.exe'
    if(-not(Test-Path -LiteralPath $gui)){$gui=$backend.executable}
    Start-SessionProcess $Name $gui ('--config-file "'+(Join-Path $root ('wezterm-'+$backend.theme+'.lua'))+'" connect --class TMX-'+(Session-Key $Name)+' --workspace '+$Name+' TMX') -ShowWindow
    [IO.File]::WriteAllText((Join-Path $state 'last-attached.json'),(@{name=$Name}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
function Assert-NoSessions {
    foreach($file in Get-ChildItem -LiteralPath $state -Filter 'session-*.json' -ErrorAction SilentlyContinue){
        $saved=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json
        if(@(Session-Panes $saved.name).Count){throw 'Exit every TMX session first. Detaching leaves its processes running. No installation files changed.'}
    }
}
function Assert-OwnedPath([string]$Path,[string]$Commands){
    $full=[IO.Path]::GetFullPath($Path)
    $parent=Split-Path -Parent $full;$leaf=Split-Path -Leaf $full
    $assetNames=@('shell.ps1','tmx.ps1','VERSION','restore-wezterm.ps1','TmuxStyle.Metrics.exe','tmux-style.ico','wezterm-palettes.json','wezterm-runtime.json','WEZTERM_LICENSE.md','backend.json')
    $allowed=($parent -ieq $root -and ($assetNames -contains $leaf -or $leaf -match '^wezterm-(aurora|midnight|ember|paper|neon|black|code|hacker)\.lua$')) -or
        ($Commands -and $parent -ieq [IO.Path]::GetFullPath($Commands) -and $leaf -in 'tmx.exe','tmx-location.txt') -or $leaf -eq 'Tmux Style WezTerm.lnk'
    if(-not $allowed -or ((Get-Item -LiteralPath $full -ErrorAction SilentlyContinue).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw ('Invalid owned installation path: '+$full)}
}
function Remove-Installation {
    Assert-NoSessions
    $manifest=Join-Path $root 'install-state.json'
    $current=[IO.File]::ReadAllText($manifest)|ConvertFrom-Json
    foreach($entry in $current.files){
        Assert-OwnedPath $entry.path $current.commandDirectory
        if(-not(Test-Path -LiteralPath $entry.path) -or (Get-FileHash -LiteralPath $entry.path).Hash -ne $entry.installedHash){throw ('An installed file was edited: '+$entry.path+'. No installation files changed.')}
    }
    $original=@{};$pathEntries=@();$cursor=$current;$seen=@{}
    for($i=0;$i -lt 100;$i++){
        foreach($entry in $cursor.files){
            Assert-OwnedPath $entry.path $current.commandDirectory
            if($entry.backup -and -not([IO.Path]::GetFullPath($entry.backup).StartsWith(($root+'\backups\'),[StringComparison]::OrdinalIgnoreCase))){throw 'Invalid backup file path. No installation files changed.'}
            if(@($current.files|Where-Object {$_.path -ieq $entry.path}).Count){$original[$entry.path]=$entry.backup}
        }
        if($cursor.addedCommandPath){$pathEntries+= $cursor.commandDirectory}
        if(-not $cursor.previousState){break}
        $next=[IO.Path]::GetFullPath($cursor.previousState)
        if(-not $next.StartsWith(($root+'\backups\'),[StringComparison]::OrdinalIgnoreCase) -or $seen[$next]){throw 'Invalid backup history. No installation files changed.'}
        $seen[$next]=$true
        $cursor=[IO.File]::ReadAllText($next)|ConvertFrom-Json
    }
    if($i -eq 100){throw 'Backup history is too deep. No installation files changed.'}
    foreach($source in $original.Values){if($source -and -not(Test-Path -LiteralPath $source -PathType Leaf)){throw 'An original backup is missing. No installation files changed.'}}
    $recovery=Join-Path $root ('backups\uninstall-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $recovery|Out-Null
    $index=0;$moved=@()
    try{
        foreach($entry in $current.files){
            $target=Join-Path $recovery ($index.ToString()+'-'+[IO.Path]::GetFileName($entry.path))
            Move-Item -LiteralPath $entry.path -Destination $target
            $moved+=@{from=$entry.path;to=$target};$index++
        }
    }catch{
        foreach($entry in $moved){Move-Item -LiteralPath $entry.to -Destination $entry.from}
        throw
    }
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $recovery 'install-state.json')
    foreach($path in $original.Keys){
        if($original[$path]){Copy-Item -LiteralPath $original[$path] -Destination $path -Force}
    }
    foreach($directory in $pathEntries){
        $userPath=[string][Environment]::GetEnvironmentVariable('PATH','User')
        [Environment]::SetEnvironmentVariable('PATH',((@($userPath.Split(';')|Where-Object {$_.TrimEnd('\','/') -ine $directory.TrimEnd('\','/')})) -join ';'),'User')
    }
    Remove-Item -LiteralPath $manifest
    'TMX uninstalled. Backups, recovery files and the WezTerm runtime are kept at: '+$recovery
}
$verb=if($Arguments.Count){$Arguments[0]}else{'workspace'}
$rest=@(if($Arguments.Count -gt 1){$Arguments[1..($Arguments.Count-1)]})
switch($verb){
    {$_ -in 'help','--help','-h'}{
        'tmx new NAME [--theme NAME] [-d] | attach [NAME] | list | detach'
        'tmx theme NAME | version. Ctrl-a d detaches without stopping processes.'
        'tmx themes | metrics | restore | uninstall. Persistence requires the WezTerm backend.'
    }
    {$_ -in 'version','--version'}{[IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()}
    'themes'{$names}
    '__check-no-sessions'{Assert-NoSessions}
    'restore'{Assert-NoSessions;& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'restore-wezterm.ps1')))) -StatePath (Join-Path $root 'install-state.json')}
    {$_ -in 'uninstall','remove'}{if($rest.Count){throw 'Usage: tmx uninstall'};Remove-Installation}
    'metrics'{
        $path=Join-Path $state 'metrics-once.json'
        $sample=Start-Process -FilePath (Join-Path $root 'TmuxStyle.Metrics.exe') -ArgumentList ('--once "'+$path+'"') -PassThru -Wait -WindowStyle Hidden
        if($sample.ExitCode -ne 0){throw 'Windows metric sampling failed.'}
        Get-Content -LiteralPath $path
    }
    {$_ -in 'list','ls','sessions'}{
        if($rest.Count){throw 'Usage: tmx list'}
        $sessions=@(foreach($file in Get-ChildItem -LiteralPath $state -Filter 'session-*.json' -ErrorAction SilentlyContinue){
            $s=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json
            if($file.Name -ne ('session-'+(Session-Key $s.name)+'.json')){continue}
            $panes=@(Session-Panes $s.name)
            if($panes.Count){[pscustomobject]@{Name=$s.name;Panes=$panes.Count;Theme=$s.theme}}
        })
        if($sessions.Count){$sessions|Format-Table -AutoSize}else{'No TMX sessions. Create one: tmx new work'}
    }
    {$_ -in 'new','new-session','workspace'}{
        if($rest.Count -ge 2 -and $rest[0] -in '-s','--session'){$rest=@($rest[1])+@($rest|Select-Object -Skip 2)}
        if($verb -ne 'workspace' -and -not $rest.Count){throw 'Usage: tmx new NAME [--theme NAME] [-d]'}
        $name=if($rest.Count){$rest[0]}else{'TMUX'}
        $key=Session-Key $name;$selected=$backend.theme;$detached=$false
        for($i=1;$i -lt $rest.Count;$i++){
            switch($rest[$i]){
                {$_ -in '-d','--detach'}{$detached=$true}
                '--theme'{$i++;if($i -ge $rest.Count -or $names -notcontains $rest[$i]){throw 'Choose a theme from: aurora midnight ember paper neon black code hacker'};$selected=$rest[$i]}
                default{throw ('Unknown option: '+$rest[$i])}
            }
        }
        if(@(Session-Panes $name).Count){
            if($verb -ne 'workspace'){throw ('Session already exists: '+$name+'. Use tmx attach '+$name+'.')}
        }else{
            New-Item -ItemType Directory -Path $state -Force|Out-Null
            $path=Session-Path $name
            [IO.File]::WriteAllText($path,(@{name=$name;theme=$selected}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            $server=Join-Path (Split-Path -Parent $backend.executable) 'wezterm-mux-server.exe'
            if(-not(Test-Path -LiteralPath $server)){throw 'This WezTerm installation has no mux server. Reinstall TMX with the bundled WezTerm runtime.'}
            # --cwd makes the pinned mux server construct a default cmd.exe.
            # Let its config select PowerShell, then set the cwd through config.
            Start-SessionProcess $name $server ('--config-file "'+(Join-Path $root ('wezterm-'+$selected+'.lua'))+'"')
            $panes=@();$until=[DateTime]::UtcNow.AddSeconds(12)
            do{Start-Sleep -Milliseconds 100;$panes=@(Session-Panes $name)}while(-not $panes.Count -and [DateTime]::UtcNow -lt $until)
            if(-not $panes.Count){throw 'The TMX session server did not start. Check the WezTerm runtime and socket path.'}
            $first=[string]$panes[0].pane_id
            $right=Invoke-Mux $name @('split-pane','--pane-id',$first,'--horizontal','--percent','35')
            Invoke-Mux $name @('split-pane','--pane-id',$right.Trim(),'--percent','50')|Out-Null
            Invoke-Mux $name @('activate-pane','--pane-id',$first)|Out-Null
        }
        if($detached){'Session ready: '+$name+'. Attach: tmx attach '+$name}else{Attach-Session $name}
    }
    {$_ -in 'attach','a','attach-session'}{
        if($rest.Count -eq 2 -and $rest[0] -eq '-t'){$rest=@($rest[1])}
        if($rest.Count -gt 1){throw 'Usage: tmx attach [NAME]'}
        $name=if($rest.Count){$rest[0]}elseif($env:TMX_SESSION){$env:TMX_SESSION}else{'TMUX'}
        if(-not $rest.Count -and -not $env:TMX_SESSION -and (Test-Path -LiteralPath (Join-Path $state 'last-attached.json'))){
            $last=[IO.File]::ReadAllText((Join-Path $state 'last-attached.json'))|ConvertFrom-Json
            if(@(Session-Panes $last.name).Count){$name=$last.name}
        }
        Session-Key $name|Out-Null
        Attach-Session $name
    }
    'detach'{
        if($rest.Count){throw 'Usage: tmx detach'}
        if(-not $env:TMX_SESSION -or -not $env:WEZTERM_PANE){throw 'Run tmx detach inside a new TMX WezTerm session. Older windows must be reopened after upgrading.'}
        $request='detach:'+ [Guid]::NewGuid().ToString('N')
        Write-Host -NoNewline ([string][char]27+']1337;SetUserVar=TmuxStyleCommand='+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))+[char]7)
    }
    'theme'{
        if(-not $rest.Count){
            if($env:WEZTERM_PANE){
                $request='choose-theme:'+ [Guid]::NewGuid().ToString('N')
                Write-Host -NoNewline ([string][char]27+']1337;SetUserVar=TmuxStyleCommand='+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))+[char]7)
            }else{$names}
            return
        }
        if($names -notcontains $rest[0]){throw 'Usage: tmx theme NAME [--session NAME | --default]'}
        $name=$env:TMX_SESSION;$selected=$rest[0]
        if($rest.Count -eq 2 -and $rest[1] -eq '--default'){
            [IO.File]::WriteAllText($defaultPath,(@{theme=$selected}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            'Default theme for new sessions: '+$selected;return
        }
        if($rest.Count -eq 3 -and $rest[1] -in '--session','-t'){$name=$rest[2]}elseif($rest.Count -ne 1){throw 'Usage: tmx theme NAME [--session NAME | --default]'}
        if(-not $name){
            $available=@(foreach($file in Get-ChildItem -LiteralPath $state -Filter 'session-*.json' -ErrorAction SilentlyContinue){
                $saved=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json
                if(@(Session-Panes $saved.name).Count){$saved.name}
            })
            if($available.Count -eq 1){$name=$available[0]}else{throw 'Run theme inside a TMX session, or specify --session NAME.'}
        }
        if(-not @(Session-Panes $name).Count){throw ('Session not found: '+$name)}
        [IO.File]::WriteAllText((Session-Path $name),(@{name=$name;theme=$selected}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if($name -ceq $env:TMX_SESSION -and $env:WEZTERM_PANE){Write-Host -NoNewline ([string][char]27+']1337;SetUserVar=TmuxStyleTheme='+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($selected))+[char]7)}
        'Theme: '+$selected+' (existing session processes keep running).'
    }
    default{throw 'Unknown command. Run tmx help.'}
}
