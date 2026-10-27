-- Loaded only through Tmux Style's explicit --config-file shortcut.
local wezterm = require 'wezterm'
local act = wezterm.action
local root = wezterm.config_dir
local function read_json(path)
  local file = io.open(path, 'r')
  if not file then return nil end
  local text = file:read '*a'; file:close()
  local ok, value = pcall(wezterm.json_parse, text)
  if ok then return value end
end
local backend = assert(read_json(root .. '/backend.json'), 'Reinstall the Tmux Style WezTerm workspace: backend.json is missing')
local palettes = assert(read_json(root .. '/wezterm-palettes.json'))
local theme = '__THEME__'
local gui_pid = tostring(wezterm.procinfo.pid())
local function shell_command(name)
  return { 'powershell.exe', '-NoLogo', '-NoExit', '-Command',
    ". ([scriptblock]::Create([IO.File]::ReadAllText('" .. root:gsub("'", "''") .. "/shell.ps1'))) -Theme " .. name }
end
local function shell_environment(name)
  return { TMUX_STYLE_BACKEND = 'wezterm', TMUX_STYLE_ASSETS = root, TMUX_STYLE_GUI_PID = gui_pid, TMUX_STYLE_THEME = name }
end
local function theme_colors(name)
  local p = palettes[name]
  local colors = wezterm.json_parse(wezterm.json_encode(p.colors))
  colors.tab_bar = {
    background = p.bar,
    active_tab = { bg_color = p.accent, fg_color = p.bar, intensity = 'Bold' },
    inactive_tab = { bg_color = p.bar, fg_color = p.muted },
    inactive_tab_hover = { bg_color = p.surface, fg_color = p.fg },
  }
  return colors
end
local function window_theme(window)
  local o = window:get_config_overrides() or {}
  local name = o.set_environment_variables and o.set_environment_variables.TMUX_STYLE_THEME
  return palettes[name] and name or theme
end
local published_themes = {}
local function publish_theme(window, name)
  -- Separate files per GUI process and pane keep other windows independent.
  for _, tab in ipairs(window:mux_window():tabs()) do
    for _, pane in ipairs(tab:panes()) do
      local path = root .. '/window-theme-' .. gui_pid .. '-' .. pane:pane_id() .. '.json'
      if published_themes[path] ~= name then
        local file = io.open(path, 'w')
        if file then file:write(wezterm.json_encode { theme = name }); file:close(); published_themes[path] = name end
      end
    end
  end
end
local function apply_theme(window, pane, name, value)
  if name ~= 'TmuxStyleTheme' or not palettes[value] then return end
  if window_theme(window) ~= value then
    local o = window:get_config_overrides() or {}
    o.colors = theme_colors(value)
    o.default_prog = shell_command(value)
    o.set_environment_variables = shell_environment(value)
    window:set_config_overrides(o)
  end
  publish_theme(window, value)
end
wezterm.on('user-var-changed', apply_theme)
local config = wezterm.config_builder()
config.default_prog = shell_command(theme)
config.default_cwd = backend.startingDirectory
config.default_workspace = 'TMUX'
config.set_environment_variables = shell_environment(theme)
config.font = wezterm.font_with_fallback { 'Cascadia Mono', 'Consolas' }
config.font_size = 11
config.initial_cols = 150
config.initial_rows = 38
config.window_padding = { left = 14, right = 14, top = 10, bottom = 6 }
config.scrollback_lines = 20000
config.audible_bell = 'Disabled'
config.check_for_updates = false
config.show_update_window = false
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 22
config.show_new_tab_button_in_tab_bar = false
config.status_update_interval = 1000
config.colors = theme_colors(theme)
config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 2000 }
local function rename(description, callback)
  return act.PromptInputLine { description = description, action = wezterm.action_callback(function(window, pane, line)
    if line then callback(window, pane, line) end
  end) }
end
local function layout(window, pane)
  local cwd = pane:get_current_working_dir()
  local path = cwd and cwd.file_path or nil
  -- OSC 7 URLs expose /C:/...; Windows CreateProcess needs C:/....
  if path then path = path:gsub('^/(%a:)', '%1') end
  local tab, first = window:mux_window():spawn_tab { cwd = path }
  local right = first:split { direction = 'Right', size = 0.35 }
  right:split { direction = 'Bottom', size = 0.5 }
  first:activate()
end
local function pass_through(window, pane)
  -- Overrides survive configuration reloads. Disable leader and defaults too,
  -- so Ctrl-a and native shortcuts reach remote tmux unchanged.
  local overrides = window:get_config_overrides() or {}
  overrides.leader = { key = 'F24', mods = 'CTRL|ALT|SHIFT' }
  overrides.disable_default_key_bindings = true
  overrides.keys = {
    { key = 'F12', action = act.EmitEvent 'tmux-style-resume' },
    { key = 'DownArrow', mods = 'SHIFT', action = act.EmitEvent 'tmux-style-resume' },
  }
  window:set_config_overrides(overrides)
end
local function resume(window, pane)
  local overrides = window:get_config_overrides() or {}
  overrides.leader = nil; overrides.keys = nil; overrides.disable_default_key_bindings = nil
  window:set_config_overrides(overrides)
