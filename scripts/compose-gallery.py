"""Compose documentation cards from recorded terminal screenshots (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
root=Path(__file__).resolve().parents[1]
out=root/'preview'
font_root=Path('C:/Windows/Fonts')
if font_root.exists():
    title=ImageFont.truetype(str(font_root/'segoeuib.ttf'),30)
    label=ImageFont.truetype(str(font_root/'segoeui.ttf'),17)
else:
    title=ImageFont.truetype('DejaVuSans.ttf',30)
    label=ImageFont.truetype('DejaVuSans.ttf',17)
items=[('black','COMMAND LINE / BLACK','Pure black, white and gray.'),
       ('aurora','AURORA','Mint accents and lavender details.'),
       ('midnight','MIDNIGHT / CYAN','A quiet, compact everyday workspace.'),
       ('ember','EMBER','Warm amber, charcoal, numbered pane headers.'),
       ('paper','PAPER / INK','Warm paper, ink-black tabs.'),
       ('neon','NEON / CIRCUIT','Orchid tabs and two rows of context.')]
gallery=Image.new('RGB',(2032,1760),'#0c0f18')
draw=ImageDraw.Draw(gallery)
draw.text((32,22),'SIX WAYS TO TMUX',font=title,fill='#e6e6e6')
draw.text((32,68),'Native tmux recordings / sample pane content / the same palettes are available on Windows',font=label,fill='#a0a0a0')
for number,(slug,name,subtitle) in enumerate(items):
    source=out/('terminal.png' if slug=='midnight' else slug+'-terminal.png')
    image=Image.open(source).convert('RGB')
    card=Image.new('RGB',(976,520),'#10131e')
    cd=ImageDraw.Draw(card)
    cd.text((16,12),f'{number+1:02d} / {name}',font=title,fill='#e6e6e6')
    cd.text((16,51),subtitle,font=label,fill='#a0a0a0')
    fitted=ImageOps.contain(image,(944,418),Image.Resampling.LANCZOS)
    card.paste(fitted,(16+(944-fitted.width)//2,90+(418-fitted.height)//2))
    x=24+(number%2)*1008;y=116+(number//2)*540
    gallery.paste(card,(x,y))
    if slug=='black':card.save(out/'black.png')
gallery.save(out/'theme-gallery.png')
print('Composed six-theme gallery')
