"""Generate standalone tmux palettes from the existing theme sources."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = (ROOT / 'tmux.conf').read_text(encoding='utf-8')
ORIGINAL = ['#161925', '#e0e6f5', '#b8a1f7', '#a5aec6', '#75d7e8',
            '#a6d6a0', '#f0c674', '#f28b98', '#202435', '#292e42', '#3b425b']
catalog = json.loads((ROOT / 'themes/catalog.json').read_text())
catalog['midnight'] = dict(name='Midnight / Cyan', colors=ORIGINAL, pane='#10131e')
catalog.update(json.loads((ROOT / 'windows-terminal/themes.extra.json').read_text()))
section = BASE.split('# MIDNIGHT / CYAN', 1)[1].split('# =====================================\n# ===        Renew environment', 1)[0]
section = '# MIDNIGHT / CYAN' + section
# No plugin dependencies: native command substitution samples the local OS.
section = section.split('# Existing plugins remain installed.', 1)[0]
section = re.sub(r'\#\{\?\#\{e\|>=:\#\{client_width\},100\},\#\{=14:window_name\},\#\{=8:window_name\}\}', '#{window_name}', section)
section = re.sub(r'^midnight_metrics=.*$', '''midnight_metrics='#{?#{e|>=:#{client_width},110},#(bash "$TMUX_STYLE_HOME/metrics.sh")  ,}' ''', section, flags=re.M)
section = section.replace('client_width},120', 'client_width},140')
section = section.replace('# >=120 cols: host + date + clock. 80-119: host + clock. <80: clock.', '# >=140 cols: date; >=110: CPU/RAM; >=80: hostname; narrow: clock.')
section = section.replace('# >=160 cols: show the optional sysstat CPU/RAM widgets, when available.', '# CPU/RAM use the local operating system, without a plugin.')
section = section.replace('status-interval 5', 'status-interval 2').replace('status-right-length 70', 'status-right-length 90')
folder = ROOT / 'unix/themes'
folder.mkdir(exist_ok=True)
for slug in ['aurora', 'midnight', 'ember', 'paper', 'neon', 'black', 'code', 'hacker']:
    spec = catalog[slug]
    mapping = dict(zip(ORIGINAL, spec['colors']))
    text = re.sub(r'#[0-9a-fA-F]{6}', lambda m: mapping.get(m[0], m[0]), section)
    text = text.replace('# MIDNIGHT / CYAN', '# ' + spec['name'].upper())
    text += f"\nset -g @tmux_style_theme '{slug}'\n"
    text += f"setw -g window-style 'bg={spec['pane']},fg={spec['colors'][1]}'\n"
    text += f"setw -g window-active-style 'bg={spec['pane']},fg={spec['colors'][1]}'\n"
    if slug == 'paper':
        text = text.replace('bg=#f0d8a5#,fg=#e9e2d5', 'bg=#f0d8a5#,fg=#302e2a')
    (folder / (slug + '.conf')).write_text(text, encoding='utf-8', newline='\n')
print('Generated 8 standalone Linux/macOS themes')
