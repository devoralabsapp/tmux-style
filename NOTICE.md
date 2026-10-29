# Provenance

The tmux baseline is an independently maintained configuration originally based on [samoshkin/tmux-config](https://github.com/samoshkin/tmux-config). Personal source identifiers have been removed at the contributor's request. No blanket license is applied to those pre-existing configuration files.

New Linux/macOS installer, launcher, metrics, clipboard, packaging and test scripts use the MIT terms in `windows-terminal/LICENSE`. Those terms do not relicense the pre-existing tmux configuration. Unix packages include configuration derived from that baseline without requiring the upstream helpers or TPM.

The new Windows installer, key bridge, prompt and build scripts are licensed under `windows-terminal/LICENSE`. That license does not replace the terms applicable to the original tmux configuration or third-party files.

The WezTerm integration, Lua configuration and local Windows metric collector also use that Windows MIT license. WezTerm itself is an independent third-party terminal by its upstream contributors, distributed under its own MIT license, with bundled fonts under OFL terms. Its upstream notice is included in `windows-terminal/WEZTERM_LICENSE.md`. The optional portable download keeps the upstream package unchanged; this project's EXE does not bundle the terminal binary. The pinned official release and upstream SHA-256 are recorded in `windows-terminal/wezterm-runtime.json`.

`windows-terminal/profiles.schema.json` is from Microsoft Windows Terminal tag `v1.25.2733.0`. See `windows-terminal/THIRD_PARTY_NOTICES.md` for its MIT license.

Preview pane text is demonstration content. The tmux status bars and pane borders were captured from a separate test environment. Windows Terminal is a Microsoft product; this project is an independent configuration/installer and is not affiliated with Microsoft.
