# TMX v1.7.0

- Install the Windows EXE once with WezTerm selected, then run `tmx` directly from PowerShell or CMD. The console launcher preserves arguments and Unicode paths without editing shell profiles or execution policy.
- Added named Windows sessions: `tmx new NAME [--theme NAME] [-d]`, `list` / `ls`, `attach [NAME]` / `attach -t NAME`, `detach`, `theme`, `themes`, `metrics`, `restore`, `uninstall`, `help` and `version`. Bare `tmx` creates or reattaches the default workspace.
- Native WezTerm mux servers keep pane processes and running jobs alive after detach or GUI close. Reattach reconnects to the same session; sessions do not survive Windows shutdown. Existing pre-1.7 windows remain usable but must be replaced by new sessions to gain persistence.
- Ctrl-a d detaches; Ctrl-a t and bare `tmx theme` open a native theme picker. Session themes survive detach/reattach; `tmx theme NAME --session SESSION` and `--default` match the Unix command style.
- Removed the blocking installation-success popup. Completion and command guidance appear inline in the installer.
- Added safe Windows restore/uninstall guards for running sessions and edited files, with recovery backups retained. Legacy Windows Terminal behavior and Unix tmux configurations remain available.

Downloads: `TMX-Setup-1.7.0.exe`, `tmx-linux-1.7.0.tar.gz`, `tmx-macos-1.7.0.tar.gz`, source, SHA-256 checksums, theme contrast report and platform validation reports.

## v1.6.0 historical notes

- Renamed the Linux/macOS command to `tmx`. The `tmux-style` command, existing data paths and socket remain compatible with running sessions. Installer refuses collisions with an unrelated `tmx` command.
- Added `tmx uninstall` to deactivate the tool and both owned commands across upgrades, retaining recovery backups and original user launchers. It refuses active TMX sessions or edited commands; unrelated tmux servers and dotfiles remain in place. `tmx restore` still rolls back only the most recent installation.
- Fixed low-contrast Paper warning/error/status colors and Windows Paper prompt text, improved Code OFF text, Hacker comments and all pane dividers. Native menus, PSReadLine selections and WezTerm copy/search highlights now use explicit readable colors.
- Added a build-time contrast audit covering native tmux, eight Unix themes and eight Windows palettes, plus labeled vector samples and the downloadable `theme-contrast.json` report. Text targets 4.5:1, pane dividers 3:1, for the shipped tool-controlled RGB pairs.
- Renamed distribution files to `tmx-linux-1.6.0.tar.gz`, `tmx-macos-1.6.0.tar.gz` and `TMX-Setup-1.6.0.exe`. GitHub repository/downloads for older releases stay available.

After installing, reload open Unix sessions with Ctrl-a Ctrl-r and source `. "$TMUX_STYLE_HOME/shell/commands.sh"` in old Bash/Zsh panes to load `tmx` without restarting them. To uninstall, exit the TMX sessions and run `tmx uninstall` from an outer terminal. Windows uses the existing installer restore flow.

## v1.5.0 historical notes

- Added `theme hacker`, `theme code` and a bare `theme` menu inside owned Bash/Zsh panes. User shell startup files remain unchanged, including custom Zsh `ZDOTDIR` support.
- Added `tmux-style new NAME [--theme NAME] [-d]`, `list` / `ls`, `attach [NAME]` / `attach -t NAME`, and `detach`. Named sessions retain pane processes through client switching and detach/reattach. Existing `workspace [NAME]` keeps its create-or-reattach behavior.
- Theme changes now affect the selected session. Other sessions keep their palettes, new windows inherit the correct colors, and `--default` changes the starting theme for future sessions. Zoom/F12 state and running shells remain in place.
- Existing v1.4 users can reload with Ctrl-a Ctrl-r and source `. "$TMUX_STYLE_HOME/shell/commands.sh"` in open Bash/Zsh panes to load helpers without restarting their process.
- Extended real-terminal tests for independent themes, native menu selection, Bash/Zsh helpers, named attach, detach, new-window inheritance, default changes and reload.

Downloads: `TmuxStyle-Setup-1.5.0.exe`, `tmux-style-linux-1.5.0.tar.gz`, `tmux-style-macos-1.5.0.tar.gz`, source, checksums and validation reports. Native Unix packages require tmux >= 3.2. Windows workspace behavior is retained.

## v1.4.0 historical notes

- Added standalone Linux and macOS packages with eight themes, native three-pane tmux workspaces, a bottom CPU/RAM/hostname/date bar, full window names, clipboard integration and detach/reattach.
- Added `tmux-style theme NAME` and the Ctrl-a t menu to switch themes in existing sessions without restarting processes.
- Added per-user install/upgrade/restore with backups and an independent tmux socket. Existing tmux and Bash/Zsh configurations stay in place. No separate samoshkin installation is required.
- Uses a two-second native prefix timeout when supported; older tmux keeps the prefix pending until the next key.
- Added Ubuntu and macOS integration tests alongside Windows packaged EXE and real WezTerm Lua checks.
- Removed personal account/author identifiers from maintained history and replaced local machine details in published previews with demo names. Historical source ZIPs and checksum manifests are regenerated separately. GitHub may retain cached views of old commits.

Downloads: `TmuxStyle-Setup-1.4.0.exe`, `tmux-style-linux-1.4.0.tar.gz`, `tmux-style-macos-1.4.0.tar.gz`, checksums and validation reports.

Linux: extract, then `bash linux/install.sh --theme hacker`. macOS: install tmux with Homebrew, extract, then `bash macos/install.command --theme code`. Launch with `~/.local/bin/tmux-style`. Both archives contain architecture-independent scripts using native tmux >= 3.2. See `unix/README.md` for setup, shortcuts, metrics and restore. The Code palette colors tmux's UI; shell/application syntax highlighting is separate. Windows functionality and the legacy samoshkin overlay remain available.

## v1.1.0 historical notes

## Fixed

- Fixed the post-install error “The expression '&' in a pipeline element produced an object that was not valid” when both **Create Desktop shortcut** and **Open workspace** were enabled. Shortcut creation no longer overwrites the launch executable, and setup steps use separate scopes.
- A workspace launch problem after successful configuration now produces a launch warning with a manual-open hint, instead of reporting the whole configuration as failed.
- Added packaged regression coverage for the shortcut + three-pane launch path and for unsuccessful Terminal launches.

## Added

- **Command Line / Black** for tmux and Windows Terminal: pure black, white and gray, including the shell syntax palette. Select `black` or **Command Line (Black)**.
- Original logo and multi-size icon embedded in the installer/key bridge, the installer window, Terminal profiles and the Desktop shortcut.
- English default README, retained Vietnamese README, a Black terminal example recorded from tmux, and an updated six-theme gallery.

## Downloads

Windows: run `TmuxStyle-Setup-1.1.0.exe`, choose a theme and click **Install workspace**. The optional Windows Terminal download uses Microsoft's winget package. The EXE remains unsigned.

tmux: extract `tmux-theme-collection-1.1.0.zip` on a machine with the samoshkin base config and tmux >= 3.2; run `bash install.sh black`, then `tmux source-file ~/.tmux.conf`.

`windows-self-test.json` contains the packaged test results. `SHA256SUMS.txt` covers the downloadable EXE, ZIP and report. Native Windows panes still follow the lifetime of the Terminal window; full tmux detach/attach semantics are not provided.
