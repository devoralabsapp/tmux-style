# TMX for Linux and macOS

Nine native tmux themes, a bottom status bar, and the same core Ctrl-a shortcuts as the Windows workspace. These packages contain shell scripts and tmux configuration, so one Linux archive works on x86_64 and ARM64 Linux; one macOS archive works on Intel and Apple Silicon. The installed tmux binary must match your OS/CPU. No terminal emulator or font is bundled.

## Install

Install **tmux >= 3.2**, **Python >= 3.8** and Bash first. Python uses only its standard library; no pip packages are needed. On macOS, install [Homebrew](https://brew.sh/) if needed, then `brew install tmux python`. On Ubuntu/Debian use `sudo apt install tmux python3`; Fedora: `sudo dnf install tmux python3`; Arch: `sudo pacman -S tmux python`; Alpine: `apk add tmux bash python3`.

Extract the release archive, enter the extracted folder, and run:

```bash
# Linux (including a Linux distribution inside WSL)
bash linux/install.sh --theme hacker

# macOS: run in Terminal, or open install.command from Finder
bash macos/install.command --theme code
```

The installer uses your user account and does not need sudo. It installs assets under `${XDG_DATA_HOME:-$HOME/.local/share}/tmux-style` and the short command `~/.local/bin/tmx`. The old `~/.local/bin/tmux-style` command remains a compatibility alias. Existing sessions keep using the same socket/data directory, so upgrades can still attach to them. The installer refuses to overwrite an unrelated `tmx` command, backs up owned assets and does not edit shell profiles or existing tmux configuration.

## Open and use

Run `tmx exit` **inside the session to close**. It terminates that entire session, including every tab/window, pane and running process. Other sessions keep running. `tmx detach` keeps the session alive for a later attach. Exit accepts no session name or other arguments and refuses an outer-terminal call; attach to the desired session first.

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

## Upgrade an open workspace

With v1.8.5 or later installed, run `tmx update`. It checks the latest stable GitHub release, verifies the correct archive for your OS and preserves your default theme and live sessions. To get the command on an older installation, run the new installer once.

Press **Ctrl-a Ctrl-r** in an open TMX client to reload the tmux configuration. Each pane has a scrollback limit of 20,000 lines. The oldest history is evicted as more output arrives. A new pane loads the updated display renderer. To refresh the shell helpers in an existing Bash/Zsh pane, run the following command.

```bash
. "$TMUX_STYLE_HOME/shell/commands.sh"
```

The scoped Bash wrapper loads `.bashrc`; the Zsh wrapper loads the user's `.zshenv` and interactive `.zshrc`. It starts an interactive shell, not a new login shell. Existing sessions and running applications remain available through `tmx attach NAME`.

All nine themes use a bottom bar in this standalone version. Names: `aurora`, `midnight` (default), `ember`, `paper`, `neon`, `black`, `code`, `hacker`, `prism`. Window names have no configured character truncation; tmux scrolls the window list when it exceeds the available width.

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

## Readable shell prompt and Prism

TMX-owned Bash/Zsh panes use explicit foreground AND background around the working directory. On macOS, the cwd is bright red (`#ff7a8a`) on dark palettes and dark red (`#b42336`) on Paper, including when the outer Terminal background is black. The wrappers still load existing startup files and do not edit them. Existing panes can load the update with `. "$TMUX_STYLE_HOME/shell/commands.sh"`; the next prompt redraw uses the current session theme.

Prism includes offline Zsh command-entry highlighting through the bundled [zsh-syntax-highlighting 0.8.0](shell/vendor/zsh-syntax-highlighting/TMX-NOTICE.md). Commands, options, quoted strings, paths and brackets have separate readable colors. An already-loaded user highlighter stays in control. Bash keeps its existing line editor.

In v1.8.4, automatic output highlighting covers the **entire terminal display** of the owned Bash/Zsh shell, across themes. It does not inspect command names: external programs, functions, aliases, shell builtins, compound commands, and stderr all pass through a Python PTY renderer. Plain output gets readable text, path, number, quoted-string, flag and status/error colors. Black keeps its grayscale output palette.

Every command still sees a real terminal on stdin/stdout/stderr. Pipeline/redirected data is never modified: only the final bytes displayed in the terminal receive colors. Existing ANSI-colored output and full-screen/cursor-driven interfaces keep their own rendering. UTF-8, OSC 52, terminal resize, Ctrl-C, live streaming and process exit status are preserved. This is a lexical display highlighter, not a semantic parser for each application's output. Use `TMX_OUTPUT_HIGHLIGHT=0` to disable it; set it back to `1` to enable on the next command. No allowlist or extra `tmx paint` prefix is needed.

The renderer requires Python >= 3.8 and starts when a **new pane** starts its shell. Existing running shells cannot acquire a parent PTY renderer by sourcing a file. After upgrading, open a new tab with **Ctrl-a c** or create `tmx new fresh --theme prism`; existing sessions/jobs remain available. Merely detaching and attaching the old pane keeps its old process and display path.

After installing an update, each already-running shell still has its previous prompt/functions in memory. Reattaching does not restart that shell. Run this once **inside each old TMX Bash/Zsh pane**:

```bash
. "$TMUX_STYLE_HOME/shell/commands.sh"
theme prism
```

This refreshes the red macOS cwd prompt in place. TMX checks its canonical prompt before line-editor redraws, preventing a late user prompt hook from restoring dark blue. An active Powerlevel10k/9k prompt is torn down inside the owned shell so its asynchronous redraw does not fight the TMX prompt; the user's startup files and other shell features are still loaded. Newly created panes load it automatically. Once these helpers are loaded, `tmx refresh` reloads them without restarting the shell. Shell profiles are never edited.

## Status and clipboard

The bar shows session/window names, COPY/PREFIX/ZOOM/OFF, hostname and time. CPU/RAM appear at 110+ columns, date at 140+; below 80 columns it prioritizes the clock. Metrics refresh every two seconds and describe the machine running tmux (the remote host when tmux itself runs over SSH). Linux uses `/proc`; macOS uses `top`, `vm_stat` and `sysctl`. RAM is an available-memory estimate; macOS excludes reclaimable inactive/speculative/purgeable pages. Unsupported/missing counters display `--`.

For a selection inside tmux, enter copy mode with **Ctrl-a [**, press **Space** to start selecting, move the cursor, then press **Ctrl-C**, **Enter** or **y** to copy and leave copy mode. **Ctrl-V** pastes the current tmux buffer (also from copy mode); **Ctrl-a ]** remains available. At the normal prompt, Ctrl-C still interrupts the running command.

The tmux buffer is on the VPS. To paste your computer's clipboard over SSH, use **Ctrl-V / Ctrl-Shift-V in the managed Windows WezTerm client**, or **Cmd-V on macOS**. For a GUI text selection, Windows WezTerm Ctrl-C / Ctrl-Shift-C or macOS Cmd-C copies locally. Hold the terminal's mouse-bypass modifier when the remote app captures dragging; in WezTerm it is Shift.

While SSH_CONNECTION/SSH_TTY is set, the copy helper sends OSC 52 to the attached client instead of choosing clipboard tools on the VPS. The owned tmux server accepts clipboard writes from inner tmux and advertises the clipboard capability to nested screen/tmux clients. Synchronizing the VPS selection to the computer clipboard still requires OSC 52 support/permission in the outside terminal; local tmux buffer copy/paste works independently. See [tmux clipboard support](https://github.com/tmux/tmux/wiki/Clipboard). Outside SSH, macOS uses pbcopy and Linux uses wl-copy/xclip/xsel when available, otherwise OSC 52.

After updating both the client installation and VPS package, reload with Ctrl-a Ctrl-r and detach/attach the clients once to refresh capabilities. The standalone package needs no TPM or third-party plugins. The older root `install.sh` remains available for existing samoshkin installations and keeps that setup's plugins and SSH tunnel behavior.

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
