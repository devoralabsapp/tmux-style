param(
    [switch]$Apply,
    [string]$SourceDirectory=$PSScriptRoot,
    [ValidateSet('aurora','midnight','ember','paper','neon','black','code','hacker')][string]$DefaultTheme='aurora',
    [string]$TerminalExecutable,
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    [string]$AssetDirectory = (Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows'),
    [string]$DesktopDirectory = [Environment]::GetFolderPath('DesktopDirectory'),
    [string]$DefaultDirectory = $HOME,
    [switch]$NoShortcut
)
$ErrorActionPreference='Stop'
if(-not $SourceDirectory){throw 'Provide -SourceDirectory when loading setup as a script block.'}
$sourceDirectory=[IO.Path]::GetFullPath($SourceDirectory)
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $sourceDirectory 'common.ps1'))))
$stagePath=Join-Path $sourceDirectory 'settings.staged.json'
$statePath=Join-Path $sourceDirectory 'stage-state.json'

function Set-Property($Object,[string]$Name,$Value) {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}
function Write-JsonFile([string]$Path,$Object) {
    [IO.File]::WriteAllText($Path,($Object | ConvertTo-Json -Depth 100)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
function Hash-OrMissing([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return 'MISSING'
}

if (-not $Apply) {
    $additions=Read-TmuxStyleJson (Join-Path $sourceDirectory 'settings.additions.json')
    if (Test-Path -LiteralPath $SettingsPath) {
        $settings=Read-TmuxStyleJson $SettingsPath
    } else { $settings=[pscustomobject]@{} }
    if (-not $settings.profiles) { Set-Property $settings profiles ([pscustomobject]@{defaults=[pscustomobject]@{};list=@()}) }
    if ($settings.profiles -is [array]) {
        Set-Property $settings profiles ([pscustomobject]@{defaults=[pscustomobject]@{};list=@($settings.profiles)})
    }
    $ownedGuids=@($additions.profiles | ForEach-Object {$_.guid})
    $profiles=@($settings.profiles.list | Where-Object {$_ -and $_.guid -notin $ownedGuids})
    foreach ($profile in $additions.profiles) {
        $slug=$profile.slug
        if($slug -eq $DefaultTheme){$defaultGuid=$profile.guid;$defaultProfileName=$profile.name}
        $profile.PSObject.Properties.Remove('slug')
        $shellPath=(Join-Path $AssetDirectory 'shell.ps1').Replace("'","''")
        # Session-local initialization, without editing the user's shared $PROFILE.
        $initialization=". ([scriptblock]::Create([IO.File]::ReadAllText('$shellPath'))) -Theme '$slug'"
        $commandline='powershell.exe -NoLogo -NoExit -Command "'+$initialization+'"'
        Set-Property $profile commandline $commandline
        Set-Property $profile startingDirectory $DefaultDirectory
        Set-Property $profile icon (Join-Path $AssetDirectory 'tmux-style.ico')
        $profiles+=$profile
    }
    Set-Property $settings.profiles list @($profiles)
    $schemeNames=@($additions.schemes | ForEach-Object {$_.name})
    Set-Property $settings schemes @(@($settings.schemes | Where-Object {$_ -and $_.name -notin $schemeNames})+@($additions.schemes))
    $newKeys=@($additions.keybindings | ForEach-Object {$_.keys.ToLowerInvariant()})
    $existingActions=@($settings.actions | Where-Object {$_ -and $_.id -notlike 'User.TmuxStyle.*'})
    $legacyBindings=@()
    foreach ($existing in $existingActions) {
        if ($existing.keys) {
            if (-not $existing.id) { Set-Property $existing id ('User.Migrated.'+[guid]::NewGuid().ToString('N')) }
            $remainingKeys=@($existing.keys | Where-Object {$_.ToLowerInvariant() -notin $newKeys})
            foreach($key in $remainingKeys){$legacyBindings += [pscustomobject]@{id=$existing.id;keys=$key}}
            # Current Terminal separates command definitions from keybindings.
            $existing.PSObject.Properties.Remove('keys')
        }
    }
    Set-Property $settings actions @($existingActions+@($additions.actions))
    $bindings=@()
    foreach ($binding in @($settings.keybindings)) {
        if (-not $binding -or $binding.id -like 'User.TmuxStyle.*') { continue }
        $remaining=@($binding.keys | Where-Object {$_.ToLowerInvariant() -notin $newKeys})
        foreach($key in $remaining){
            $copy=$binding.PSObject.Copy()
            Set-Property $copy keys $key
            $bindings+=$copy
        }
    }
    Set-Property $settings keybindings @($bindings+$legacyBindings+@($additions.keybindings))
    Set-Property $settings '$schema' 'https://aka.ms/terminal-profiles-schema'
    Set-Property $settings defaultProfile $defaultGuid
    Set-Property $settings theme 'dark'
    Set-Property $settings alwaysShowTabs $true
    Set-Property $settings showTabsInTitlebar $true
    Set-Property $settings tabWidthMode 'titleLength'
    Set-Property $settings initialCols 132
    Set-Property $settings initialRows 34
    Write-JsonFile $stagePath $settings
    Write-JsonFile $statePath ([pscustomobject]@{
        settingsPath=$SettingsPath; previousHash=(Hash-OrMissing $SettingsPath)
        stagedHash=(Hash-OrMissing $stagePath);assetDirectory=$AssetDirectory
        desktopDirectory=$DesktopDirectory;defaultDirectory=$DefaultDirectory
        shortcut=(-not $NoShortcut);created=(Get-Date -Format o)
        defaultProfileName=$defaultProfileName
        terminalExecutable=$TerminalExecutable
    })
    Write-Output "Staged configuration: $stagePath"
    return
}

$state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ((Hash-OrMissing $stagePath) -ne $state.stagedHash) { throw 'Staged configuration changed; stage and validate again.' }
if ((Hash-OrMissing $state.settingsPath) -ne $state.previousHash) { throw 'Windows Terminal settings changed; stage and validate again.' }
if ((Get-Command Test-Json -ErrorAction SilentlyContinue) -and -not (Test-Json -LiteralPath $stagePath -SchemaFile (Join-Path $sourceDirectory 'profiles.schema.json'))) {
    throw 'The staged settings did not pass the official schema.'
}
$backupDirectory=Join-Path $state.assetDirectory ('backups\'+(Get-Date -Format yyyyMMdd-HHmmss)+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$settingsBackup=$null
if ($state.previousHash -ne 'MISSING') {
    $settingsBackup=Join-Path $backupDirectory 'settings.before.json'
    Copy-Item -LiteralPath $state.settingsPath -Destination $settingsBackup
}
$ownedAssets=@('shell.ps1','restore.ps1','common.ps1','settings.additions.json','TmuxStyle.Keys.exe','tmux-style.ico')
$assetBackups=@()
foreach($name in $ownedAssets){
    $path=Join-Path $state.assetDirectory $name
    $backup=$null
    if(Test-Path -LiteralPath $path){$backup=Join-Path $backupDirectory $name;Copy-Item -LiteralPath $path -Destination $backup}
    $assetBackups+=[pscustomobject]@{path=$path;backup=$backup}
}
$oldBridge=Join-Path $state.assetDirectory 'TmuxStyle.Keys.exe'
if(Test-Path -LiteralPath $oldBridge){
    Stop-TmuxStyleOwnedBridge $oldBridge
}
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'shell.ps1') -Destination (Join-Path $state.assetDirectory 'shell.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'restore.ps1') -Destination (Join-Path $state.assetDirectory 'restore.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'common.ps1') -Destination (Join-Path $state.assetDirectory 'common.ps1') -Force
if(Test-Path (Join-Path $sourceDirectory 'TmuxStyle.Keys.exe')){Copy-Item -LiteralPath (Join-Path $sourceDirectory 'TmuxStyle.Keys.exe') -Destination (Join-Path $state.assetDirectory 'TmuxStyle.Keys.exe') -Force}
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'tmux-style.ico') -Destination (Join-Path $state.assetDirectory 'tmux-style.ico') -Force
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'settings.additions.json') -Destination (Join-Path $state.assetDirectory 'settings.additions.json') -Force
New-Item -ItemType Directory -Path (Split-Path -Parent $state.settingsPath) -Force | Out-Null
Copy-Item -LiteralPath $stagePath -Destination $state.settingsPath -Force
$shortcutPath=$null; $shortcutBackup=$null
if ($state.shortcut) {
    $shortcutPath=Join-Path $state.desktopDirectory 'Tmux Style Workspace.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        $shortcutBackup=Join-Path $backupDirectory 'Aurora Workspace.before.lnk'
        Copy-Item -LiteralPath $shortcutPath -Destination $shortcutBackup
    }
    $shortcutTerminalExe=$state.terminalExecutable
    if(-not $shortcutTerminalExe){$shortcutTerminalExe=(Get-Command wt.exe -ErrorAction Stop).Source}
    $wshell=New-Object -ComObject WScript.Shell
    $shortcut=$wshell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath=$shortcutTerminalExe
    $shortcut.IconLocation=(Join-Path $state.assetDirectory 'tmux-style.ico')+',0'
    $profileName=$state.defaultProfileName
    $directory=$state.defaultDirectory
    $shortcut.Arguments='-w new new-tab -p "'+$profileName+'" -d "'+$directory+'" ; split-pane -V -s 0.35 -p "'+$profileName+'" -d "'+$directory+'" ; split-pane -H -s 0.5 -p "'+$profileName+'" -d "'+$directory+'" ; move-focus first'
    $shortcut.WorkingDirectory=$directory
    $shortcut.Description='Tmux Style PowerShell workspace: editor / tools / logs'
    $shortcut.Save()
}
$manifest=[pscustomobject]@{
    settingsPath=$state.settingsPath;settingsBackup=$settingsBackup
    previousHash=$state.previousHash;installedHash=(Hash-OrMissing $state.settingsPath)
    shortcutPath=$shortcutPath;shortcutBackup=$shortcutBackup
    shortcutHash=$(if($shortcutPath){Hash-OrMissing $shortcutPath}else{$null})
    backupDirectory=$backupDirectory;installedAt=(Get-Date -Format o)
    expectedSettings=(Join-Path $backupDirectory 'settings.installed.json')
    assetBackups=$assetBackups
}
Copy-Item -LiteralPath $state.settingsPath -Destination $manifest.expectedSettings
Write-JsonFile (Join-Path $state.assetDirectory 'install-state.json') $manifest
Write-JsonFile (Join-Path $sourceDirectory 'installed-state.json') $manifest
Write-Output ('Applied. Backups: '+$backupDirectory)
