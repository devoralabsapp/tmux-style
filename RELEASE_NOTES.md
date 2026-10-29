# Tmux Style v1.4.0

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
