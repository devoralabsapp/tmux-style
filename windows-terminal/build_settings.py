"""Build native Windows Terminal profiles and actions from the tmux palettes."""
from pathlib import Path
import json, uuid

ROOT=Path(__file__).resolve().parent
catalog=json.loads((ROOT.parent/'themes/catalog.json').read_text())
catalog['midnight']={'name':'Midnight','pane':'#10131e','colors':[
    '#161925','#e0e6f5','#b8a1f7','#a5aec6','#75d7e8','#a6d6a0',
    '#f0c674','#f28b98','#202435','#292e42','#3b425b']}
names={'aurora':'Aurora','midnight':'Midnight','ember':'Ember','paper':'Paper','neon':'Neon','black':'Command Line'}
schemes=[]; profiles=[]
for slug in ['aurora','midnight','ember','paper','neon','black']:
    spec=catalog[slug]; c=spec['colors']; label='Tmux Style / '+names[slug]
    scheme=dict(name=label,background=spec['pane'],foreground=c[1],cursorColor=c[4],
        selectionBackground=c[9],black=c[0],red=c[7],green=c[5],yellow=c[6],
        blue=('#456897' if slug=='paper' else '#88a8f9'),purple=c[2],
        cyan=('#426e70' if slug=='paper' else '#75d7e8'),white=c[1],
        brightBlack=c[3],brightRed=c[7],brightGreen=c[5],brightYellow=c[6],
        brightBlue=('#456897' if slug=='paper' else '#a4bdff'),brightPurple=c[2],
        brightCyan=('#426e70' if slug=='paper' else '#9fe4db'),brightWhite=c[1])
    # Paper needs strong prompt/syntax colors against its pale background.
    if slug=='paper':
        scheme.update(yellow='#8a601d',brightYellow='#8a601d',
                      green='#527344',brightGreen='#527344',brightBlack='#625d54')
    if slug=='black':
        for key in ['red','green','yellow','blue','purple','cyan']:
            scheme[key]='#bfbfbf'
        for key in ['brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan']:
            scheme[key]='#ededed'
        scheme['selectionBackground']='#333333'
    schemes.append(scheme)
    guid='{'+str(uuid.uuid5(uuid.NAMESPACE_URL,'https://local/tmux-style-windows/'+slug))+'}'
    profiles.append(dict(guid=guid,name='Tmux Style - '+names[slug],hidden=False,
        slug=slug,colorScheme=label,tabColor=c[4],font={'face':'Cascadia Mono','size':12},
        padding='14, 10, 14, 10',cursorShape='bar',historySize=20000,
        scrollbarState='hidden',useAcrylic=False,opacity=100,
        bellStyle='taskbar',startingDirectory='%USERPROFILE%'))

actions=[]; keys=[]
def action(id,name,command,key):
    id='User.TmuxStyle.'+id
    actions.append(dict(id=id,name='Workspace: '+name,command=command))
    keys.append(dict(id=id,keys=key))
action('SplitRight','split right',dict(action='splitPane',split='right',splitMode='duplicate'),'ctrl+alt+v')
action('SplitDown','split below',dict(action='splitPane',split='down',splitMode='duplicate'),'ctrl+alt+h')
action('Zoom','zoom / restore pane','togglePaneZoom','ctrl+shift+z')
action('NewTab','new tab','newTab','ctrl+shift+t')
action('ClosePane','close pane','closePane','ctrl+shift+w')
action('NextTab','next tab',dict(action='nextTab',tabSwitcherMode='disabled'),'ctrl+tab')
for direction in ['left','down','up','right']:
    action('Focus'+direction.title(),'focus '+direction,dict(action='moveFocus',direction=direction),'alt+'+direction)
    action('Resize'+direction.title(),'resize '+direction,dict(action='resizePane',direction=direction),'alt+shift+'+direction)
action('Layout','create 3-pane layout',dict(action='multipleActions',actions=[
    dict(action='newTab'),
    dict(action='splitPane',split='right',splitMode='duplicate',size=0.35),
    dict(action='splitPane',split='down',splitMode='duplicate',size=0.5),
    dict(action='moveFocus',direction='first')]),'ctrl+alt+w')
action('DuplicateTab','new tab in current profile and directory','duplicateTab','ctrl+alt+c')
action('RenameTab','rename current tab',dict(action='renameTab'),'ctrl+alt+r')
action('RenameWindow','rename current window','openWindowRenamer','ctrl+alt+shift+r')
action('LastTab','most recently used tab',dict(action='nextTab',tabSwitcherMode='mru'),'ctrl+alt+l')
action('SwapPane','swap with next pane',dict(action='swapPane',direction='nextInOrder'),'ctrl+alt+o')
action('CloseTab','close current tab','closeTab','ctrl+alt+shift+x')
action('CloseWindow','close current window','closeWindow','ctrl+alt+shift+q')
action('CopyMode','keyboard selection','markMode','ctrl+alt+[')
action('Paste','paste clipboard','paste','ctrl+alt+]')
action('MoveTabLeft','move tab left',dict(action='moveTab',direction='backward'),'ctrl+alt+shift+left')
action('MoveTabRight','move tab right',dict(action='moveTab',direction='forward'),'ctrl+alt+shift+right')
for index in range(1,10):
    action('Tab'+str(index),'select tab '+str(index),dict(action='switchToTab',index=index-1),'ctrl+alt+'+str(index))
action('EditSettings','edit Terminal settings',dict(action='openSettings',target='settingsFile'),'ctrl+alt+e')
action('FocusMode','toggle tab/title bar','toggleFocusMode','ctrl+alt+s')
action('PreviousOrderedTab','previous tab',dict(action='prevTab',tabSwitcherMode='disabled'),'ctrl+alt+left')
action('NextOrderedTab','next tab',dict(action='nextTab',tabSwitcherMode='disabled'),'ctrl+alt+right')
result=dict(profiles=profiles,schemes=schemes,actions=actions,keybindings=keys)
(ROOT/'settings.additions.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
wezterm={}
for slug,scheme in zip(names,schemes):
    c=catalog[slug]['colors']
    wezterm[slug]=dict(bar=c[0],fg=c[1],accent=c[4],muted=c[3],surface=c[9],colors=dict(
        foreground=scheme['foreground'],background=scheme['background'],
        cursor_bg=scheme['cursorColor'],cursor_fg=scheme['background'],cursor_border=scheme['cursorColor'],
        selection_bg=scheme['selectionBackground'],selection_fg=scheme['foreground'],split=c[10],
        ansi=[scheme[k] for k in ['black','red','green','yellow','blue','purple','cyan','white']],
        brights=[scheme[k] for k in ['brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite']]))
(ROOT/'wezterm-palettes.json').write_text(json.dumps(wezterm,indent=2)+'\n',encoding='utf-8')
print('Built',len(profiles),'profiles,',len(schemes),'color schemes and',len(actions),'actions.')
