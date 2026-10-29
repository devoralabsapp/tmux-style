# Tmux Style for Linux and macOS

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

The installer uses your user account and does not need sudo. It installs assets under `${XDG_DATA_HOME:-$HOME/.local/share}/tmux-style` and a launcher at `~/.local/bin/tmux-style`. It backs up previous owned assets and any existing launcher before replacing them. It does not edit `~/.tmux.conf`, `~/.tmux`, `.bashrc` or `.zshrc`, install plugins, download software, or change your terminal application's preferences.

## Open and use

```bash
~/.local/bin/tmux-style                     # open/reattach a three-pane workspace
~/.local/bin/tmux-style workspace project   # another named session
~/.local/bin/tmux-style themes
~/.local/bin/tmux-style theme code          # recolor existing sessions in place
~/.local/bin/tmux-style theme hacker
```

If `~/.local/bin` is on PATH, use `tmux-style` directly. No shell startup changes are required. The workspace uses its own **tmux-style** socket, separate from your existing tmux server. Detach from another tmux before opening it. Sessions survive closing the terminal window and can be reattached with the same launcher. `theme` changes all sessions on the Tmux Style server and saves the choice for future starts; pane processes keep running. Applications such as Vim retain their own color schemes. The Code Spectrum theme colors tmux's UI; it does not add PowerShell-style command syntax highlighting to Bash/Zsh.

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

## Restore / remove

Exit the sessions on the Tmux Style server first, then run:

```bash
~/.local/bin/tmux-style restore
```

This restores the previous installation and launcher. After the first installation it removes the owned assets/launcher. Each restore preserves a recovery copy under `tmux-style-backups`. Existing dotfiles and other tmux servers are untouched. If the launcher was edited after installation, restore stops and prints a manual-recovery hint.

## Verify and build

Release files have SHA-256 sidecars. Linux: `sha256sum -c FILE.tar.gz.sha256`; macOS: `shasum -a 256 -c FILE.tar.gz.sha256`.

From the repository, `python3 unix/generate.py` regenerates palettes; `python3 unix/test.py` exercises install, three real panes, all themes, long names, prefix timing, F12, metrics, upgrade and restore on an isolated socket/home. `python3 unix/package.py` builds both archives under `dist/`. GitHub Actions runs the integration test on both Ubuntu and macOS in addition to the existing Windows tests.

See `NOTICE.md` for the original configuration's provenance and license scope. New installer/launcher/metrics/clipboard/package/test code uses the MIT terms in `windows-terminal/LICENSE`; those terms do not relicense the pre-existing tmux baseline.
