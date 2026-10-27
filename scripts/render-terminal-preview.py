"""Render a recorded native terminal screen; requires Pillow and pyte.

The input must be an ANSI recording taken before the terminal leaves its screen.
This renders recorded cells, rather than inventing terminal output.
"""
from pathlib import Path
import argparse, json, re
import pyte
from PIL import Image, ImageDraw, ImageFont

parser=argparse.ArgumentParser()
parser.add_argument('--input',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--theme',default='black')
parser.add_argument('--columns',type=int,default=120)
parser.add_argument('--rows',type=int,default=24)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
spec=json.loads((root/'themes/catalog.json').read_text())[args.theme]
font_path=next((str(p) for p in [Path('C:/Windows/Fonts/consola.ttf'),Path('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')] if p.exists()),None)
if not font_path:raise RuntimeError('Install Consolas or DejaVu Sans Mono')
font=ImageFont.truetype(font_path,16)
bold_path=Path(font_path).with_name('consolab.ttf') if font_path.endswith('consola.ttf') else Path(font_path).with_name('DejaVuSansMono-Bold.ttf')
bold=ImageFont.truetype(str(bold_path),16) if bold_path.exists() else font
screen=pyte.Screen(args.columns,args.rows)
raw=args.input.read_bytes().decode('utf-8','replace')
raw=re.sub(r'\x1b\[\?[0-9;]*n','',raw)
pyte.Stream(screen).feed(raw)
status=screen.display[-1]
if 'editor' not in status:raise RuntimeError('The recording does not contain the expected tmux status bar')
def color(value,default):
    if re.fullmatch('[a-fA-F0-9]{6}',value):return '#'+value
    return {'black':'#000000','white':'#e6e6e6'}.get(value,default)
image=Image.new('RGB',(args.columns*10,args.rows*22),spec['pane'])
draw=ImageDraw.Draw(image)
for y in range(args.rows):
    for x in range(args.columns):
        cell=screen.buffer[y][x]
        fg,bg=color(cell.fg,spec['colors'][1]),color(cell.bg,spec['pane'])
        if cell.reverse:fg,bg=bg,fg
        draw.rectangle((x*10,y*22,(x+1)*10-1,(y+1)*22-1),fill=bg)
        if cell.data.strip():draw.text((x*10,y*22),cell.data,font=bold if cell.bold else font,fill=fg)
if args.theme=='black':
    pixels=image.get_flattened_data() if hasattr(image,'get_flattened_data') else image.getdata()
    for rgb in pixels:
        if not(rgb[0]==rgb[1]==rgb[2]):raise RuntimeError('The Black preview contains a colored pixel')
args.output.parent.mkdir(parents=True,exist_ok=True)
image.save(args.output)
print('Rendered native terminal recording:',args.output)
