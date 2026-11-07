param([Parameter(Mandatory=$true)][string]$SourceDirectory,
      [Parameter(Mandatory=$true)][string]$WezTermExecutable,[string]$ReportFile,[switch]$SoftwareRendering,[bool]$RequirePhysicalResize=$true)
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('tmx-native-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $fixture|Out-Null
if($true){
    # Hosted Windows runners may have no usable GPU. Exercise real GUI/mux
    # behavior with WezTerm's supported CPU renderer, in a private source copy.
    $renderSource=Join-Path $fixture 'source'
    New-Item -ItemType Directory -Path $renderSource|Out-Null
    Get-ChildItem -LiteralPath $SourceDirectory -File|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $renderSource}
    $template=Join-Path $renderSource 'wezterm.lua'
    $text=[IO.File]::ReadAllText($template)
    if($SoftwareRendering){$text=$text.Replace('return config',"config.front_end = 'Software'`nreturn config")}
    # Test-only window controls and geometry telemetry in an isolated copy.
    $controls=@'
  if name == 'TmxTestWindow' then
    if value:match('^small:') then window:restore();wezterm.time.call_after(0.25,function() window:set_inner_size(720,460) end)
    elseif value:match('^large:') then window:maximize() end
    return
  end
'@
    $text=$text.Replace("wezterm.on('user-var-changed', function(window,pane,name,value)","wezterm.on('user-var-changed', function(window,pane,name,value)`n"+$controls)
    $telemetry=@'
  do
    local size=active_tab:get_size()
    local f=io.open(state_dir..'/geometry-test.json','w')
    if f then f:write(wezterm.json_encode{cols=size.cols,rows=size.rows});f:close() end
  end
'@
    $text=$text.Replace('  if not valid or not active_tab then return end','  if not valid or not active_tab then return end'+"`n"+$telemetry)
    [IO.File]::WriteAllText($template,$text,[Text.UTF8Encoding]::new($false))
    $SourceDirectory=$renderSource
}
$assets=Join-Path $fixture 'assets'
$commands=Join-Path $fixture 'commands'
$state=$assets+'-state'
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup-wezterm.ps1')))
$checks=@();$savedPath=$env:PATH
$savedEnv=@{}
foreach($key in 'WEZTERM_UNIX_SOCKET','WEZTERM_PANE','TMX_SESSION','TMX_SESSION_KEY'){$savedEnv[$key]=[Environment]::GetEnvironmentVariable($key);[Environment]::SetEnvironmentVariable($key,$null)}
function Wait-Until([scriptblock]$Condition){
    $until=[DateTime]::UtcNow.AddSeconds(15)
    do{if(& $Condition){return};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $until)
    throw ('Timed out waiting for native Windows session state: '+$Condition.ToString().Trim())
}
function Invoke-TestTmx([string[]]$Arguments,[switch]$Fail){
    $out=@(& (Join-Path $commands 'tmx.exe') @Arguments 2>&1)
    if($Fail){if($LASTEXITCODE -eq 0){throw ('Unexpected success: '+($Arguments -join ' '))}}
    elseif($LASTEXITCODE -ne 0){throw ('Command failed: '+($Arguments -join ' ')+': '+($out -join ' '))}
    return ($out -join "`n")
}
function Mux([string]$Name,[string[]]$Arguments){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Name))).Replace('-','').Substring(0,16).ToLowerInvariant()}finally{$sha.Dispose()}
    $env:WEZTERM_UNIX_SOCKET=Join-Path $state ('mux-'+$key+'.sock')
    try{
        $out=@(& $WezTermExecutable cli --no-auto-start @Arguments 2>&1)
        if($LASTEXITCODE -ne 0){throw ('Native mux operation failed: '+($Arguments -join ' ')+': '+($out -join ' '))}
        return ($out -join "`n")
    }finally{Remove-Item Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue}
}
function Panes([string]$Name){@(Mux $Name @('list','--format','json')|ConvertFrom-Json)}
function Clients([string]$Name){@(Mux $Name @('list-clients','--format','json')|ConvertFrom-Json)}
function Send([string]$Name,[string]$Pane,[string]$Text){Mux $Name @('send-text','--no-paste','--pane-id',$Pane,($Text+"`r"))|Out-Null}
function Check-Geometry {
    $path=Join-Path $state 'geometry-test.json'
    if(-not(Test-Path $path)){return $false}
    try{
        $grid=[IO.File]::ReadAllText($path)|ConvertFrom-Json
        $panes=@(Panes work)
        foreach($p in $panes){
            if($p.left_col+$p.size.cols -gt $grid.cols -or $p.top_row+$p.size.rows -gt $grid.rows){return $false}
        }
        return $panes.Count -eq 3
    }catch{return $false}
}
try{
    & $setup -SourceDirectory $SourceDirectory -AssetDirectory $assets -StartingDirectory $fixture -WezTermExecutable $WezTermExecutable -CommandDirectory $commands -NoShortcut -NoCommandPath
    $env:PATH=$commands+';'+$savedPath
    if((Get-Command tmx.exe).Source -ne (Join-Path $commands 'tmx.exe')){throw 'Installed command is not discoverable on PATH'}
    $version=Invoke-TestTmx @('version')
    $cmdVersion=& $env:ComSpec /d /c 'tmx version'
    if($LASTEXITCODE -ne 0 -or $cmdVersion.Trim() -ne $version.Trim()){throw 'CMD and PowerShell entry points differ'}
    $checks+='installed tmx.exe works on PATH from PowerShell and CMD without profile or execution-policy changes'
    if((Invoke-TestTmx @('renderer')).Trim() -ne 'webgpu'){throw 'Default renderer must use WebGPU'}
    Invoke-TestTmx @('renderer','invalid') -Fail|Out-Null
    Invoke-TestTmx @('renderer','software')|Out-Null
    if((Invoke-TestTmx @('renderer')).Trim() -ne 'software'){throw 'Software renderer recovery was not saved'}
    Invoke-TestTmx @('renderer','webgpu')|Out-Null
    $checks+='WebGPU renderer default and software recovery command validated without changing live sessions'
    Invoke-TestTmx @('new','work','--theme','prism','-d')|Out-Null
    Invoke-TestTmx @('new','lab','--theme','hacker','-d')|Out-Null
    if((Panes work).Count -ne 3 -or (Panes lab).Count -ne 3){throw 'Named sessions must each have exactly three panes'}
    if((Invoke-TestTmx @('list')) -notmatch 'work' -or (Invoke-TestTmx @('ls')) -notmatch 'lab'){throw 'Sessions missing from list'}
    Invoke-TestTmx @('new','work','-d') -Fail|Out-Null
    Invoke-TestTmx @('new','../invalid','-d') -Fail|Out-Null
    Invoke-TestTmx @('attach','missing') -Fail|Out-Null
    $panes=@(Panes work);$first=[string]$panes[0].pane_id
    # RPC pane creation can precede PowerShell/PSReadLine startup on CI hosts.
    # Wait for the prompt before injecting commands into its input stream.
    Wait-Until {(Mux work @('get-text','--pane-id',$first)).Contains('  > ')}
    Start-Sleep -Milliseconds 300
    $ids=($panes.pane_id -join ',')
    $pidFile=Join-Path $fixture 'shell-pid.txt'
    $tickFile=Join-Path $fixture 'heartbeat.txt'
    $quotePid=$pidFile.Replace("'","''");$quoteTick=$tickFile.Replace("'","''")
    Send work $first ("[IO.File]::WriteAllText('$quotePid',[string]`$PID); `$global:tmxJob=Start-Job {param(`$p) while(`$true){[IO.File]::WriteAllText(`$p,[string][DateTime]::UtcNow.Ticks);Start-Sleep -Milliseconds 200}} -ArgumentList '$quoteTick'")
    Wait-Until {Test-Path -LiteralPath $pidFile}
    Wait-Until {Test-Path -LiteralPath $tickFile}
    $shellPid=[IO.File]::ReadAllText($pidFile)
    $tick=[IO.File]::ReadAllText($tickFile)
    $checks+='named sessions, three-pane layout, missing/duplicate/invalid-name validation and list aliases'
    Invoke-TestTmx @('attach','-t','work')|Out-Null
    Wait-Until {(Clients work).Count -gt 0}
    Wait-Until {Check-Geometry}
    Send work $first 'tmx detach'
    Wait-Until {(Clients work).Count -eq 0}
    Wait-Until {[IO.File]::ReadAllText($tickFile) -ne $tick}
    if((Panes work).pane_id -join ',' -ne $ids){throw 'Detach changed pane IDs'}
    if(-not(Get-Process -Id ([int]$shellPid) -ErrorAction SilentlyContinue)){throw 'Detach terminated the original shell'}
    Invoke-TestTmx @('attach','work')|Out-Null
    Wait-Until {(Clients work).Count -gt 0}
    foreach($mode in 'small','large'){
        $signal=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mode+':'+[Guid]::NewGuid().ToString('N')))
        Send work $first ("Write-Host -NoNewline ([string][char]27+']1337;SetUserVar=TmxTestWindow=$signal'+[char]7)")
        Start-Sleep -Milliseconds 800
        Wait-Until {
            if(-not(Check-Geometry)){return $false}
            $grid=[IO.File]::ReadAllText((Join-Path $state 'geometry-test.json'))|ConvertFrom-Json
            if(-not $RequirePhysicalResize){return $true}
            if($mode -eq 'small'){return $grid.cols -le 90}
            return $grid.cols -gt $smallColumns
        }
        if($mode -eq 'small'){$smallColumns=([IO.File]::ReadAllText((Join-Path $state 'geometry-test.json'))|ConvertFrom-Json).cols}
    }
    Send work $first ("[IO.File]::WriteAllText('$quotePid',[string]`$PID)")
    Start-Sleep -Milliseconds 400
    if([IO.File]::ReadAllText($pidFile) -ne $shellPid){throw 'Reattach started another shell'}
    Send work $first 'for ($i=1; $i -le 30000; $i+=1000) { [Console]::WriteLine((($i..($i+999) | ForEach-Object { "TMX_LOG_{0:00000}" -f $_ }) -join "`r`n")) }'
    Wait-Until {(Mux work @('get-text','--pane-id',$first)).Contains('TMX_LOG_30000')}
    $history=Mux work @('get-text','--pane-id',$first,'--start-line=-30000')
    $logLines=@([regex]::Matches($history,'(?m)^TMX_LOG_[0-9]{5}\r?$'))
    $visible=(Panes work|Where-Object pane_id -eq $first).size.rows
    if($logLines.Count -lt 19000 -or $logLines.Count -gt (20000+$visible) -or $history -match '(?m)^TMX_LOG_00001\r?$'){throw 'WezTerm scrollback did not evict old lines at the 20,000-line cap'}
    $probe=Join-Path $fixture 'scrollback-pid.txt'
    Send work $first ("[IO.File]::WriteAllText('"+$probe.Replace("'","''")+"',[string]`$PID)")
    Wait-Until {Test-Path -LiteralPath $probe}
    if((Panes work).pane_id -join ',' -ne $ids -or [IO.File]::ReadAllText($probe) -ne $shellPid){throw 'Heavy output replaced a running pane'}
    $checks+='30,000 log lines rotate at the 20,000-line cap without replacing a live pane'
    Send work $first ("& '"+(Join-Path $commands 'tmx.exe').Replace("'","''")+"' detach")
    Wait-Until {(Clients work).Count -eq 0}
    $checks+='real GUI attach/detach/reattach twice retains pane IDs, original PowerShell PID and running background job'
    $checks+=if($RequirePhysicalResize){'actual small/maximized transitions keep every PTY within the retained split grid'}else{'pane bounds verified after GUI resize requests; physical display transitions verified separately on desktop'}
    Invoke-TestTmx @('theme','paper','--session','work')|Out-Null
    Invoke-TestTmx @('theme','neon','--default')|Out-Null
    Invoke-TestTmx @('new','defaults','-d')|Out-Null
    $themes=@(Get-ChildItem -LiteralPath $state -Filter 'session-*.json'|ForEach-Object {[IO.File]::ReadAllText($_.FullName)|ConvertFrom-Json})
    if(($themes|Where-Object name -eq work).theme -ne 'paper' -or ($themes|Where-Object name -eq lab).theme -ne 'hacker' -or ($themes|Where-Object name -eq defaults).theme -ne 'neon'){throw 'Session themes are not independent'}
    Invoke-TestTmx @('attach','work')|Out-Null
    Wait-Until {(Clients work).Count -gt 0}
    $themeFile=Join-Path $fixture 'prompt-theme.txt'
    Send work $first ("Sync-TmuxStyleShellTheme; [IO.File]::WriteAllText('"+$themeFile.Replace("'","''")+"',[string]`$global:TmuxStyleTheme)")
    Wait-Until {(Test-Path -LiteralPath $themeFile) -and [IO.File]::ReadAllText($themeFile) -eq 'paper'}
    if((Panes work).Count -ne 3){throw 'Reattach duplicated the layout'}
    Send work $first 'tmx detach'
    Wait-Until {(Clients work).Count -eq 0}
    Invoke-TestTmx @('uninstall') -Fail|Out-Null
    Invoke-TestTmx @('restore') -Fail|Out-Null
    if(-not(Test-Path -LiteralPath (Join-Path $assets 'install-state.json'))){throw 'Active-session guard removed files'}
    $checks+='per-session and default theme commands; restore/uninstall refuse live sessions including detached ones'
    Invoke-TestTmx @('exit') -Fail|Out-Null
    Invoke-TestTmx @('exit','lab') -Fail|Out-Null
    $labIds=((Panes lab).pane_id -join ',')
    Mux work @('spawn','--pane-id',$first)|Out-Null
    if((Panes work).Count -lt 4){throw 'Exit regression needs multiple tabs'}
    Send work $first 'tmx exit'
    Wait-Until {(Invoke-TestTmx @('list')) -notmatch '(?m)^work\s'}
    Wait-Until {-not(Get-Process -Id ([int]$shellPid) -ErrorAction SilentlyContinue)}
    if(((Panes lab).pane_id -join ',') -ne $labIds){throw 'Exit touched another session'}
    Start-Sleep -Milliseconds 800
    $lastTick=[IO.File]::ReadAllText($tickFile)
    Start-Sleep -Milliseconds 500
    if([IO.File]::ReadAllText($tickFile) -ne $lastTick){throw 'Exit left the session background job running'}
    $labFirst=[string](Panes lab)[0].pane_id
    Wait-Until {(Mux lab @('get-text','--pane-id',$labFirst)).Contains('  > ')}
    Send lab $labFirst ("& '"+(Join-Path $commands 'tmx.exe').Replace("'","''")+"' exit")
    Wait-Until {(Invoke-TestTmx @('list')) -notmatch '(?m)^lab\s'}
    Invoke-TestTmx @('new','work','-d')|Out-Null
    $reusedFirst=[string](Panes work)[0].pane_id
    Wait-Until {(Mux work @('get-text','--pane-id',$reusedFirst)).Contains('  > ')}
    Send work $reusedFirst 'tmx exit'
    Wait-Until {(Invoke-TestTmx @('list')) -notmatch '(?m)^work\s'}
    $checks+='tmx exit closes every tab/pane and stops the shell/job; other sessions survive; native EXE exit also works; outer/argument calls rejected'
    foreach($name in 'defaults'){
        foreach($pane in @(Panes $name)){Mux $name @('kill-pane','--pane-id',[string]$pane.pane_id)|Out-Null}
    }
    Wait-Until {(Invoke-TestTmx @('list')) -match 'No TMX sessions'}
    # Test a real upgrade, full uninstall and installed-command edit protection.
    & $setup -SourceDirectory $SourceDirectory -AssetDirectory $assets -StartingDirectory $fixture -WezTermExecutable $WezTermExecutable -CommandDirectory $commands -NoShortcut -NoCommandPath
    Invoke-TestTmx @('restore')|Out-Null
    if((Invoke-TestTmx @('version')).Trim() -ne $version.Trim()){throw 'Command restore did not retain the previous launcher'}
    & $setup -SourceDirectory $SourceDirectory -AssetDirectory $assets -StartingDirectory $fixture -WezTermExecutable $WezTermExecutable -CommandDirectory $commands -NoShortcut -NoCommandPath
    $changed=Join-Path $assets 'shell.ps1';$original=[IO.File]::ReadAllBytes($changed)
    [IO.File]::AppendAllText($changed,"`n# user edit")
    Invoke-TestTmx @('uninstall') -Fail|Out-Null
    [IO.File]::WriteAllBytes($changed,$original)
    Invoke-TestTmx @('uninstall')|Out-Null
    if((Test-Path -LiteralPath (Join-Path $commands 'tmx.exe')) -or (Test-Path -LiteralPath (Join-Path $assets 'backend.json'))){throw 'Uninstall left an active command or backend'}
    if(-not(Get-ChildItem -LiteralPath (Join-Path $assets 'backups') -Filter 'uninstall-*')){throw 'Uninstall recovery copy missing'}
    $checks+='command restore and full uninstall across upgrades preserve recovery backups and refuse edited files'
    $report=[pscustomobject]@{passed=$true;platform='Windows';runtime=(& $WezTermExecutable --version);renderer=$(if($SoftwareRendering){'Software'}else{'WebGpu'});physicalResizeRequired=$RequirePhysicalResize;checks=$checks}
    if($ReportFile){[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
    'PASS: native Windows command, persistent named sessions, real detach/attach and safe uninstall.'
}catch{
    try{Write-Output ('Failed geometry: '+[IO.File]::ReadAllText((Join-Path $state 'geometry-test.json')));Write-Output (Mux work @('list','--format','json'))}catch{}
    foreach($log in Get-ChildItem -LiteralPath $state -Filter 'gui-*.log' -ErrorAction SilentlyContinue){Get-Content -LiteralPath $log.FullName -Tail 20|Write-Output}
    foreach($directory in @((Join-Path $env:USERPROFILE '.local\share\wezterm'),(Join-Path $env:LOCALAPPDATA 'wezterm'),(Join-Path $env:TEMP 'wezterm'))){
        foreach($log in Get-ChildItem -LiteralPath $directory -Filter 'wezterm-gui*-log-*.txt' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 2){
            Get-Content -LiteralPath $log.FullName -Tail 30|Write-Output
        }
    }
    Get-CimInstance Win32_Process -Filter "Name='wezterm-gui.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($fixture)}|Select-Object ProcessId,SessionId,CommandLine|Format-List|Out-String|Write-Output
    throw
}finally{
    # Only terminate test processes whose command line contains this exact,
    # freshly created fixture. Do not touch installed workspaces or other muxes.
    foreach($process in Get-CimInstance Win32_Process -Filter "Name='wezterm-mux-server.exe' OR Name='wezterm-gui.exe'"){
        if($process.CommandLine -and $process.CommandLine.Contains($fixture)){Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue}
    }
    $env:PATH=$savedPath
    foreach($key in $savedEnv.Keys){[Environment]::SetEnvironmentVariable($key,$savedEnv[$key])}
}
