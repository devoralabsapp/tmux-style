param(
    [ValidateSet('aurora','midnight','ember','paper','neon')]
    [string]$Theme = 'aurora',
    [switch]$NoBanner,
    [switch]$NoKeyBridge
)

$global:TmuxStyleTheme = $Theme
$keyBridge=Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\TmuxStyle.Keys.exe'
if(-not $NoKeyBridge -and $env:WT_SESSION -and (Test-Path -LiteralPath $keyBridge)){
    Start-Process -FilePath $keyBridge -WindowStyle Hidden
}
$global:TmuxStyleThemeNames = @{
    aurora='Aurora'; midnight='Midnight'; ember='Ember'; paper='Paper'; neon='Neon'
}
$global:TmuxStylePalette = switch ($Theme) {
    'aurora' { @{Accent='Green';Detail='Magenta';Muted='DarkGray';Text='Gray'} }
    'ember' { @{Accent='Yellow';Detail='DarkYellow';Muted='DarkGray';Text='Gray'} }
    'paper' { @{Accent='Black';Detail='DarkGreen';Muted='DarkGray';Text='Black'} }
    'neon' { @{Accent='Magenta';Detail='Cyan';Muted='DarkGray';Text='Gray'} }
    default { @{Accent='Cyan';Detail='Magenta';Muted='DarkGray';Text='Gray'} }
}

function global:Get-TmuxStyleTerminal {
    $terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($terminal) { return $terminal.Source }
    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $aliasPath) { return $aliasPath }
    throw 'Windows Terminal (wt.exe) was not found.'
}

function global:Open-TmuxStyleWorkspace {
    param([string]$Path = $PWD.Path)
    $terminal = Get-TmuxStyleTerminal
    $profileName = 'Tmux Style - ' + $global:TmuxStyleThemeNames[$global:TmuxStyleTheme]
    & $terminal -w new new-tab -p $profileName -d $Path ';' split-pane -V -s 0.35 -p $profileName -d $Path ';' split-pane -H -s 0.5 -p $profileName -d $Path ';' move-focus first
}

function global:Set-TmuxStyleTheme {
    param([ValidateSet('aurora','midnight','ember','paper','neon')][string]$Name = 'aurora')
    $terminal = Get-TmuxStyleTerminal
    $profileName = 'Tmux Style - ' + $global:TmuxStyleThemeNames[$Name]
    & $terminal -w 0 new-tab -p $profileName -d $PWD.Path
}

function global:Show-TmuxStyleHelp {
    Write-Host ''
    Write-Host '  TMUX STYLE / WINDOWS' -ForegroundColor $global:TmuxStylePalette.Accent
    Write-Host '  Ctrl+Alt+V          split right'
    Write-Host '  Ctrl+Alt+H          split below'
    Write-Host '  Alt+Arrow           focus pane'
    Write-Host '  Alt+Shift+Arrow     resize pane'
    Write-Host '  Ctrl+Shift+Z        zoom / restore pane'
    Write-Host '  Ctrl+Alt+W          new tab with 3 panes'
    Write-Host '  Ctrl+Shift+T / W    new tab / close pane'
    Write-Host '  Ctrl+Tab            next tab'
    Write-Host '  workspace           open a new 3-pane window'
    Write-Host '  theme neon          open a tab in another theme'
    Write-Host '  Show-TmuxStyleHelp  show these shortcuts'
    Write-Host ''
}

function global:prompt {
    $previousSuccess = $?
    $previousExitCode = $global:LASTEXITCODE
    $palette = $global:TmuxStylePalette
    $path = $PWD.Path
    if ($HOME -and $path.StartsWith($HOME,[StringComparison]::OrdinalIgnoreCase)) {
        if ($path.Length -eq $HOME.Length -or $path[$HOME.Length] -eq '\') {
            $path = '~' + $path.Substring($HOME.Length)
        }
    }
    $branch = $null
    try {
        if ($PWD.Provider.Name -eq 'FileSystem' -and (Get-Command git.exe -ErrorAction SilentlyContinue)) {
            $branch = & git.exe --no-optional-locks -C $PWD.ProviderPath symbolic-ref --quiet --short HEAD 2>$null
            if (-not $branch) {
                $branch = & git.exe --no-optional-locks -C $PWD.ProviderPath rev-parse --short HEAD 2>$null
            }
        }
        $leaf = Split-Path -Leaf $PWD.Path
        if (-not $leaf) { $leaf = $PWD.Path }
        $Host.UI.RawUI.WindowTitle = $global:TmuxStyleThemeNames[$global:TmuxStyleTheme] + ' | ' + $leaf
        if ($env:WT_SESSION -and $PWD.Provider.Name -eq 'FileSystem') {
            $escape = [char]27
            # Native Terminal working-directory reporting for duplicate panes.
            $safePath = $PWD.ProviderPath -replace '[\x00-\x1f"\x7f]', ''
            Write-Host -NoNewline ($escape + ']9;9;"' + $safePath + '"' + $escape + '\')
        }
    } catch {
        # A prompt must remain usable in directories without Git or a console host.
    } finally {
        $global:LASTEXITCODE = $previousExitCode
    }
    Write-Host ''
    Write-Host ('  ' + $global:TmuxStyleThemeNames[$global:TmuxStyleTheme].ToUpper()) -NoNewline -ForegroundColor $palette.Accent
    Write-Host ('  ' + $path) -NoNewline -ForegroundColor $palette.Text
    if ($branch) { Write-Host ('  [' + $branch + ']') -NoNewline -ForegroundColor $palette.Detail }
    if (-not $previousSuccess) { Write-Host '  !' -NoNewline -ForegroundColor Red }
    Write-Host ''
    return '  > '
}

if (-not (Get-Command workspace -ErrorAction SilentlyContinue)) {
    Set-Alias -Name workspace -Value Open-TmuxStyleWorkspace -Scope Global
}
if (-not (Get-Command theme -ErrorAction SilentlyContinue)) {
    Set-Alias -Name theme -Value Set-TmuxStyleTheme -Scope Global
}

if (Get-Module PSReadLine) {
    $options = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
    if ($options.Parameters.ContainsKey('PredictionSource')) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
    }
    $syntaxColors = @{
        Command=$global:TmuxStylePalette.Accent
        Parameter=$global:TmuxStylePalette.Detail
        String='Green'
        Comment='DarkGray'
        Error='Red'
    }
    Set-PSReadLineOption -Colors $syntaxColors -ErrorAction SilentlyContinue
}
if (-not $NoBanner) {
    Write-Host ''
    Write-Host ('  ' + $global:TmuxStyleThemeNames[$Theme].ToUpper() + ' / WINDOWS WORKSPACE') -ForegroundColor $global:TmuxStylePalette.Accent
    Write-Host '  Tab. Split. Focus.' -ForegroundColor $global:TmuxStylePalette.Detail
    Write-Host '  Ctrl+Alt+W: 3 panes   |   Show-TmuxStyleHelp: shortcuts' -ForegroundColor $global:TmuxStylePalette.Muted
}
