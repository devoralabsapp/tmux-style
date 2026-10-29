# TMX for Linux and macOS

Eight native tmux themes, a bottom status bar, and the same core Ctrl-a shortcuts as the Windows workspace. These packages contain shell scripts and tmux configuration, so one Linux archive works on x86_64 and ARM64 Linux; one macOS archive works on Intel and Apple Silicon. The installed tmux binary must match your OS/CPU. No terminal emulator or font is bundled.

## Install

Install **tmux >= 3.2** and Bash first. On macOS, install [Homebrew](https://brew.sh/) if needed, then `brew install tmux`. On Ubuntu/Debian use `sudo apt install tmux`; Fedora: `sudo dnf install tmux`; Arch: `sudo pacman -S tmux`; Alpine: `apk add tmux bash`.

Extract the release archive, enter the extracted folder, and run:

```bash
# Linux (including a Linux distribution inside WSL)
bash linux/install.sh --theme hacker

# macOS: run in Terminal, or open install.command from Finder
bash macos/install.command --theme code
```

The installer uses your user account and does not need sudo. It installs assets under `${XDG_DATA_HOME:-$HOME/.local/share}/tmux-style` and the short command `~/.local/bin/tmx`. The old `~/.local/bin/tmux-style` command remains a compatibility alias. Existing sessions keep using the same socket/data directory, so upgrades can still attach to them. The installer refuses to overwrite an unrelated `tmx` command, backs up owned assets and does not edit shell profiles or existing tmux configuration.

## Open and use

```bash
~/.local/bin/tmx                     # open/reattach the default workspace
~/.local/bin/tmx new work --theme code
# Ctrl-a d detaches and leaves processes running
~/.local/bin/tmx new lab --theme hacker -d
~/.local/bin/tmx list
~/.local/bin/tmx attach work
~/.local/bin/tmx attach lab
```

If `~/.local/bin` is on PATH, use `tmx` directly from your outer terminal. Inside TMX's Bash/Zsh panes, `tmx`, the legacy `tmux-style` alias, `theme` and `workspace` are available automatically. The owned shell wrappers read your existing `.bashrc` or Zsh startup files, including a custom `ZDOTDIR`, without editing them. Other shells can use the full launcher path. The workspace keeps the **tmux-style** socket for compatibility, separate from your existing tmux server. Detach from another tmux before opening it.

`new NAME` creates a three-pane session; `-d` leaves it detached. It rejects an existing name instead of resetting that session. `workspace [NAME]` preserves the older create-or-reattach behavior. `attach NAME` (also `attach -t NAME`) enters an existing session, or switches to it from inside Tmux Style. It never creates a missing session. `attach` without a name reattaches the most recently used session from an outer terminal; inside Tmux Style it opens the native session chooser. `list` / `ls` shows names, windows, attachment state and themes. `tmx detach` and Ctrl-a d leave pane processes running. Closing a terminal also leaves the sessions available for later attach.

## Change theme in the terminal

Inside a Tmux Style Bash/Zsh pane, use the same short command as on Windows:

```bash
theme hacker                       # recolor this session in place
theme code
theme                              # native theme menu (also Ctrl-a t)
tmx theme paper --session lab # target a named session
tmx theme black --default     # default for NEW sessions
```

Each session keeps its own palette. All its existing windows/panes change in place, new windows inherit it, and other sessions retain their colors. Theme changes preserve processes, zoom and F12 pass-through. Choices last for the session's lifetime; `--default` saves the starting palette for future sessions. With several sessions running, an outer-terminal theme command needs `--session NAME`; with one session it targets that session, and with none it updates the starting default. Native linked windows share pane colors because both sessions refer to the same window.

Applications such as Vim retain their own color schemes. Code Spectrum colors tmux's UI; it does not add PowerShell-style command syntax highlighting to Bash/Zsh.

## Upgrade an open v1.4 workspace

Run the new installer, then press **Ctrl-a Ctrl-r** in each open Tmux Style client to reload. New panes load the shell helpers automatically. To add the short commands to an existing Bash/Zsh pane without restarting its shell, run:

```bash
. "$TMUX_STYLE_HOME/shell/commands.sh"
```

The scoped Bash wrapper loads `.bashrc`; the Zsh wrapper loads the user's `.zshenv` and interactive `.zshrc`. It starts an interactive shell, not a new login shell. Existing sessions and running applications remain available through `tmx attach NAME`.

All eight themes use a bottom bar in this standalone version. Names: `aurora`, `midnight` (default), `ember`, `paper`, `neon`, `black`, `code`, `hacker`. Window names have no configured character truncation; tmux scrolls the window list when it exceeds the available width.

| Keys | Action |
| --- | --- |
| `Ctrl-a c` | New window in the current directory |
| `Ctrl-a \|` / `Ctrl-a -` | Split right / below |
| `Ctrl-a r` / `Ctrl-a R` | Rename window / session |
| `Ctrl-a t` | Choose a theme without opening another terminal |
| `Ctrl-a z` | Zoom / restore pane |
| `Ctrl-a x` / `Ctrl-a X` | Close pane / window |
| `Ctrl-a` + arrow / `Ctrl-a Ctrl-arrow` | Focus / resize pane |
| `Shift-left` / `Shift-right` | Previous / next window |
| `Ctrl-a [` / `Ctrl-a ]` | Copy mode / paste tmux buffer |
| `Ctrl-a d` | Detach, leaving processes running |
| `Ctrl-a Ctrl-a` | Send Ctrl-a to the shell |
| `Ctrl-a Ctrl-r` | Reload configuration |
| `F12` | Toggle pass-through for nested tmux over SSH |

On tmux versions with `prefix-timeout`, Ctrl-a accepts a command within **2 seconds**. Native tmux checks expiration when the next key arrives, so the PREFIX badge can stay visible until that key. Older tmux versions keep the prefix pending until the next key; they do not cancel it prematurely. macOS Terminal/iTerm2 or the OS may intercept some modifier/function keys; configure the terminal to send them if needed. `Ctrl-a` followed by the command works without the Alt shortcuts.

## Status and clipboard

The bar shows session/window names, COPY/PREFIX/ZOOM/OFF, hostname and time. CPU/RAM appear at 110+ columns, date at 140+; below 80 columns it prioritizes the clock. Metrics refresh every two seconds and describe the machine running tmux (the remote host when tmux itself runs over SSH). Linux uses `/proc`; macOS uses `top`, `vm_stat` and `sysctl`. RAM is an available-memory estimate; macOS excludes reclaimable inactive/speculative/purgeable pages. Unsupported/missing counters display `--`.

Copy uses macOS `pbcopy`, Linux Wayland `wl-copy`, or X11 `xclip`/`xsel` when available. Otherwise tmux requests the terminal clipboard via OSC 52; support and permissions depend on the terminal. The tmux buffer remains available with Ctrl-a ]. The standalone package needs no TPM or third-party plugins. The older root `install.sh` remains available for existing samoshkin installations and keeps that setup's plugins and SSH tunnel behavior.

