param([string]$Version,[switch]$RunTests,[string]$SourceDirectory=$PSScriptRoot)
$ErrorActionPreference='Stop'
$root=$SourceDirectory
if(-not $root){throw 'Provide -SourceDirectory when invoking build as a script block.'}
if(-not $Version){$Version=[IO.File]::ReadAllText((Join-Path (Split-Path -Parent $root) 'VERSION')).Trim()}
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Version must have the form 1.1.0'}
$output=Join-Path (Split-Path -Parent $root) 'dist'
$build=Join-Path $output 'build'
New-Item -ItemType Directory -Path $build -Force|Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path $compiler)){$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
$assemblyInfo=Join-Path $build 'AssemblyInfo.cs'
[IO.File]::WriteAllText($assemblyInfo,'using System.Reflection; [assembly:AssemblyVersion("'+$Version+'.0")] [assembly:AssemblyFileVersion("'+$Version+'.0")] [assembly:AssemblyProduct("TMX Windows Workspace")]')
$bridge=Join-Path $build 'TmuxStyle.Keys.exe'
& $compiler /nologo /target:winexe /platform:anycpu "/out:$bridge" "/win32icon:$(Join-Path $root 'tmux-style.ico')" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll (Join-Path $root 'installer\KeyBridge.cs') $assemblyInfo
if($LASTEXITCODE -ne 0){throw 'Key bridge compilation failed'}
$metrics=Join-Path $build 'TmuxStyle.Metrics.exe'
& $compiler /nologo /target:winexe /platform:anycpu "/out:$metrics" "/win32icon:$(Join-Path $root 'tmux-style.ico')" (Join-Path $root 'installer\Metrics.cs') $assemblyInfo
if($LASTEXITCODE -ne 0){throw 'Metrics helper compilation failed'}
$command=Join-Path $build 'TmuxStyle.Command.exe'
& $compiler /nologo /target:exe /platform:anycpu "/out:$command" "/win32icon:$(Join-Path $root 'tmux-style.ico')" (Join-Path $root 'installer\Command.cs') $assemblyInfo
if($LASTEXITCODE -ne 0){throw 'Command launcher compilation failed'}
$command=Join-Path $build 'TmuxStyle.Command.exe'
& $compiler /nologo /target:exe /platform:anycpu "/out:$command" "/win32icon:$(Join-Path $root 'tmux-style.ico')" (Join-Path $root 'installer\Command.cs') $assemblyInfo
if($LASTEXITCODE -ne 0){throw 'Command launcher compilation failed'}
$payload=Join-Path $build 'payload.zip'
if(Test-Path $payload){Remove-Item -LiteralPath $payload}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
try{
    foreach($name in @('shell.ps1','setup.ps1','restore.ps1','common.ps1','settings.additions.json','profiles.schema.json','install-runner.ps1','test-release.ps1','tmux-style.ico')){
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $name),$name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    }
    foreach($name in @('setup-wezterm.ps1','tmx.ps1','restore-wezterm.ps1','wezterm.lua','wezterm-palettes.json','wezterm-runtime.json','WEZTERM_LICENSE.md','test-wezterm.ps1','test-wezterm-lua.ps1','test-windows-sessions.ps1')){
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $root $name),$name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    }
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path (Split-Path -Parent $root) 'VERSION'),'VERSION',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$metrics,'TmuxStyle.Metrics.exe',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$command,'TmuxStyle.Command.exe',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$command,'TmuxStyle.Command.exe',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$bridge,'TmuxStyle.Keys.exe',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
}finally{$archive.Dispose()}
$installer=Join-Path $output ('TMX-Setup-'+$Version+'.exe')
& $compiler /nologo /target:winexe /platform:anycpu "/out:$installer" "/win32icon:$(Join-Path $root 'tmux-style.ico')" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll "/resource:$payload,TmuxStyle.Payload.zip" "/win32manifest:$(Join-Path $root 'installer\app.manifest')" (Join-Path $root 'installer\Setup.cs') $assemblyInfo
if($LASTEXITCODE -ne 0){throw 'Setup compilation failed'}
if($RunTests){
    $report=Join-Path $output 'self-test.json'
    $process=Start-Process -FilePath $installer -ArgumentList ('--self-test --report "'+$report+'"') -PassThru -Wait -WindowStyle Hidden
    if($process.ExitCode -ne 0){if(Test-Path ($report+'.log')){Get-Content ($report+'.log')};throw 'Packaged installer self-test failed'}
    $result=[IO.File]::ReadAllText($report)|ConvertFrom-Json
    if(-not $result.passed){throw 'Invalid self-test report'}
    Write-Output ('PASS: packaged EXE tests on PowerShell '+$result.powershell)
}
$hash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'),$hash+'  '+[IO.Path]::GetFileName($installer)+"`n")
Write-Output ('Built: '+$installer)
