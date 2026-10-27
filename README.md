<img src="assets/tmux-style.svg" width="84" alt="Tmux Style logo">

# Tmux Style

English · [Tiếng Việt](README.vi.md)

Six selectable themes for **tmux** and **Windows Terminal + PowerShell**, with familiar `Ctrl-a` shortcuts based on the original tmux configuration and [samoshkin/tmux-config](https://github.com/samoshkin/tmux-config).

## Command Line / Black

A pure black canvas, white text and quiet gray dividers. Every color in the Black palette is grayscale, including shell syntax colors. No green or other colored accents.

![Command Line / Black terminal sample](preview/black-terminal.png)

*Recorded from a native tmux test session with sample pane content. The same color palette is available in Windows Terminal.*

<details>
<summary>View all six themes</summary>

![Six-theme terminal gallery](preview/theme-gallery.png)

</details>

## Windows: download the EXE

**[Download TmuxStyle-Setup-1.1.0.exe](https://github.com/devoralabsapp/tmux-style/releases/download/v1.1.0/TmuxStyle-Setup-1.1.0.exe)** · [Release notes and checksums](https://github.com/devoralabsapp/tmux-style/releases/latest)

1. Run the installer, choose a theme and starting folder.
2. Keep the Desktop shortcut and launch options enabled if you want a ready-to-use, three-pane workspace.
3. Click **Install workspace**. Open **Tmux Style Workspace** on Desktop next time.

The per-user installer uses Windows PowerShell 5.1 and .NET Framework 4.8 on Windows 10/11. If Windows Terminal is missing, the optional download uses the official Microsoft package through winget and requires an internet connection. No Nerd Font, Oh My Posh or Starship is needed.

**v1.1.0 fixes the post-install launch failure** shown as “The expression '&' in a pipeline element produced an object that was not valid.” Shortcut creation and launching now use separate variables/scopes, and the packaged regression test exercises both options together.

| Shortcut | Windows behavior |
| --- | --- |
| `Ctrl-a c` | New tab in the focused profile and working directory |
| `Ctrl-a \|` / `Ctrl-a -` | Split right / below |
| `Ctrl-a r` / `Ctrl-a R` | Rename tab / window |
| `Ctrl-a z` | Zoom / restore pane |
| `Ctrl-a x` / `Ctrl-a X` | Close pane / tab |
| `Ctrl-a` + arrow | Focus an adjacent pane |
| `Ctrl-a Ctrl-arrow` | Resize pane |
| `F12` | Toggle the key bridge; turn it off for tmux over SSH |

`theme black` opens a Command Line tab. `workspace` opens a three-pane window at the current directory. The bridge handles only predefined mappings while Windows Terminal is in front; it does not record typed content or add itself to Windows startup. Terminal sessions still end when their window is closed. [Full shortcut table, native differences and restore instructions](windows-terminal/README.md).

The installer backs up existing settings and owned assets, preserves unrelated profiles/preferences/non-conflicting keys, and includes **Restore previous settings**. It changes neither the shared `$PROFILE` nor execution policy or Windows' default terminal application.

## Linux / macOS / WSL: tmux

Requires **tmux >= 3.2** and the samoshkin base configuration already installed under `~/.tmux`.

```bash
git clone https://github.com/devoralabsapp/tmux-style.git
cd tmux-style
bash install.sh black
tmux source-file ~/.tmux.conf
```

Supported names: `black`, `aurora`, `midnight`, `ember`, `paper`, `neon`. Without a name, the installer keeps Midnight as its default. Every install creates a backup and preserves the existing `~/.tmux.conf` symlink. Existing sessions can stay open.

| Theme | Style |
| --- | --- |
| [Command Line / Black](preview/black.png) | Black canvas, white text, gray dividers |
| [Aurora](preview/aurora.png) | Mint/lavender, tabs on top locally |
| [Midnight / Cyan](preview/midnight-cyan.png) | Compact navy/cyan workspace |
| [Ember](preview/ember.png) | Warm amber with numbered pane headers |
| [Paper / Ink](preview/paper.png) | Warm light background and ink-black tabs |
| [Neon / Circuit](preview/neon.png) | Orchid accents and two rows of context |

The tmux status bar adapts to window width and shows COPY/PREFIX/ZOOM/OFF states. Existing sysstat CPU/RAM widgets appear on wide terminals. Personal shortcuts, clipboard behavior and SSH/F12 handling are retained. Remote sessions keep the samoshkin bottom status position. Applications such as Neovim can still use their own color schemes.

To restore tmux, use the backup path printed by the installer:

```bash
cat ~/.tmux/backups/your-backup-file > ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

## Build and validation

```powershell
.\windows-terminal\build.ps1 -RunTests
```

The Windows build reads `VERSION`, embeds the multi-size application icon, and produces an EXE plus SHA-256 checksums under `dist/`. Its packaged self-test runs on Windows PowerShell 5.1 with temporary settings: six themes, JSONC preservation, exact backup/restore, protection of newer user edits, prompt exit codes, grayscale checks, native key-map resolution, and shortcut/post-install launch regression tests. CI also validates settings against Microsoft's schema.

The EXE is **not code signed**. Source and checksums are provided. This project is an independent installer/configuration, not Microsoft Windows Terminal itself. See [NOTICE.md](NOTICE.md) for provenance and licensing. Original Windows code and logo assets use the [Windows MIT license](windows-terminal/LICENSE); existing tmux and third-party files retain their own terms.