## Uninstall / restore

Exit all TMX sessions first, then run from an outer terminal (detaching keeps sessions alive):

```bash
~/.local/bin/tmx uninstall
```

This removes the active tool and both owned command names across installation upgrades. It preserves backups and a recovery copy under `tmux-style-backups`, and restores a user command that predated the tool when its snapshot is available. It does not uninstall tmux itself or stop unrelated tmux servers. Edited launchers or active TMX sessions cause it to stop before moving files.

Use `tmx restore` to roll back only the latest installation/upgrade instead. On a first installation, restore removes the tool; after an upgrade it restores the earlier version and its command names.

## Readable palettes

The shipped tool-controlled text pairs are checked at **4.5:1** and pane dividers at **3:1**, using [WCAG's relative-luminance calculation](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). Paper uses dark warning/error/prompt colors, menus and copy selections have explicit foreground/background pairs, and Windows Paper's ANSI Black is ink rather than paper. The legacy Midnight overlay inherits the outer terminal's pane background; standalone pane colors are explicit. The Unix configuration allows 256-color fallback instead of forcing RGB on terminals that do not advertise it. Application-specific colors and custom terminal palettes are outside this audit.

`python3 scripts/check-theme-contrast.py` checks native tmux, the generated Unix themes, Windows prompt/PSReadLine colors and WezTerm tabs/status/copy highlights. It generates `dist/theme-contrast.json` plus the labeled vector samples in `preview/theme-readability.svg`. CI fails on insufficient contrast.

## Verify and build

Release files have SHA-256 sidecars. Linux: `sha256sum -c FILE.tar.gz.sha256`; macOS: `shasum -a 256 -c FILE.tar.gz.sha256`.

From the repository, `python3 unix/generate.py` regenerates palettes; `python3 unix/test.py` exercises install, independent named sessions, real Bash/Zsh commands, both theme menus, new-window palette inheritance, attach/detach with process retention, defaults/reload, long names, prefix timing, F12, metrics, upgrade and restore on an isolated socket/home. Zsh coverage runs when Zsh is installed; CI provides it on both Ubuntu and macOS. `python3 unix/package.py` builds both archives under `dist/`.

See `NOTICE.md` for the original configuration's provenance and license scope. New installer/launcher/metrics/clipboard/package/test code uses the MIT terms in `windows-terminal/LICENSE`; those terms do not relicense the pre-existing tmux baseline.
