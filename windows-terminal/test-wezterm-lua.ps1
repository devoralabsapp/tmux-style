param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$WezTermExecutable,[string]$ReportFile)
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('TmuxStyleLua-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
Copy-Item -LiteralPath (Join-Path $SourceDirectory 'wezterm-palettes.json') -Destination $fixture
[IO.File]::WriteAllText((Join-Path $fixture 'backend.json'),'{"startingDirectory":"C:/","executable":"wezterm.exe"}')
$template=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'wezterm.lua')).Replace("`r`n","`n")
# Execute the actual status/layout/F12 functions with controlled native API inputs
# inside WezTerm's real Lua interpreter. No GUI or production files are touched.
$assertions=@'
local w = { overrides={}, zoomed=false, prefix=false, width=1400 }
local pane = {}
local tab = {}
function pane:pane_id() return 41 end
function tab:panes() return {pane} end
function w:mux_window() return {tabs=function() return {tab} end} end
function tab:panes_with_info() return {{is_zoomed=w.zoomed}} end
function tab:get_size() return {cols=math.floor(w.width/9)} end
function w:get_config_overrides() return self.overrides end
function w:set_config_overrides(o) self.overrides=o end
function w:active_workspace() return 'TEST' end
function w:leader_is_active() return self.prefix end
function w:active_tab() return tab end
function w:get_dimensions() return {pixel_width=self.width} end
function w:set_left_status(text) self.left=text end
function w:set_right_status(text) self.right=text end
local function sample(timestamp)
  local f=assert(io.open(root .. '/metrics.json','w'))
  f:write(wezterm.json_encode {timestamp=timestamp,cpu=42,ram=63});f:close()
end
sample(os.time()); status_handler(w,pane)
assert(w.right:find('CPU 42%%') and w.right:find('RAM 63%%'), 'Live counters missing')
assert(w.right:find(wezterm.strftime('%d/%m/%Y'),1,true), 'Date missing')
assert(w.right:find(wezterm.hostname(),1,true), 'Host missing')
assert(w.left:find('CTRL%-A'), 'Normal mode missing')
pass_through(w,pane);status_handler(w,pane)
assert(w.left:find('OFF'), 'Pass-through indicator missing')
assert(w.overrides.disable_default_key_bindings and w.overrides.leader.key=='F24' and #w.overrides.keys==2, 'Pass-through still captures defaults/leader')
resume(w,pane);status_handler(w,pane)
assert(w.overrides.leader==nil and w.overrides.keys==nil and w.overrides.disable_default_key_bindings==nil, 'Resume did not restore defaults')
w.zoomed=true;w.prefix=true;status_handler(w,pane)
assert(w.left:find('PREFIX ZOOM',1,true), 'Prefix/zoom state missing')
w.width=800;status_handler(w,pane)
assert(not w.right:find(wezterm.hostname(),1,true), 'Narrow status not compact')
sample(0);status_handler(w,pane)
assert(w.right:find('CPU %-%-') and w.right:find('RAM %-%-'), 'Stale counters displayed as fresh')
-- All six themes recolor the same window, keep OFF/zoom/chrome overrides,
-- publish prompt state, and configure new panes without spawning anything.
w.overrides.enable_tab_bar=false
pass_through(w,pane)
local other = {get_config_overrides=function() return {} end}
apply_theme(w,pane,'TmuxStyleTheme','paper')
for _, name in ipairs {'black','paper','neon','ember','midnight','aurora'} do
  apply_theme(w,pane,'TmuxStyleTheme',name)
  assert(window_theme(w)==name and window_theme(other)==theme, 'Theme leaked into another window')
  assert(w.overrides.colors.background==palettes[name].colors.background, 'Pane background stale')
  assert(w.overrides.colors.tab_bar.active_tab.bg_color==palettes[name].accent, 'Tab palette stale')
  assert(w.overrides.disable_default_key_bindings and w.overrides.enable_tab_bar==false, 'Theme reset OFF/chrome state')
  assert(w.overrides.default_prog[5]:find('-Theme '..name,1,true), 'New pane theme stale')
  local f=assert(io.open(root .. '/window-theme-'..gui_pid..'-41.json','r'))
  local state=wezterm.json_parse(f:read('*a'));f:close()
  assert(state.theme==name, 'Existing prompt theme stale')
  assert(palettes[name].colors.tab_bar==nil, 'Shared palette was mutated')
end
local previous=w.overrides
apply_theme(w,pane,'TmuxStyleTheme','invalid')
apply_theme(w,pane,'other-var','black')
assert(w.overrides==previous, 'Unrelated/invalid signal changed theme')
local first, right = {}, {}
function pane:get_current_working_dir() return {file_path='/C:/test space'} end
function w:mux_window() return {spawn_tab=function(_,cmd) assert(cmd.cwd=='C:/test space');return tab,first end} end
function first:split(cmd) assert(cmd.direction=='Right' and cmd.size==0.35);return right end
function right:split(cmd) assert(cmd.direction=='Bottom' and cmd.size==0.5) end
function first:activate() self.activated=true end
layout(w,pane);assert(first.activated, 'Layout focus missing')
local f=assert(io.open(root .. '/lua-passed.json','w'));f:write('true');f:close()
'@
$themes=@()
foreach($theme in 'aurora','midnight','ember','paper','neon','black'){
    $config=Join-Path $fixture 'test.lua'
    $passed=Join-Path $fixture 'lua-passed.json'
    if(Test-Path -LiteralPath $passed){Remove-Item -LiteralPath $passed}
    $text=$template.Replace('__THEME__',$theme).Replace("wezterm.on('update-status', function(window, pane)","local status_handler = function(window, pane)").Replace("end)`nreturn config",("end`n"+$assertions+"`nreturn config"))
    [IO.File]::WriteAllText($config,$text,[Text.UTF8Encoding]::new($false))
    $keys=@(& $WezTermExecutable --config-file $config show-keys 2>&1)
    if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $passed) -or -not($keys|Where-Object {$_ -eq "Leader: Char('a') CTRL 2s"})){throw ('WezTerm Lua validation failed for '+$theme+': '+($keys -join "`n"))}
    $themes+=$theme
}
$report=[pscustomobject]@{passed=$true;runtime=(& $WezTermExecutable --version);themes=$themes;checks=@('native Lua configuration and key action parsing; two-second leader','live theme resets all colors without opening windows; other windows independent','theme retains OFF/zoom/chrome state and updates existing/new pane prompt metadata','status: CPU/RAM/hostname/date','prefix/zoom/off states','F12 disables leader and defaults; resume restores them','narrow bar and stale sample handling','3-pane layout preserves cwd and focus');guiStarted=$false}
if($ReportFile){[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
Write-Output 'PASS: six themes parsed by real WezTerm; status, F12, layout callbacks verified.'
