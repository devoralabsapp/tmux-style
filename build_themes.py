"""Generate standalone alternatives from the original Midnight configuration."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent
BASE = (ROOT / 'tmux.conf').read_text(encoding='utf-8')
ORIGINAL = ['#161925', '#e0e6f5', '#b8a1f7', '#a5aec6', '#75d7e8',
            '#a6d6a0', '#f0c674', '#f28b98', '#202435', '#292e42', '#3b425b']
THEMES = {
    'aurora': {
        'name': 'Aurora', 'subtitle': 'Mint accents. Lavender details. Tabs on top.',
        'colors': ['#182722','#e1eee6','#c5b5ed','#a7bdb1','#9fe4be',
                   '#a8d5a2','#eed49f','#ed9ca8','#22382e','#2a3b33','#425c4c'],
        'pane': '#12201b', 'position': 'top', 'rows': 1,
    },
    'ember': {
        'name': 'Ember', 'subtitle': 'Warm amber. Charcoal canvas. Numbered pane headers.',
        'colors': ['#241d1a','#eee1d2','#e8bf86','#c0ac98','#f3a66b',
                   '#b9cc93','#f0cd83','#ed9490','#32261f','#3b2d24','#67503e'],
        'pane': '#1b1715', 'position': 'bottom', 'rows': 1,
    },
    'paper': {
        'name': 'Paper / Ink', 'subtitle': 'Warm paper. Ink-black tabs. A calm light workspace.',
        'colors': ['#e9e2d5','#302e2a','#56634e','#625d54','#292724',
                   '#527344','#f0d8a5','#ac454b','#ddd5c7','#ddd5c7','#b8ae9e'],
        'pane': '#f6f2e9', 'position': 'bottom', 'rows': 1,
    },
    'neon': {
        'name': 'Neon / Circuit', 'subtitle': 'Orchid tabs. Electric mint. Two rows of context.',
        'colors': ['#171326','#eae1fa','#bda2f2','#b4a2cd','#ef88d8',
                   '#7de3ce','#f5d38e','#fc8cae','#28203b','#302441','#53406e'],
        'pane': '#100e1b', 'position': 'bottom', 'rows': 2,
    },
}

def replace_setting(text, option, value, command='set -g'):
    pattern = rf'^{re.escape(command)} {re.escape(option)} .*$'
    result, count = re.subn(pattern, lambda _: f"{command} {option} '{value}'", text, flags=re.M)
    assert count >= 1, (option,count)
    return result

def build(slug, spec):
    palette = dict(zip(ORIGINAL,spec['colors']))
    text = re.sub(r'#[0-9a-fA-F]{6}',lambda m:palette.get(m[0],m[0]),BASE)
    text = text.replace('# MIDNIGHT / CYAN',f"# {spec['name'].upper()}")
    text = text.replace('# A quiet, single-row UI. No patched font or extra theme plugin required.',
                        '# '+spec['subtitle']+' No patched font required.')
    text = replace_setting(text,'status-position',spec['position'])
    if spec['rows']==2:
        text = replace_setting(text,'status','2')
    text = replace_setting(text,'window-style',f"bg={spec['pane']},fg={spec['colors'][1]}",'setw -g')
    text = replace_setting(text,'window-active-style',f"bg={spec['pane']},fg={spec['colors'][1]}",'setw -g')
    if slug == 'aurora':
        text = replace_setting(text,'window-status-format',
            ' [#I #{?#{e|>=:#{client_width},100},#{=14:window_name},#{=8:window_name}}]#{?window_bell_flag,!,#{?window_activity_flag,+,}} ', 'setw -g')
        text = replace_setting(text,'window-status-current-format',
            ' [#I #{?#{e|>=:#{client_width},100},#{=14:window_name},#{=8:window_name}}] ', 'setw -g')
    if slug == 'ember':
        text = re.sub(r"^midnight_status_left=.*$",
            "midnight_status_left='#[fg=#e8bf86,bold] #{?#{e|>=:#{client_width},100},#{=18:session_name},#{=10:session_name}} / #[default] '",
            text,flags=re.M)
        text = text.replace(' #I #{?',' #I:#{?')
        text += "\n# Small pane headers make a split workspace easier to scan.\n"
        text += "setw -g pane-border-status top\n"
        text += "setw -g pane-border-format '#[fg=#{?pane_active,#f3a66b,#c0ac98}] #P / #{=16:pane_current_command} '\n"
    if slug == 'paper':
        text = re.sub(r"^midnight_status_left=.*$",
            "midnight_status_left='#[fg=#302e2a,bold] #{?#{e|>=:#{client_width},100},#{=18:session_name},#{=10:session_name}} / #[default] '",
            text,flags=re.M)
        # Pale OFF badge stays readable on paper; selections use an ink-green fill.
        text = text.replace('bg=#f0d8a5#,fg=#e9e2d5','bg=#f0d8a5#,fg=#302e2a')
    if slug == 'neon':
        text = replace_setting(text,'window-status-format',
            ' #I / #{?#{e|>=:#{client_width},100},#{=14:window_name},#{=8:window_name}}#{?window_bell_flag, !,#{?window_activity_flag, +,}} ', 'setw -g')
        text = replace_setting(text,'window-status-current-format',
            ' #I / #{?#{e|>=:#{client_width},100},#{=14:window_name},#{=8:window_name}} ', 'setw -g')
        text += "\n# The native window list stays on row one; context occupies row two.\n"
        text += "set -g status-format[1] '#[bg=#302441,fg=#b4a2cd] #{?#{e|>=:#{client_width},100},PATH #{=42:pane_current_path}  /  RUN #{=14:pane_current_command},#{=24:pane_current_path}}#[align=right]#{?#{e|>=:#{client_width},100}, Ctrl-a prefix   F12 nested , F12 nested }'\n"
    return '\n'.join(line.rstrip(' \t') for line in text.splitlines())+'\n'

if __name__=='__main__':
    folder=ROOT/'themes'
    folder.mkdir(exist_ok=True)
    for slug,spec in THEMES.items():
        config=build(slug,spec)
        (folder/f'{slug}.conf').write_text(config,encoding='utf-8',newline='\n')
    (folder/'catalog.json').write_text(json.dumps(THEMES,indent=2)+'\n',encoding='utf-8')
    print('Generated:',', '.join(THEMES))
