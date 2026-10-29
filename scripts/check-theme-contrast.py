"""Audit shipped, app-controlled text/borders; use actual generated configs.

WCAG relative luminance: text >= 4.5:1; pane focus/dividers >= 3:1.
This does not certify colors independently chosen by terminal applications.
"""
from pathlib import Path
import json
from html import escape
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = []


def luminance(hex_color):
    values = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    values = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
    return sum(v * w for v, w in zip(values, (.2126, .7152, .0722)))


def contrast(a, b):
    a, b = sorted((luminance(a), luminance(b)))
    return (b + .05) / (a + .05)


def add(theme, role, fg, bg, minimum=4.5):
    assert re.fullmatch(r'#[0-9a-fA-F]{6}', fg), (theme, role, fg)
    assert re.fullmatch(r'#[0-9a-fA-F]{6}', bg), (theme, role, bg)
    ratio = contrast(fg, bg)
    checks.append(dict(theme=theme, role=role, foreground=fg, background=bg,
                       ratio=round(ratio, 3), required=minimum, passed=ratio >= minimum))


def read_config(path):
    variables, options = {}, {}
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        assignment = re.match(r'^(\w+)=(.+)$', line)
        option = re.match(r'^(?:set|setw) -g ([\w@-]+) (.+)$', line)
        if not assignment and not option:
            continue
        name, raw = (assignment or option).groups()
        if raw[:1] in ['"', "'"] and raw[-1:] == raw[:1]:
            raw = raw[1:-1]
        raw = re.sub(r'\$(\w+)', lambda m: variables.get(m[1], m[0]), raw)
        (variables if assignment else options)[name] = raw
    return variables, options


def style(text, fallback):
    result = dict(fallback)
    for name, value in re.findall(r'(fg|bg)=(#[0-9a-fA-F]{6})', text):
        result[name] = value
    return result


files = [('tmux/midnight', ROOT / 'tmux.conf')]
files += [('tmux/' + p.stem, p) for p in sorted((ROOT / 'themes').glob('*.conf'))]
files += [('unix/' + p.stem, p) for p in sorted((ROOT / 'unix/themes').glob('*.conf'))]
for theme, path in files:
    variables, opts = read_config(path)
    bar = style(opts['status-style'], {})
    pane = style(opts['window-style'], {'fg': variables['color_light'], 'bg': '#10131e'})
    for name in ['status-style', 'window-style', 'window-active-style', 'window-status-style',
                 'window-status-current-style', 'window-status-activity-style', 'window-status-bell-style',
                 'window-status-last-style', 'message-style', 'message-command-style',
                 'menu-style', 'menu-selected-style', 'mode-style']:
        colors = style(opts[name], pane if name.startswith('window-a') or name == 'window-style' else bar)
        add(theme, name, colors['fg'], colors['bg'])
    for name in ['pane-border-style', 'pane-active-border-style']:
        colors = style(opts[name], pane)
        add(theme, name, colors['fg'], pane['bg'], 3)
    for name in ['midnight_modes', 'midnight_status_left', 'midnight_host', 'midnight_date']:
        for i, value in enumerate(re.findall(r'#\[(.*?)\]', variables[name].replace('#,', ','))):
            if value == 'default':
                continue
            colors = style(value, bar)
            add(theme, name + '/' + str(i), colors['fg'], colors['bg'])
    add(theme, 'OFF bar', variables['color_status_text'], variables['color_window_off_status_bg'])
    for name, value in opts.items():
        if re.fullmatch(r'@sysstat_(?:cpu|mem|swap)_color_(?:low|medium|stress)', name):
            add(theme, name, value, bar['bg'])

# Resolve console color names from the actual PowerShell source, rather than
# assuming the terminal's "Black" is a dark color (the Paper regression).
ps = (ROOT / 'windows-terminal/shell.ps1').read_text(encoding='utf-8')
palette_roles = {name: dict(re.findall(r"(\w+)='(\w+)'", body))
                 for name, body in re.findall(r"'([a-z]+)' \{ @\{([^}]+)\} \}", ps)}
default_palette = dict(re.findall(r"(\w+)='(\w+)'", re.search(r'default \{ @\{([^}]+)\}', ps)[1]))
syntax_blocks = re.findall(r'\$syntax=@\{([^}]+)\}', ps)
console_names = dict(zip(
    ['Black','DarkRed','DarkGreen','DarkYellow','DarkBlue','DarkMagenta','DarkCyan','Gray',
     'DarkGray','Red','Green','Yellow','Blue','Magenta','Cyan','White'],
    ['black','red','green','yellow','blue','purple','cyan','white',
     'brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite']))
