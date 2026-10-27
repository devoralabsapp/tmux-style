# Tmux Style v1.1.0

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
