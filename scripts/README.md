# Documentation previews

`render-terminal-preview.py` decodes a native ANSI terminal recording with pyte and renders its cells using Pillow. Use a recording saved before the terminal leaves its alternate screen. The pane text is demo content; the status bar and borders come from the recorded terminal.

```bash
python -m pip install Pillow pyte
python scripts/render-terminal-preview.py --input recording.ansi --output preview/black-terminal.png --theme black --columns 120 --rows 24
python scripts/compose-gallery.py
```

The renderer uses Consolas on Windows or DejaVu Sans Mono on Linux. The Black preview is checked pixel by pixel for grayscale output. Raw recordings are not published because they can contain local paths or host information. Gallery composition uses the checked-in terminal screenshots.
