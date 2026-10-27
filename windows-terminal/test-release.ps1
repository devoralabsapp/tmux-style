param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$ReportFile)
$ErrorActionPreference='Stop'
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'common.ps1'))))
function Write-JsonFile([string]$Path,$Value){
    [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
}
$blackScheme=@((Read-TmuxStyleJson (Join-Path $SourceDirectory 'settings.additions.json')).schemes|Where-Object {$_.name -eq 'Tmux Style / Command Line'})[0]
foreach($color in $blackScheme.PSObject.Properties|Where-Object {$_.Name -ne 'name'}){
    $hex=$color.Value.TrimStart('#')
    if($hex.Substring(0,2) -ne $hex.Substring(2,2) -or $hex.Substring(2,2) -ne $hex.Substring(4,2)){throw 'Black theme contains a colored accent'}
}
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
foreach($theme in 'aurora','midnight','ember','paper','neon','black'){
    & $setup -SourceDirectory $SourceDirectory -SettingsPath $fixtureSettings -AssetDirectory (Join-Path $fixture 'assets') -DefaultDirectory $fixture -DefaultTheme $theme -NoShortcut
    $merged=Read-TmuxStyleJson (Join-Path $SourceDirectory 'settings.staged.json')
    if(@($merged.profiles.list).Count -ne 7){throw 'Existing profile lost'}
    if($merged.profiles.defaults.font.size -ne 15 -or -not $merged.copyOnSelect){throw 'Preference lost'}
    if(-not($merged.keybindings|Where-Object {$_.id -eq 'User.Keep' -and $_.keys -eq 'ctrl+f12'})){throw 'Existing key lost'}
    if($merged.wordDelimiters -notlike 'http://example.test/a/*b*'){throw 'JSON string was damaged'}
    $profile=@($merged.profiles.list|Where-Object {$_.guid -eq $merged.defaultProfile})[0]
    if($profile.commandline -notlike "*-Theme '$theme'*" ){throw 'Wrong default theme'}
    & $setup -SourceDirectory $SourceDirectory -Apply
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
    try{& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest}
    catch{if($_.Exception.Message -like 'Terminal settings changed*'){$rejected=$true}else{throw}}
    if(-not $rejected -or (Get-FileHash -LiteralPath $fixtureSettings).Hash -ne $editedHash){throw 'Restore did not preserve newer user changes'}
    $normalized.copyOnSelect=$true
    Write-JsonFile $fixtureSettings $normalized
    & ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest
    if((Get-FileHash -LiteralPath $fixtureSettings).Hash -ne $originalHash){throw 'Restore differs'}
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'shell.ps1')))) -Theme $theme -NoBanner -NoKeyBridge
    $global:LASTEXITCODE=7;$promptText=prompt
    if($global:LASTEXITCODE -ne 7 -or $promptText -ne '  > '){throw 'Prompt damaged native status'}
    $checks+='install/restore/prompt '+$theme
}
# Regression for v1.0.0: creating the shortcut used to overwrite the runner's
# CommandInfo variable, so launching via & $terminal.Source became a null call.
# Exercise the entire runner with both options enabled, without touching real
# Terminal windows or production settings.
$fakeTerminal=Join-Path $fixture 'fake-terminal.exe'
$fakeSource=@'
using System;
using System.IO;
public static class MockTerminal {
    public static int Main(string[] args) {
        File.WriteAllLines(Environment.GetEnvironmentVariable("TMUX_STYLE_TEST_TERMINAL_LOG"),args);
        return Environment.GetEnvironmentVariable("TMUX_STYLE_TEST_TERMINAL_FAIL")=="1" ? 7 : 0;
    }
}
'@
Add-Type -TypeDefinition $fakeSource -OutputAssembly $fakeTerminal -OutputType ConsoleApplication
$env:TMUX_STYLE_TEST_TERMINAL_LOG=Join-Path $fixture 'launch-args.txt'
$desktop=Join-Path $fixture 'Desktop'
New-Item -ItemType Directory -Path $desktop -Force|Out-Null
$runner=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'install-runner.ps1')))
& $runner -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $fixture -SettingsPath $fixtureSettings -AssetDirectory (Join-Path $fixture 'assets') -DesktopDirectory $desktop -TerminalExecutable $fakeTerminal -Launch
if(-not(Test-Path (Join-Path $desktop 'Tmux Style Workspace.lnk'))){throw 'Desktop shortcut was not created'}
$launchArguments=[IO.File]::ReadAllLines($env:TMUX_STYLE_TEST_TERMINAL_LOG)
if(@($launchArguments|Where-Object {$_ -eq 'Tmux Style - Command Line'}).Count -ne 3){throw 'Three-pane launch arguments were not preserved'}
$shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Tmux Style Workspace.lnk'))
if($shortcut.TargetPath -ne $fakeTerminal){throw 'Shortcut target differs from the terminal executable'}
$manifest=Join-Path $fixture 'assets\install-state.json'
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest
if((Get-FileHash -LiteralPath $fixtureSettings).Hash -ne $originalHash){throw 'Launch regression fixture did not restore'}
$env:TMUX_STYLE_TEST_TERMINAL_FAIL='1'
$launchOutput=@(& $runner -SourceDirectory $SourceDirectory -Theme black -StartingDirectory $fixture -SettingsPath $fixtureSettings -AssetDirectory (Join-Path $fixture 'assets') -DesktopDirectory $desktop -TerminalExecutable $fakeTerminal -Launch)
if(-not($launchOutput|Where-Object {$_ -like 'Configuration installed successfully. Workspace launch failed:*'})){throw 'Launch failure incorrectly reported as configuration failure'}
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $SourceDirectory 'restore.ps1')))) -StatePath $manifest
Remove-Item Env:TMUX_STYLE_TEST_TERMINAL_LOG,Env:TMUX_STYLE_TEST_TERMINAL_FAIL
$checks+='shortcut creation plus post-install launch regression'
$checks+='launch failure preserves successful configuration result'
$bridgeReport=Join-Path $fixture 'bridge.json'
$proc=Start-Process -FilePath (Join-Path $SourceDirectory 'TmuxStyle.Keys.exe') -ArgumentList ('--self-test "'+$bridgeReport+'"') -PassThru -Wait -WindowStyle Hidden
if($proc.ExitCode -ne 0 -or -not(Test-Path $bridgeReport)){throw 'Key mapping self-test failed'}
$checks+='native key mapping resolver'
$checks+='black palette contains only grayscale values'
$checks+='Terminal first-launch normalization accepted; newer user edits protected'
$report=[pscustomobject]@{passed=$true;powershell=$PSVersionTable.PSVersion.ToString();checks=$checks;keyboardHookInstalled=$false;productionSettingsTouched=$false}
[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Output 'PASS: six theme installs, JSONC merge, backups/restore, prompts, native mappings, shortcut/launch regression.'
