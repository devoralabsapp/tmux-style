param([Parameter(Mandatory=$true)][string]$SourceDirectory,
      [Parameter(Mandatory=$true)][string]$WezTermExecutable,[string]$ReportFile,[switch]$SoftwareRendering)
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('tmx-native-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $fixture|Out-Null
if($SoftwareRendering){
    # Hosted Windows runners may have no usable GPU. Exercise real GUI/mux
    # behavior with WezTerm's supported CPU renderer, in a private source copy.
    $renderSource=Join-Path $fixture 'source'
    New-Item -ItemType Directory -Path $renderSource|Out-Null
    Get-ChildItem -LiteralPath $SourceDirectory -File|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $renderSource}
    $template=Join-Path $renderSource 'wezterm.lua'
    $text=[IO.File]::ReadAllText($template).Replace('return config',"config.front_end = 'Software'`nreturn config")
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
        if($LASTEXITCODE -ne 0){throw ('Native mux operation failed: '+($Arguments -join ' '))}
        return ($out -join "`n")
    }finally{Remove-Item Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue}
}
function Panes([string]$Name){@(Mux $Name @('list','--format','json')|ConvertFrom-Json)}
function Clients([string]$Name){@(Mux $Name @('list-clients','--format','json')|ConvertFrom-Json)}
function Send([string]$Name,[string]$Pane,[string]$Text){Mux $Name @('send-text','--no-paste','--pane-id',$Pane,($Text+"`r"))|Out-Null}
try{
    & $setup -SourceDirectory $SourceDirectory -AssetDirectory $assets -StartingDirectory $fixture -WezTermExecutable $WezTermExecutable -CommandDirectory $commands -NoShortcut -NoCommandPath
    $env:PATH=$commands+';'+$savedPath
    if((Get-Command tmx.exe).Source -ne (Join-Path $commands 'tmx.exe')){throw 'Installed command is not discoverable on PATH'}
    $version=Invoke-TestTmx @('version')
    $cmdVersion=& $env:ComSpec /d /c 'tmx version'
    if($LASTEXITCODE -ne 0 -or $cmdVersion.Trim() -ne $version.Trim()){throw 'CMD and PowerShell entry points differ'}
    $checks+='installed tmx.exe works on PATH from PowerShell and CMD without profile or execution-policy changes'
    Invoke-TestTmx @('new','work','--theme','code','-d')|Out-Null
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
    Send work $first 'tmx detach'
    Wait-Until {(Clients work).Count -eq 0}
    Wait-Until {[IO.File]::ReadAllText($tickFile) -ne $tick}
    if((Panes work).pane_id -join ',' -ne $ids){throw 'Detach changed pane IDs'}
    if(-not(Get-Process -Id ([int]$shellPid) -ErrorAction SilentlyContinue)){throw 'Detach terminated the original shell'}
    Invoke-TestTmx @('attach','work')|Out-Null
    Wait-Until {(Clients work).Count -gt 0}
    Send work $first ("[IO.File]::WriteAllText('$quotePid',[string]`$PID)")
    Start-Sleep -Milliseconds 400
    if([IO.File]::ReadAllText($pidFile) -ne $shellPid){throw 'Reattach started another shell'}
    Send work $first ("& '"+(Join-Path $commands 'tmx.exe').Replace("'","''")+"' detach")
    Wait-Until {(Clients work).Count -eq 0}
    $checks+='real GUI attach/detach/reattach twice retains pane IDs, original PowerShell PID and running background job'
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
    Send work $first 'Stop-Job $global:tmxJob; Remove-Job $global:tmxJob'
    foreach($name in 'work','lab','defaults'){
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
    $report=[pscustomobject]@{passed=$true;platform='Windows';runtime=(& $WezTermExecutable --version);renderer=$(if($SoftwareRendering){'Software'}else{'Default'});checks=$checks}
    if($ReportFile){[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
    'PASS: native Windows command, persistent named sessions, real detach/attach and safe uninstall.'
}catch{
    foreach($log in Get-ChildItem -LiteralPath $state -Filter 'gui-*.log' -ErrorAction SilentlyContinue){Get-Content -LiteralPath $log.FullName -Tail 20|Write-Output}
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