settings = json.loads((ROOT / 'windows-terminal/settings.additions.json').read_text())
wez = json.loads((ROOT / 'windows-terminal/wezterm-palettes.json').read_text())
for profile in settings['profiles']:
    slug = profile['slug']
    scheme = next(s for s in settings['schemes'] if s['name'] == profile['colorScheme'])
    palette = palette_roles.get(slug, default_palette)
    roles = {'prompt/' + k: v for k, v in palette.items()}
    block = syntax_blocks[1 if slug == 'code' else 2 if slug == 'hacker' else 0]
    for token in block.split(';'):
        role, value = token.split('=', 1)
        roles['syntax/' + role] = palette[value.split('.')[-1]] if value.startswith('$global:') else value.strip("'")
    for role, name in roles.items():
        add('windows/' + slug, role, scheme[console_names[name]], scheme['background'])
    add('windows/' + slug, 'terminal selection', scheme['foreground'], scheme['selectionBackground'])
    add('windows/' + slug, 'PSReadLine reverse selection', scheme['background'], scheme['foreground'])
    p = wez[slug]
    for name, fg, bg in [('active tab', p['bar'], p['accent']), ('inactive tab', p['muted'], p['bar']),
                         ('hover tab', p['fg'], p['surface']), ('workspace/PREFIX', p['accent'], p['surface']),
                         ('CPU/RAM/host/time', p['fg'], p['bar'])]:
        add('wezterm/' + slug, name, fg, bg)
    for prefix in ['copy_mode_active_highlight', 'copy_mode_inactive_highlight', 'quick_select_label', 'quick_select_match']:
        add('wezterm/' + slug, prefix, p['colors'][prefix + '_fg']['Color'], p['colors'][prefix + '_bg']['Color'])

failed = [c for c in checks if not c['passed']]
if not failed:
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1344" height="930" viewBox="0 0 1344 930">',
           '<rect width="1344" height="930" fill="#0c0f18"/>', '<g font-family="Consolas,DejaVu Sans Mono,monospace">',
           '<text x="28" y="40" font-size="25" fill="#e0e6f5">TMX / READABLE THEMES</text>',
           '<text x="28" y="69" font-size="14" fill="#b8bfd0">Shipped color samples / text 4.5:1 minimum / dividers 3:1 minimum</text>']
    for i, profile in enumerate(settings['profiles']):
        slug = profile['slug']; p = wez[slug]
        x, y = 28 + (i % 2) * 658, 94 + (i // 2) * 202
        svg.append(f'<rect x="{x}" y="{y}" width="630" height="184" rx="8" fill="{p["colors"]["background"]}" stroke="{p["colors"]["split"]}" stroke-width="2"/>')
        label = profile['name'].split(' - ', 1)[-1].upper()
        for dy, size, fg, text in [(28,18,p['fg'],label),(60,17,p['fg'],'tmx new work --theme '+slug+' -d'),(87,15,p['muted'],'CPU 12% / RAM 37% / demo-host')]:
            svg.append(f'<text x="{x+18}" y="{y+dy}" font-size="{size}" fill="{fg}">{escape(text)}</text>')
        for dx, width, fg, bg, text in [(0,122,p['accent'],p['surface'],'work / TMX'),(122,144,p['muted'],p['bar'],'1 shell'),(266,126,p['bar'],p['accent'],'2 logs'),(392,238,p['fg'],p['bar'],'29 Oct / 12:00')]:
            svg.append(f'<rect x="{x+dx}" y="{y+111}" width="{width}" height="35" fill="{bg}"/>')
            svg.append(f'<text x="{x+dx+10}" y="{y+134}" font-size="16" fill="{fg}">{text}</text>')
        _, opts = read_config(ROOT / 'unix/themes' / (slug+'.conf'))
        selected = style(opts['mode-style'], {})
        svg.append(f'<rect x="{x+18}" y="{y+154}" width="66" height="23" fill="{selected["bg"]}"/>')
        svg.append(f'<text x="{x+25}" y="{y+171}" font-size="14" fill="{selected["fg"]}">COPY</text>')
        svg.append(f'<text x="{x+101}" y="{y+171}" font-size="13" fill="{p["muted"]}">Selection and menu colors are explicit.</text>')
    svg.append(f'<text x="28" y="918" font-size="13" fill="#b8bfd0">{len(checks)} app-controlled color pairs checked. Samples, not terminal screenshots.</text></g></svg>')
    (ROOT/'preview/theme-readability.svg').write_text('\n'.join(svg)+'\n',encoding='utf-8',newline='\n')
out = ROOT / 'dist/theme-contrast.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(dict(passed=not failed, checkedPairs=len(checks), checks=checks), indent=2) + '\n')
for c in failed:
    print(f"FAIL {c['theme']} / {c['role']}: {c['ratio']} < {c['required']} ({c['foreground']} on {c['background']})")
print(f'{len(checks)} shipped UI color pairs checked; {len(failed)} failures')
sys.exit(bool(failed))