end
wezterm.on('tmux-style-resume', resume)
config.keys = {
  { key = 'F12', action = wezterm.action_callback(pass_through) },
  { key = 'UpArrow', mods = 'SHIFT', action = wezterm.action_callback(pass_through) },
  { key = 'DownArrow', mods = 'SHIFT', action = wezterm.action_callback(resume) },
  { key = 'a', mods = 'LEADER|CTRL', action = act.SendKey { key = 'a', mods = 'CTRL' } },
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = '|', mods = 'LEADER|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'r', mods = 'LEADER', action = rename('Rename tab (empty resets)', function(w, _, s) w:active_tab():set_title(s) end) },
  { key = 'R', mods = 'LEADER|SHIFT', action = rename('Rename workspace', function(w, _, s)
      if s ~= '' then wezterm.mux.rename_workspace(w:active_workspace(), s) end
    end) },
  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },
  { key = 'X', mods = 'LEADER|SHIFT', action = act.CloseCurrentTab { confirm = true } },
  { key = 'Tab', mods = 'LEADER', action = act.ActivateLastTab },
  { key = 'o', mods = 'LEADER|CTRL', action = act.RotatePanes 'Clockwise' },
  { key = '[', mods = 'LEADER', action = act.ActivateCopyMode },
  { key = ']', mods = 'LEADER', action = act.PasteFrom 'Clipboard' },
  { key = 'r', mods = 'LEADER|CTRL', action = act.ReloadConfiguration },
  { key = 's', mods = 'LEADER|CTRL', action = wezterm.action_callback(function(w)
      local o = w:get_config_overrides() or {}; o.enable_tab_bar = not (o.enable_tab_bar ~= false); w:set_config_overrides(o)
    end) },
  { key = 'w', mods = 'CTRL|ALT', action = wezterm.action_callback(layout) },
  { key = 'v', mods = 'CTRL|ALT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL|ALT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 't', mods = 'CTRL', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'LeftArrow', mods = 'SHIFT', action = act.ActivateTabRelative(-1) },
  { key = 'RightArrow', mods = 'SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = act.MoveTabRelative(-1) },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.MoveTabRelative(1) },
}
for _, direction in ipairs { 'Left', 'Right', 'Up', 'Down' } do
  table.insert(config.keys, { key = direction .. 'Arrow', mods = 'LEADER', action = act.ActivatePaneDirection(direction) })
  table.insert(config.keys, { key = direction .. 'Arrow', mods = 'ALT', action = act.ActivatePaneDirection(direction) })
  table.insert(config.keys, { key = direction .. 'Arrow', mods = 'LEADER|CTRL', action = act.AdjustPaneSize { direction, 3 } })
  table.insert(config.keys, { key = direction .. 'Arrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { direction, 3 } })
end
for i = 1, 9 do table.insert(config.keys, { key = tostring(i), mods = 'LEADER', action = act.ActivateTab(i - 1) }) end

wezterm.on('gui-startup', function(cmd)
  local _, first = wezterm.mux.spawn_window(cmd or {})
  local right = first:split { direction = 'Right', size = 0.35 }
  right:split { direction = 'Bottom', size = 0.5 }
  first:activate()
end)
wezterm.on('format-tab-title', function(tab, _, _, _, _, max_width)
  local title = tab.tab_title ~= '' and tab.tab_title or tab.active_pane.title
  title = title:gsub('[%c]', ' ')
  return ' ' .. (tab.tab_index + 1) .. ' ' .. wezterm.truncate_right(title, math.max(1, max_width - 5)) .. ' '
end)
local last_sample
wezterm.on('update-status', function(window, pane)
  local selected_theme = window_theme(window)
  local p = palettes[selected_theme]
  publish_theme(window, selected_theme)
  local overrides = window:get_config_overrides() or {}
  local off = overrides.disable_default_key_bindings == true
  local mode = off and 'OFF' or (window:leader_is_active() and 'PREFIX' or 'CTRL-A')
  for _, info in ipairs(window:active_tab():panes_with_info()) do
    if info.is_zoomed then mode = mode .. ' ZOOM'; break end
  end
  window:set_left_status(wezterm.format {
    { Background = { Color = p.surface } }, { Foreground = { Color = p.accent } },
    { Attribute = { Intensity = 'Bold' } }, { Text = ' ' .. window:active_workspace() .. ' / ' .. mode .. ' ' },
  })
  local sample = read_json(root .. '/metrics.json') or last_sample
  last_sample = sample
  local cpu, ram = '--', '--'
  if sample and sample.timestamp and os.time() - sample.timestamp < 10 then
    cpu = string.format('%.0f%%', sample.cpu)
    ram = string.format('%.0f%%', sample.ram)
  end
  local host = wezterm.hostname():gsub('[%c]', '')
  local text = ' CPU ' .. cpu .. '  RAM ' .. ram .. ' | ' .. host .. ' | ' .. wezterm.strftime('%d/%m/%Y %H:%M:%S') .. ' '
  -- Use all tab columns, rather than the focused pane or pixel/DPI size.
  if window:active_tab():get_size().cols < 110 then text = ' CPU ' .. cpu .. ' RAM ' .. ram .. ' | ' .. wezterm.strftime('%H:%M') .. ' ' end
  window:set_right_status(wezterm.format { { Background = { Color = p.bar } }, { Foreground = { Color = p.fg } }, { Text = text } })
end)
return config
