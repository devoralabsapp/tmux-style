"""Render illustrative previews from the generated Windows palettes (Pillow)."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
palettes = json.loads((ROOT/'windows-terminal/wezterm-palettes.json').read_text())
image = Image.new('RGB', (1600, 1080), '#11151c')
draw = ImageDraw.Draw(image)
regular = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 22)
small = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 18)
bold = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 26)
draw.text((36, 20), 'WINDOWS WORKSPACES / ILLUSTRATIVE PREVIEWS / SAMPLE DATA', font=small, fill='#b7c3d8')

def tokens(x, y, items, colors, font=regular):
    for text, color in items:
        draw.text((x, y), text, font=font, fill=colors[color] if isinstance(color, int) else color)
        x += draw.textlength(text, font=font)

for slug, top, title in [('code', 66, 'CODE SPECTRUM'), ('hacker', 570, 'HACKER MATRIX')]:
    p = palettes[slug]; c = p['colors']; ansi = c['ansi'] + c['brights']
    left, right, bottom = 28, 1572, top+480
    draw.rounded_rectangle((left, top, right, bottom), radius=14, fill=c['background'], outline=c['split'], width=2)
    draw.rounded_rectangle((left+2, top+2, right-2, top+59), radius=12, fill=p['bar'])
    draw.text((52, top+17), title, font=bold, fill=p['accent'])
    draw.text((1140, top+22), 'theme '+slug+'  |  CTRL-A: 2s', font=small, fill=p['muted'])
    draw.line((1040, top+60, 1040, bottom-42), fill=c['split'], width=2)
    draw.text((54, top+81), 'PS  ~/workspace   [main]', font=regular, fill=p['accent'])
    rows = [
        [('  # Commands, variables and strings have distinct colors', 8)],
        [('  $project', 12), (' = ', 7), ('"tmux-style"', 3)],
        [('  Get-ChildItem ', 11), ('-Path ', 6), ('$project ', 12), ('| ', 7)],
        [('    Where-Object ', 11), ('{ ', 7), ('$_.Length ', 12), ('-gt ', 5), ('1024 ', 10), ('}', 7)],
        [('  if ', 13), ('($project', 12), (') {', 7)],
        [('    Write-Host ', 11), ('"Workspace ready" ', 3), ('-ForegroundColor ', 6), ('Green', 10)],
        [('  }', 7)],
    ]
    if slug == 'hacker':
        rows[0] = [('  # Local development / green phosphor palette', 8)]
        rows[2] = [('  Get-Process ', 10), ('| ', 7), ('Sort-Object ', 10), ('CPU ', 14), ('-Descending', 14)]
        rows[3] = [('    Select-Object ', 10), ('-First ', 14), ('5 ', 11), ('Name, CPU, WorkingSet', 7)]
    for index, row in enumerate(rows):
        tokens(48, top+129+index*34, row, ansi)
    draw.text((1070, top+92), 'WORKSPACE / LOCAL', font=bold, fill=p['accent'])
    for index, (label, value) in enumerate([('git', 'main / clean'), ('shell', 'PowerShell'), ('layout', '3 panes'), ('prefix', 'waits 2 seconds'), ('theme', 'changes in place')]):
        draw.text((1070, top+151+index*42), label, font=regular, fill=p['muted'])
        draw.text((1192, top+151+index*42), value, font=regular, fill=p['fg'])
    draw.rectangle((left+2, bottom-41, right-2, bottom-2), fill=p['bar'])
    draw.rectangle((left+2, bottom-41, 390, bottom-2), fill=p['accent'])
    draw.text((45, bottom-33), 'TMUX / CTRL-A   1 workspace', font=small, fill=p['bar'])
    draw.text((425, bottom-33), '2 logs', font=small, fill=p['muted'])
    draw.text((842, bottom-33), 'CPU 18%  RAM 42% | DEMO-PC | 27/10 14:30', font=small, fill=p['fg'])

path = ROOT/'preview/windows-new-themes.png'
image.save(path)
print(path)
