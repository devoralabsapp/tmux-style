param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$ReportFile)
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('TmuxStyleTest-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force|Out-Null
$fixtureSettings=Join-Path $fixture 'settings.json'
$original=@'
{
  // URL and literal comments inside strings must survive
  "profiles":{"defaults":{"font":{"size":15}},"list":[
    {"guid":"{11111111-1111-4111-8111-111111111111}","name":"Keep me","commandline":"cmd.exe"}
  ]},
  "schemes":[], "copyOnSelect":true,
  "actions":[{"id":"User.Keep","command":"copy","keys":"ctrl+f10"}],
  "keybindings":[{"id":"User.Keep","keys":["ctrl+alt+v","ctrl+f12"]}],
  "wordDelimiters":"http://example.test/a/*b*/ trailing,] and \\\"quoted",
}
'@
[IO.File]::WriteAllText($fixtureSettings,$original,[Text.UTF8Encoding]::new($false))
$originalHash=(Get-FileHash -LiteralPath $fixtureSettings).Hash
$setup=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'setup.ps1')))
$checks=@()
foreach($theme in 'aurora','midnight','ember','paper','neon'){
    . $setup -SourceDirectory $SourceDirectory -SettingsPath $fixtureSettings -AssetDirectory (Join-Path $fixture 'assets') -DefaultDirectory $fixture -DefaultTheme $theme -NoShortcut
    $merged=Read-TmuxStyleJson (Join-Path $SourceDirectory 'settings.staged.json')
    if(@($merged.profiles.list).Count -ne 6){throw 'Existing profile lost'}
    if($merged.profiles.defaults.font.size -ne 15 -or -not $merged.copyOnSelect){throw 'Preference lost'}
    if(-not($merged.keybindings|Where-Object {$_.id -eq 'User.Keep' -and $_.keys -eq 'ctrl+f12'})){throw 'Existing key lost'}
    if($merged.wordDelimiters -notlike 'http://example.test/a/*b*'){throw 'JSON string was damaged'}
    $profile=@($merged.profiles.list|Where-Object {$_.guid -eq $merged.defaultProfile})[0]
    if($profile.commandline -notlike "*-Theme '$theme'*" ){throw 'Wrong default theme'}
    . $setup -SourceDirectory $SourceDirectory -Apply
    $manifest=Join-Path $fixture 'assets\install-state.json'
    $installed=Read-TmuxStyleJson $manifest
    if((Get-FileHash -LiteralPath $installed.settingsBackup).Hash -ne $originalHash){throw 'Backup differs'}
    # Windows Terminal rewrites equivalent colors/actions and adds generated profiles.
    $normalized=Read-TmuxStyleJson $fixtureSettings
    foreach($profileItem in $normalized.profiles.list){if($profileItem.tabColor){$profileItem.tabColor=$profileItem.tabColor.ToUpperInvariant()}}
    foreach($actionItem in $normalized.actions){if($actionItem.command -is [string] -and $actionItem.command -eq 'newTab'){$actionItem.command=[pscustomobject]@{action='newTab'}}}
    $normalized.profiles.list+=([pscustomobject]@{guid='{61c54bbd-c2c6-5271-96e7-009a87ff44bf}';name='Windows PowerShell';commandline='powershell.exe'})
    $normalized|Add-Member NoteProperty '$help' 'https://aka.ms/terminal-documentation' -Force
    $normalized|Add-Member NoteProperty newTabMenu @([pscustomobject]@{type='remainingProfiles'}) -Force
    $normalized|Add-Member NoteProperty themes @() -Force
    Write-JsonFile $fixtureSettings $normalized
    if(-not(Test-TmuxStyleNormalization (Read-TmuxStyleJson $installed.expectedSettings) $normalized)){throw 'Equivalent Terminal normalization rejected'}
    $normalized.copyOnSelect=$false
    Write-JsonFile $fixtureSettings $normalized
    $editedHash=(Get-FileHash -LiteralPath $fixtureSettings).Hash
    $rejected=$false
    try{. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest}
    catch{if($_.Exception.Message -like 'Terminal settings changed*'){$rejected=$true}else{throw}}
    if(-not $rejected -or (Get-FileHash -LiteralPath $fixtureSettings).Hash -ne $editedHash){throw 'Restore did not preserve newer user changes'}
    $normalized.copyOnSelect=$true
    Write-JsonFile $fixtureSettings $normalized
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest
    if((Get-FileHash -LiteralPath $fixtureSettings).Hash -ne $originalHash){throw 'Restore differs'}
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'shell.ps1')))) -Theme $theme -NoBanner -NoKeyBridge
    $global:LASTEXITCODE=7;$promptText=prompt
    if($global:LASTEXITCODE -ne 7 -or $promptText -ne '  > '){throw 'Prompt damaged native status'}
    $checks+='install/restore/prompt '+$theme
}
$bridgeReport=Join-Path $fixture 'bridge.json'
$proc=Start-Process -FilePath (Join-Path $SourceDirectory 'TmuxStyle.Keys.exe') -ArgumentList ('--self-test "'+$bridgeReport+'"') -PassThru -Wait -WindowStyle Hidden
if($proc.ExitCode -ne 0 -or -not(Test-Path $bridgeReport)){throw 'Key mapping self-test failed'}
$checks+='native key mapping resolver'
$checks+='Terminal first-launch normalization accepted; newer user edits protected'
$report=[pscustomobject]@{passed=$true;powershell=$PSVersionTable.PSVersion.ToString();checks=$checks;keyboardHookInstalled=$false;productionSettingsTouched=$false}
[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Output 'PASS: five theme installs, JSONC merge, exact backups/restore, prompts, native mappings.'
