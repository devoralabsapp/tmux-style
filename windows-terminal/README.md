# Windows Terminal workspace + tmux-style keys

Download **TmuxStyle-Setup-1.1.0.exe** from the [GitHub Release](https://github.com/devoralabsapp/tmux-style/releases/latest), choose a theme and starting folder, then click **Install workspace**. The installer is per-user and uses Windows PowerShell 5.1 and .NET Framework already included with Windows 10/11. It can install the official Microsoft Windows Terminal package with winget if Terminal is missing and the download checkbox is enabled. An internet connection and App Installer/winget are needed for that optional step.

The executable is not code signed. Source, build scripts and SHA-256 checksums are provided with the release. It does not bundle or impersonate Microsoft Windows Terminal.

## Keys matching original tmux configuration

Press and release **Ctrl-a**, then the second key. The prefix waits up to five seconds; Escape cancels it. `Ctrl-a Ctrl-a` forwards a literal Ctrl-a to the terminal.

| Original tmux binding | Windows behavior |
| --- | --- |
| `Ctrl-a c` | New tab using the focused profile and working directory |
| `Ctrl-a \|` | Split right |
| `Ctrl-a -` | Split below |
| `Ctrl-a r` | Rename tab |
| `Ctrl-a R` | Rename window |
| `Ctrl-a Tab` | Switch to a recently used tab |
| `Ctrl-a z` | Zoom / restore pane (inherited default in the personal tmux config) |
| `Ctrl-a x` | Close pane |
| `Ctrl-a X` | Close tab |
| `Ctrl-a Q` | Close the window using Terminal's close behavior |
| `Ctrl-a Ctrl-o` | Swap with the next pane |
| `Ctrl-a` + arrow | Focus adjacent pane |
| `Ctrl-a Ctrl-arrow` | Resize pane |
| `Ctrl-a 1` … `9` | Select tabs 1–9 |
| `Ctrl-a [` | Windows Terminal keyboard selection mode |
| `Ctrl-a ]` | Paste the Windows clipboard |
| `Ctrl-a Ctrl-e` | Edit Terminal settings JSON |
| `Ctrl-a Ctrl-s` | Toggle Terminal focus mode (hide/show tab/title chrome) |
| `Ctrl-a d` | Minimize the window; processes keep running |
| `Ctrl-a ?` | Terminal command palette |
| `F12` | Turn the key bridge off/on; use OFF for tmux over SSH |
| `Shift+Up` | Send Alt+F12, use Ctrl-b prefix, disable Shift tab controls |
| `Shift+Down` | Send Alt+F11, restore Ctrl-a and enable Shift tab controls |
| `Shift+Left/Right`, after Shift+Down | Previous/next tab |
| `Ctrl+Shift+Left/Right`, after Shift+Down | Move tab left/right |
| `Ctrl+T`, after Shift+Down | New tab in the focused profile/directory |

Linking/merging sessions (`L`, `Ctrl-u`), detaching other clients (`D`), window activity/silence monitors (`m`, `M`) and tmux buffer history (`Enter`) have no equivalent in this native setup. `Ctrl-r` after the prefix is not mapped: Terminal automatically reloads settings JSON; open a new Tmux Style tab to reload the prompt. The minimize, focus-mode, selection and Windows clipboard mappings are approximations, rather than full tmux session semantics. Closing a Terminal window ends its PowerShell sessions.

The bridge only handles keys while the **WindowsTerminal** process owns the foreground window. It does not record keys, inspect typed text, read the clipboard or make network requests. It appears in the system tray; its menu can turn mappings off or exit. It starts from Tmux Style profiles, runs once per user session, and exits after Terminal has been closed for about 20 seconds. It does not add itself to Windows startup. F12 turns off this bridge, while Windows Terminal's own shortcuts remain available. Elevated Terminal windows may require a bridge at matching privilege; the normal per-user setup targets non-elevated windows.

Direct shortcuts also remain: `Ctrl+Alt+V/H` splits, `Alt+Arrow` focuses panes, `Alt+Shift+Arrow` resizes, `Ctrl+Shift+Z` zooms and `Ctrl+Alt+W` creates a three-pane tab.

## Terminal sample

![Command Line / Black terminal sample](../preview/black-terminal.png)

This example was recorded from a native tmux test session with sample pane content. Windows Terminal uses the same Black color palette.

## Themes and prompt

Six profiles are installed: Aurora, Midnight, Ember, Paper, Neon and Command Line. `theme black` opens the monochrome profile. `theme neon` opens a new Neon tab. `workspace` opens a three-pane window at the current directory. The prompt shows the directory and Git branch, when available. No Nerd Font, Oh My Posh or Starship is required.

The installer preserves unrelated profiles, preferences and non-conflicting keys. It intentionally replaces the keys listed above and sets the selected theme as the default profile. `$PROFILE`, PATH, execution policy and Windows' default terminal application are not changed.

## Backup and restore

Settings, owned assets and an existing workspace shortcut are backed up under `%LOCALAPPDATA%\TmuxStyleWindows\backups`. To restore the most recent pre-installation state, close workspace windows and use **Restore previous settings** in the installer. It stops if newer user edits would be lost. Standard Terminal first-launch normalization is accepted by the restore check.

Installed assets live under `%LOCALAPPDATA%\TmuxStyleWindows`. Windows Terminal itself remains installed after restoring the configuration.

## Build and test

On Windows, from the repository root:

```powershell
.\windows-terminal\build.ps1 -RunTests
```

The build uses the Windows .NET Framework compiler. No downloaded compiler package or PowerShell 7 runtime is included in the EXE. `dist/` contains the installer, checksums and self-test report. The packaged self-test uses temporary settings, exercises all six themes, preserves existing data, checks exact backups/restores, prompt exit-code behavior and key-map resolution. It does not install a keyboard hook or touch production settings. CI separately validates generated settings against Microsoft's schema using PowerShell 7.

GUI capture was unavailable in the local test environment (capture timeout); the release was checked by compiling and running the packaged self-test and by validating the native settings, not by claiming every shortcut was pressed in UI.

References: the original tmux configuration, [Terminal actions](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/actions), [upstream multi-key prefix request](https://github.com/microsoft/terminal/issues/1334).

## v1.1.0 launch fix

Creating a Desktop shortcut no longer overwrites the executable used by the post-install launcher. Setup steps execute in separate scopes. The packaged regression test enables both shortcut creation and launch, then checks the complete three-pane argument list using a mock Terminal. A launch failure after successful configuration is reported as a launch warning, rather than claiming the configuration failed.
