param(
    [ValidateSet('aurora','midnight','ember','paper','neon','black','code','hacker')]
    [string]$Theme = 'aurora',
    [switch]$NoBanner,
    [switch]$NoKeyBridge
)

$global:TmuxStyleTheme = $Theme
$global:TmuxStyleBackend = if($env:TMUX_STYLE_BACKEND -eq 'wezterm'){'wezterm'}else{'windows-terminal'}
$global:TmuxStyleAssetDirectory = if($global:TmuxStyleBackend -eq 'wezterm'){$env:TMUX_STYLE_ASSETS}else{Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows'}
$global:TmuxStyleStateDirectory = $global:TmuxStyleAssetDirectory.TrimEnd('\','/')+'-state'
$keyBridge=Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\TmuxStyle.Keys.exe'
if(-not $NoKeyBridge -and $global:TmuxStyleBackend -eq 'windows-terminal' -and $env:WT_SESSION -and (Test-Path -LiteralPath $keyBridge)){
    Start-Process -FilePath $keyBridge -WindowStyle Hidden
}
if(-not $NoKeyBridge -and $global:TmuxStyleBackend -eq 'wezterm'){
    $collector=Join-Path $global:TmuxStyleAssetDirectory 'TmuxStyle.Metrics.exe'
    if(Test-Path -LiteralPath $collector){Start-Process -FilePath $collector -ArgumentList ('--watch "'+(Join-Path $global:TmuxStyleStateDirectory 'metrics.json')+'"') -WindowStyle Hidden}
}
$global:TmuxStyleThemeNames = @{
    aurora='Aurora'; midnight='Midnight'; ember='Ember'; paper='Paper'; neon='Neon'; black='Command Line'; code='Code Spectrum'; hacker='Hacker Matrix'
}
function global:Update-TmuxStyleShellTheme {
    param([ValidateSet('aurora','midnight','ember','paper','neon','black','code','hacker')][string]$Name)
    $global:TmuxStyleTheme = $Name
    $global:TmuxStylePalette = switch ($Name) {
    'aurora' { @{Accent='Green';Detail='Magenta';Muted='DarkGray';Text='Gray'} }
    'ember' { @{Accent='Yellow';Detail='DarkYellow';Muted='DarkGray';Text='Gray'} }
    'paper' { @{Accent='Black';Detail='DarkGreen';Muted='DarkGray';Text='Black'} }
    'neon' { @{Accent='Magenta';Detail='Cyan';Muted='DarkGray';Text='Gray'} }
    'black' { @{Accent='White';Detail='Gray';Muted='DarkGray';Text='Gray'} }
    'code' { @{Accent='Cyan';Detail='Magenta';Muted='DarkGray';Text='Gray'} }
    'hacker' { @{Accent='Green';Detail='DarkGreen';Muted='DarkGray';Text='Gray'} }
    default { @{Accent='Cyan';Detail='Magenta';Muted='DarkGray';Text='Gray'} }
    }
    if(Get-Module PSReadLine){
        $syntax=@{Command=$global:TmuxStylePalette.Accent;Parameter=$global:TmuxStylePalette.Detail;String='Green';Variable=$global:TmuxStylePalette.Text;Type=$global:TmuxStylePalette.Detail;Number='Cyan';Operator=$global:TmuxStylePalette.Text;Keyword=$global:TmuxStylePalette.Accent;Member=$global:TmuxStylePalette.Text;Comment='DarkGray';Error='Red'}
        if($Name -eq 'code'){
            $syntax=@{Command='Yellow';Parameter='DarkCyan';String='DarkYellow';Variable='Blue';Type='Cyan';Number='Green';Operator='Gray';Keyword='Magenta';Member='Yellow';Comment='DarkGray';Error='Red'}
        }elseif($Name -eq 'hacker'){
            $syntax=@{Command='Green';Parameter='Cyan';String='DarkYellow';Variable='Cyan';Type='DarkCyan';Number='Yellow';Operator='DarkGreen';Keyword='Green';Member='Green';Comment='DarkGray';Error='Red'}
        }
        # Reset to the theme's foreground/background before reversing selection.
        # This avoids inherited light-on-light or dark-on-dark selection colors.
        $syntax.Selection = [string][char]27+'[0;7m'
        $syntax.Emphasis = $global:TmuxStylePalette.Detail
        $syntax.ContinuationPrompt = $global:TmuxStylePalette.Muted
        Set-PSReadLineOption -Colors $syntax -ErrorAction SilentlyContinue
    }
}
function global:Get-TmuxStyleThemeStatePath {
    if($env:TMX_SESSION_KEY -match '^[a-f0-9]{16}$'){
        return Join-Path $global:TmuxStyleStateDirectory ('session-'+$env:TMX_SESSION_KEY+'.json')
    }
    $guiProcessId=$env:TMUX_STYLE_GUI_PID
    if(-not $guiProcessId -and $env:WEZTERM_UNIX_SOCKET -match 'gui-sock-(\d+)$'){$guiProcessId=$Matches[1]}
    if($guiProcessId -match '^\d+$' -and $env:WEZTERM_PANE -match '^\d+$'){
        return Join-Path $global:TmuxStyleStateDirectory ('window-theme-'+$guiProcessId+'-'+$env:WEZTERM_PANE+'.json')
    }
}
function global:Sync-TmuxStyleShellTheme {
    if($global:TmuxStyleBackend -ne 'wezterm'){return}
    try{
        $statePath=Get-TmuxStyleThemeStatePath
        if($statePath -and (Test-Path -LiteralPath $statePath)){
            $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
            if($global:TmuxStyleThemeNames.ContainsKey($state.theme) -and $state.theme -ne $global:TmuxStyleTheme){Update-TmuxStyleShellTheme $state.theme}
        }
    }catch{ } # A prompt remains usable during a concurrent state write.
}
Update-TmuxStyleShellTheme $Theme
Sync-TmuxStyleShellTheme

function global:Get-TmuxStyleTerminal {
    if($global:TmuxStyleBackend -eq 'wezterm'){
        $backend=[IO.File]::ReadAllText((Join-Path $global:TmuxStyleAssetDirectory 'backend.json'))|ConvertFrom-Json
        return $backend.executable
    }
    $terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($terminal) { return $terminal.Source }
    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $aliasPath) { return $aliasPath }
    throw 'Windows Terminal (wt.exe) was not found.'
}

function global:Open-TmuxStyleWorkspace {
    param([string]$Path = $PWD.Path)
    $terminal = Get-TmuxStyleTerminal
    if($global:TmuxStyleBackend -eq 'wezterm'){
        Push-Location -LiteralPath $Path
        try{tmx new ('workspace-'+[Guid]::NewGuid().ToString('N').Substring(0,8)) --theme $global:TmuxStyleTheme}finally{Pop-Location}
        return
    }
    $profileName = 'Tmux Style - ' + $global:TmuxStyleThemeNames[$global:TmuxStyleTheme]
    & $terminal -w new new-tab -p $profileName -d $Path ';' split-pane -V -s 0.35 -p $profileName -d $Path ';' split-pane -H -s 0.5 -p $profileName -d $Path ';' move-focus first
}

function global:Set-TmuxStyleTheme {
    param([ValidateSet('aurora','midnight','ember','paper','neon','black','code','hacker')][string]$Name = 'aurora')
    if($env:TMX_SESSION -and $PSBoundParameters.Count -eq 0){tmx theme;return}
    if($global:TmuxStyleBackend -eq 'wezterm'){
        $statePath=Get-TmuxStyleThemeStatePath
        if($statePath){
            $state=@{theme=$Name}
            if($env:TMX_SESSION){$state.name=$env:TMX_SESSION}
            [IO.File]::WriteAllText($statePath,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
        Update-TmuxStyleShellTheme $Name
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Name))
        Write-Host -NoNewline ([string][char]27+']1337;SetUserVar=TmuxStyleTheme='+$encoded+[char]7)
        return
    }
    $terminal = Get-TmuxStyleTerminal
    $profileName = 'Tmux Style - ' + $global:TmuxStyleThemeNames[$Name]
    & $terminal -w 0 new-tab -p $profileName -d $PWD.Path
}

function global:Show-TmuxStyleHelp {
    Write-Host ''
    Write-Host '  TMUX STYLE / WINDOWS' -ForegroundColor $global:TmuxStylePalette.Accent
    Write-Host '  Ctrl-a then | / -  split right / below'
    Write-Host '  Ctrl-a then c / r  new tab / rename tab'
    Write-Host '  Ctrl-a then z / x  zoom pane / close pane'
    Write-Host '  F12                 toggle pass-through for remote tmux'
    Write-Host '  Ctrl+Alt+V          split right'
    Write-Host '  Ctrl+Alt+H          split below'
    Write-Host '  Alt+Arrow           focus pane'
    Write-Host '  Alt+Shift+Arrow     resize pane'
    Write-Host '  Ctrl+Shift+Z        zoom / restore pane'
    Write-Host '  Ctrl+Alt+W          new tab with 3 panes'
    Write-Host '  Ctrl+Shift+T / W    new tab / close pane'
    Write-Host '  Ctrl+Tab            next tab'
    Write-Host '  workspace           open a new 3-pane window'
    Write-Host '  tmx new work [-d]    create a persistent WezTerm session'
    Write-Host '  tmx list / attach work / detach    manage sessions; Ctrl-a d detaches'
    Write-Host '  theme neon          recolor this WezTerm window / open a Terminal tab'
    Write-Host '  theme code / hacker  Code Spectrum / Hacker Matrix'
    Write-Host '  Show-TmuxStyleHelp  show these shortcuts'
    Write-Host ''
}

function global:tmx {
    $assets=if($global:TmuxStyleBackend -eq 'wezterm'){$global:TmuxStyleAssetDirectory}else{Join-Path $env:LOCALAPPDATA 'TmuxStyleWindows\wezterm'}
    $cli=Join-Path $assets 'tmx.ps1'
    if(-not(Test-Path -LiteralPath $cli)){throw 'Install the TMX WezTerm backend to use persistent sessions on Windows.'}
    & ([scriptblock]::Create([IO.File]::ReadAllText($cli))) -AssetDirectory $assets -Arguments $args
}

function global:prompt {
    $previousSuccess = $?
    $previousExitCode = $global:LASTEXITCODE
    Sync-TmuxStyleShellTheme
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
        if ($global:TmuxStyleBackend -eq 'wezterm' -and $PWD.Provider.Name -eq 'FileSystem') {
            $escape = [char]27
            $uri = [Uri]::new($PWD.ProviderPath + [IO.Path]::DirectorySeparatorChar)
            Write-Host -NoNewline ($escape + ']7;' + $uri.AbsoluteUri + $escape + '\')
        } elseif ($env:WT_SESSION -and $PWD.Provider.Name -eq 'FileSystem') {
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
    Update-TmuxStyleShellTheme $global:TmuxStyleTheme
}
if (-not $NoBanner) {
    Write-Host ''
    Write-Host ('  ' + $global:TmuxStyleThemeNames[$global:TmuxStyleTheme].ToUpper() + ' / WINDOWS WORKSPACE') -ForegroundColor $global:TmuxStylePalette.Accent
    Write-Host '  Tab. Split. Focus.' -ForegroundColor $global:TmuxStylePalette.Detail
    Write-Host '  Ctrl+Alt+W: 3 panes   |   Show-TmuxStyleHelp: shortcuts' -ForegroundColor $global:TmuxStylePalette.Muted
}
