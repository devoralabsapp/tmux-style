"""Exercise the installed Linux/macOS workspace against a real isolated tmux."""
import fcntl
import base64
import json
import os
from pathlib import Path
import pty
import re
import signal
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='ts-'))
home = work / "home with $HOME spaces'"
home.mkdir()
env = dict(os.environ, HOME=str(home), TMUX_TMPDIR=str(work), TERM='xterm-256color')
env.pop('TMUX', None)
env.pop('XDG_DATA_HOME', None)
env['SHELL'] = shutil.which('bash')
env['skip_global_compinit'] = '1'  # avoid distribution-wide completion prompts in the fake home
launcher = home / '.local/bin/tmx'
legacy_launcher = home / '.local/bin/tmux-style'
data = home / '.local/share/tmux-style'
checks = []
pid = None
master = None
probe_index = 0
terminal_output = bytearray()


def drain_terminal(fd):
    try:
        while True:
            chunk = os.read(fd, 8192)
            if not chunk:
                return
            terminal_output.extend(chunk)
    except OSError:
        pass


def reap_child():
    global pid
    if not pid:
        return
    for _ in range(40):
        if os.waitpid(pid, os.WNOHANG)[0]:
            pid = None
            return
        time.sleep(.05)
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    pid = None


def run(*args, ok=True, **kwargs):
    result = subprocess.run([str(a) for a in args], env=env, text=True, timeout=15,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if ok and result.returncode:
        raise AssertionError((args, result.stdout, result.stderr))
    return result


def tm(*args):
    return run('tmux', '-L', 'tmux-style', *args).stdout.strip()


def wait_for(predicate, timeout=8):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError('Timed out waiting for tmux state')


def start_client(*args):
    global pid, master
    pid, master = pty.fork()
    if pid == 0:
        os.execvpe('bash', ['bash', str(launcher), *args], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 38, 170, 0, 0))
    threading.Thread(target=drain_terminal, args=(master,), daemon=True).start()


def in_shell(pane, command):
    global probe_index
    probe_index += 1
    result = work / f'shell-probe-{probe_index}'
    tm('send-keys', '-t', pane, '-l', command + '; printf "%s\\n" "$?" > ' + shlex.quote(str(result)))
    tm('send-keys', '-t', pane, 'Enter')
    wait_for(lambda: result.exists() and bool(result.read_text().strip()))
    assert result.read_text().strip() == '0', (command, result.read_text(), tm('capture-pane', '-p', '-t', pane))


def session_theme(name):
    return tm('show-option', '-qv', '-t', name, '@tmux_style_theme')


try:
    tested_version = run('tmux', '-V').stdout.strip()
    print('Testing:', tested_version, os.uname().sysname, flush=True)
    # Existing configuration/shell profile and symlink must remain byte-identical.
    original = home / 'original.conf'
    original.write_text('# existing user configuration\n')
    (home / '.tmux.conf').symlink_to(original.name)
    for name in ['.bashrc', '.zshrc']:
        (home / name).write_text('# existing shell profile\n')
    assert run('bash', ROOT / 'unix/install.sh', '--theme', 'invalid', ok=False).returncode
    assert not data.exists()
    run('bash', ROOT / 'unix/install.sh', '--theme', 'black')
    assert run(launcher, 'version').stdout.strip() == (ROOT / 'VERSION').read_text().strip()
    assert run(legacy_launcher, 'version').stdout == run(launcher, 'version').stdout
    assert len(run(launcher, 'themes').stdout.splitlines()) == 9
    first_backup = Path((data / 'previous-backup').read_text().strip())
    first_launcher = launcher.read_bytes()
    checks.append('install without base config; paths with spaces, dollar and apostrophe')
    print('PASS:', checks[-1], flush=True)

    start_client()
    wait_for(lambda: len(run('tmux', '-L', 'tmux-style', 'list-panes', '-F', '#{pane_id}', ok=False).stdout.splitlines()) == 3)
    before = tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
    assert len(before.splitlines()) == 3
    for theme in run(launcher, 'themes').stdout.splitlines():
        run(launcher, 'theme', theme)
        assert tm('show-option', '-qv', '-t', 'TMUX', '@tmux_style_theme') == theme
        assert before == tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
        assert tm('show-option', '-gv', 'status-position') == 'bottom'
    checks.append('nine themes switch in place; same panes/processes; bottom status')
    print('PASS:', checks[-1], flush=True)

    primary = tm('list-panes', '-t', 'TMUX:1', '-F', '#{pane_id}').splitlines()[0]
    in_shell(primary, 'type theme >/dev/null && type tmx >/dev/null && type tmux-style >/dev/null')
    in_shell(primary, 'tmx_prompt_colors; test -n "$TMX_PROMPT_FG" && test -n "$TMX_PROMPT_BG" && test "${PS1#*48;2;}" != "$PS1"')
    painted = run(launcher, 'paint', 'printf', 'success 42 /tmp/result\n').stdout
    assert '\x1b[38;2;' in painted and 'success' in painted
    assert run(launcher, 'paint', 'bash', '-c', 'exit 7', ok=False).returncode == 7
    checks.append('scoped cwd prompt has explicit RGB foreground/background; opt-in paint retains exit code')
    # Real copy-mode key, paste-buffer key, SIGINT and nested OSC52 byte flow.
    clip_pane = tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-t', 'TMUX', '-n', 'clipboard',
                   'printf TMX_COPY_MARKER; sleep 60')
    wait_for(lambda: 'TMX_COPY_MARKER' in tm('capture-pane', '-p', '-t', clip_pane))
    tm('copy-mode', '-t', clip_pane)
    tm('send-keys', '-t', clip_pane, '-X', 'start-of-line')
    tm('send-keys', '-t', clip_pane, '-X', 'begin-selection')
    tm('send-keys', '-t', clip_pane, '-X', 'end-of-line')
    tm('send-keys', '-t', clip_pane, 'C-c')
    wait_for(lambda: run('tmux','-L','tmux-style','show-buffer',ok=False).stdout.strip() == 'TMX_COPY_MARKER')
    wait_for(lambda: tm('display-message','-p','-t',clip_pane,'#{pane_in_mode}') == '0')
    tm('kill-window','-t',clip_pane)
    start = len(terminal_output)
    marker = 'TMX_SSH_CLIPBOARD'
    in_shell(primary, 'printf ' + marker + ' | SSH_CONNECTION=test bash "$TMUX_STYLE_HOME/yank.sh"')
    wait_for(lambda: base64.b64encode(marker.encode()) in terminal_output[start:])
    nested_conf = work/'nested-clipboard.conf'
    nested_conf.write_text("set -s set-clipboard on\nset -as terminal-features ',screen*:clipboard,tmux*:clipboard'\n")
    run('tmux','-L','clipboard-inner','-f',nested_conf,'new-session','-d','-s','nested','sleep 60')
    try:
        tm('send-keys','-t',primary,'-l','TMUX= tmux -L clipboard-inner attach-session -t nested')
        tm('send-keys','-t',primary,'Enter')
        wait_for(lambda: bool(run('tmux','-L','clipboard-inner','list-clients','-F','#{client_name}').stdout.strip()))
        start = len(terminal_output)
        marker = 'TMX_NESTED_CLIPBOARD'
        run('tmux','-L','clipboard-inner','load-buffer','-w','-',input=marker)
        wait_for(lambda: base64.b64encode(marker.encode()) in terminal_output[start:])
        assert tm('show-buffer') == marker
    finally:
        run('tmux','-L','clipboard-inner','kill-server',ok=False)
    wait_for(lambda: tm('display-message','-p','-t',primary,'#{pane_current_command}') == 'bash')
    in_shell(primary, ':')
    paste_file = work/'pasted-command'
    tm('set-buffer','printf pasted > '+shlex.quote(str(paste_file)))
    tm('select-window','-t',primary)
    tm('select-pane','-t',primary)
    os.write(master, b'\x16')
    time.sleep(.2)
    assert not paste_file.exists(), 'Paste executed without Enter'
    tm('send-keys','-t',primary,'Enter')
    wait_for(paste_file.exists)
    assert paste_file.read_text() == 'pasted'
    interrupted = work/'interrupted-status'
    tm('send-keys','-t',primary,'-l','sleep 30')
    tm('send-keys','-t',primary,'Enter')
    time.sleep(.2)
    os.write(master, b'\x03')
    time.sleep(.15)
    tm('send-keys','-t',primary,'-l','printf "%s" "$?" > '+shlex.quote(str(interrupted)))
    tm('send-keys','-t',primary,'Enter')
    wait_for(lambda: interrupted.exists() and bool(interrupted.read_text()))
    assert interrupted.read_text() == '130', interrupted.read_text()
    checks.append('Ctrl-C copies in copy mode and still sends SIGINT outside it; Ctrl-V pastes without auto-execution; SSH/nested OSC52 reaches the outer terminal')
    run(launcher, 'new', 'lab', '--theme', 'paper', '-d')
    lab_pane = tm('list-panes', '-t', 'lab:1', '-F', '#{pane_id}').splitlines()[0]
    assert len(tm('list-panes', '-t', 'lab:1', '-F', '#{pane_id}').splitlines()) == 3
    stable = tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
    assert run(launcher, 'new', 'lab', '-d', ok=False).returncode
    assert run(launcher, 'attach', 'missing', ok=False).returncode
    assert run(launcher, 'attach', '-t', ok=False).returncode
    assert run(launcher, 'theme', 'neon', ok=False).returncode  # ambiguous outside two sessions
    assert 'lab' in run(launcher, 'list').stdout and 'TMUX' in run(launcher, 'ls').stdout
    in_shell(primary, 'theme code')
    assert session_theme('TMUX') == 'code' and session_theme('lab') == 'paper'
    run(launcher, 'theme', 'hacker', '--session', 'lab')
    assert session_theme('TMUX') == 'code' and session_theme('lab') == 'hacker'
    assert tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}') == stable
    checks.append('named sessions, duplicate/missing validation, list and independent live themes')
    print('PASS:', checks[-1], flush=True)

    new_pane = tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-t', 'lab', '-n', 'extra')
    wait_for(lambda: '#020805' in tm('show-option', '-wv', '-t', new_pane, 'window-style'))
    code_pane = tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-t', 'TMUX', '-n', 'extra')
    wait_for(lambda: '#1e1e1e' in tm('show-option', '-wv', '-t', code_pane, 'window-style'))
    checks.append('new windows inherit their own session palette')

    # Both a shell command and Ctrl-a t invoke the real native menu.
    run(launcher, 'theme', 'paper', '-t', 'lab')
    start = len(terminal_output)
    tm('send-keys', '-t', primary, '-l', 'theme')
    tm('send-keys', '-t', primary, 'Enter')
    wait_for(lambda: b'Choose a theme for this session' in terminal_output[start:])
    os.write(master, b'8')
    wait_for(lambda: session_theme('TMUX') == 'hacker')
    assert session_theme('lab') == 'paper'
    start = len(terminal_output)
    os.write(master, b'\x01t')
    wait_for(lambda: b'Choose a theme for this session' in terminal_output[start:])
    os.write(master, b'7')
    wait_for(lambda: session_theme('TMUX') == 'code')
    checks.append('bare theme command and Ctrl-a t menu change only the current session')

    # Real client switching, detaching and reattaching preserve every pane PID.
    in_shell(primary, 'tmx attach lab')
    wait_for(lambda: tm('list-clients', '-F', '#{session_name}') == 'lab')
    in_shell(lab_pane, 'tmx attach TMUX')
    wait_for(lambda: tm('list-clients', '-F', '#{session_name}') == 'TMUX')
    stable = tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
    in_shell(primary, 'tmx detach')
    wait_for(lambda: not tm('list-clients'))
    reap_child()
    os.close(master)
    master = None
    start_client('attach', '-t', 'lab')
    wait_for(lambda: tm('list-clients', '-F', '#{session_name}') == 'lab')
    assert stable == tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
    in_shell(lab_pane, 'tmx attach TMUX')
    wait_for(lambda: tm('list-clients', '-F', '#{session_name}') == 'TMUX')
    checks.append('attach by name, switch, detach and reattach retain running processes')

    run(launcher, 'theme', 'neon', '--default')
    assert session_theme('TMUX') == 'code' and session_theme('lab') == 'paper'
    run(launcher, 'new', 'fresh', '-d')
    assert session_theme('fresh') == 'neon'
    tm('kill-session', '-t', '=fresh')
    tm('source-file', str(data / 'entry.conf'))
    assert session_theme('TMUX') == 'code' and session_theme('lab') == 'paper'
    checks.append('new-session defaults and reload preserve existing per-session choices')

    zsh = shutil.which('zsh')
    if zsh:
        zdot = home / 'zsh settings'
        zdot.mkdir()
        zenv = 'export TMUX_STYLE_TEST_ZSHENV=loaded\n'
        if os.environ.get('TMX_TEST_ZSH_MODULE_PATH'):
            zenv += 'module_path=(' + shlex.quote(os.environ['TMX_TEST_ZSH_MODULE_PATH']) + ' $module_path)\n'
            functions = os.environ['TMX_TEST_ZSH_MODULE_PATH'].replace('/lib/zsh/', '/share/zsh/') + '/functions'
            zenv += 'fpath=(' + shlex.quote(functions) + '/*(/) $fpath)\n'
        zrc = "export TMUX_STYLE_TEST_ZSHRC=loaded\nprecmd() { PROMPT='%F{blue}%~%f > '; }\nPS1='TMUX_STYLE_TEST_READY> '\n"
        (zdot / '.zshenv').write_text(zenv)
        (zdot / '.zshrc').write_text(zrc)
        tm('set-environment', '-g', 'ZDOTDIR', str(zdot))
        tm('set-option', '-g', 'default-shell', zsh)
        zsh_pane = tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-t', 'lab', '-n', 'zsh')
        try:
            wait_for(lambda: 'TMX ' in tm('capture-pane', '-p', '-t', zsh_pane))
        except AssertionError:
            print('Zsh startup output:', tm('capture-pane', '-p', '-t', zsh_pane), flush=True)
            raise
        in_shell(zsh_pane, 'test "$TMUX_STYLE_TEST_ZSHENV" = loaded && test "$TMUX_STYLE_TEST_ZSHRC" = loaded && theme hacker')
        assert session_theme('lab') == 'hacker' and session_theme('TMUX') == 'code'
        in_shell(zsh_pane, 'theme prism')
        wait_for(lambda: 'TMX ' in tm('capture-pane', '-p', '-t', zsh_pane))
        in_shell(zsh_pane, 'test "$TMX_PROMPT_THEME" = prism && test "$ZSH_HIGHLIGHT_VERSION" = 0.8.0')
        cwd_line = [line for line in tm('capture-pane', '-p', '-e', '-t', zsh_pane).splitlines() if 'TMX ' in line][-1]
        cwd_rgb = '255;122;138' if os.uname().sysname == 'Darwin' else '229;233;255'
        assert '38;2;'+cwd_rgb in cwd_line and '48;2;17;19;31' in cwd_line, cwd_line
        # Inspect the actual cells while editing, before executing the command.
        tm('send-keys', '-t', zsh_pane, '-l', 'printf "success 42 /tmp/prism-result\\n"')
        time.sleep(.3)
        editing = tm('capture-pane', '-p', '-e', '-t', zsh_pane)
        typed = [line for line in editing.splitlines() if '/tmp/prism-result' in line][-1]
        assert len(set(re.findall(r'\x1b\[[0-9;]*m', typed))) >= 2, typed
        tm('send-keys', '-t', zsh_pane, 'Enter')
        wait_for(lambda: any('success' in line and '/tmp/prism-result' in line and 'printf' not in line
                             for line in tm('capture-pane', '-p', '-t', zsh_pane).splitlines()))
        output = [line for line in tm('capture-pane', '-p', '-e', '-t', zsh_pane).splitlines()
                  if '/tmp/prism-result' in line and 'printf' not in line][-1]
        assert len(set(re.findall(r'\x1b\[[0-9;]*m', output))) >= 3, output
        # The output renderer must bypass pipelines/redirection and retain errors.
        in_shell(zsh_pane, 'test "$(printf "success 42")" = "success 42"; grep missing /dev/null; test "$?" = 1')
        in_shell(zsh_pane, 'tmx refresh; tmx refresh; test "$TMX_PROMPT_THEME" = prism')
        in_shell(zsh_pane, 'theme paper')
        in_shell(zsh_pane, 'test ${#ZSH_HIGHLIGHT_HIGHLIGHTERS} = 0')
        checks.append('Prism Zsh edits and ordinary output have distinct real terminal colors; pipelines and exit codes preserved')
        assert (zdot / '.zshenv').read_text() == zenv and (zdot / '.zshrc').read_text() == zrc
        tm('set-option', '-g', 'default-shell', env['SHELL'])
        tm('set-environment', '-gu', 'ZDOTDIR')
        checks.append('Zsh theme helper preserves custom ZDOTDIR and user startup files')
    checks.append('Bash theme helper is scoped to owned panes; shell profiles unchanged')

    long_title = 'workspace-with-a-full-length-name-0123456789'
    tm('rename-window', long_title)
    assert long_title in tm('display-message', '-p', '#{E:window-status-current-format}')
    checks.append('long window names have no configured character truncation')
    os.write(master, b'\x01')
    wait_for(lambda: tm('display-message', '-p', '#{client_prefix}') == '1')
    time.sleep(1.55)
    assert tm('display-message', '-p', '#{client_prefix}') == '1'
    os.write(master, b'z')
    wait_for(lambda: tm('display-message', '-p', '#{window_zoomed_flag}') == '1')
    timeout = run('tmux', '-L', 'tmux-style', 'show-option', '-gqv', 'prefix-timeout', ok=False).stdout.strip()
    if timeout:
        assert timeout == '2000'
        os.write(master, b'\x01')
        time.sleep(2.2)
        # Native tmux checks expiration when the next key arrives, rather than
        # clearing the PREFIX indicator on a timer. Expired z must not unzoom.
        os.write(master, b'z')
        wait_for(lambda: tm('display-message', '-p', '#{client_prefix}') == '0')
        assert tm('display-message', '-p', '#{window_zoomed_flag}') == '1'
        os.write(master, b'\x15')  # clear the literal z from the shell input
        checks.append('prefix accepts a command at 1.55s and rejects it after 2s')
    else:
        checks.append('older tmux prefix stays pending (no native timeout option)')
    tm('resize-pane', '-Z')
    os.write(master, b'\x1b[24~')
    wait_for(lambda: tm('show-option', '-v', 'prefix') == 'None')
    run(launcher, 'theme', 'ember', '--session', 'TMUX')
    assert tm('show-option', '-v', 'prefix') == 'None'
    os.write(master, b'\x1b[24~')
    wait_for(lambda: tm('show-option', '-Av', 'prefix') == 'C-a')
    checks.append('real F12 pass-through toggles off and on')
    metric_sample = run(launcher, 'metrics').stdout.strip()
    assert re.fullmatch(r'CPU \d+%  RAM \d+%', metric_sample), metric_sample
    assert all(0 <= int(n) <= 100 for n in re.findall(r'\d+', metric_sample)), metric_sample
    checks.append('local operating-system CPU/RAM sampling')
    assert run(launcher, 'restore', ok=False).returncode
    assert run(launcher, 'uninstall', ok=False).returncode
    assert data.exists()
    checks.append('restore refuses to remove assets while sessions are running')
    # Close every tab/pane of only the calling session; an outer call is invalid.
    stable = tm('list-panes', '-a', '-F', '#{session_name}:#{pane_id}:#{pane_pid}')
    assert run(launcher, 'exit', ok=False).returncode
    run(launcher, 'new', 'close-me', '-d')
    exit_pane = tm('list-panes', '-t', 'close-me', '-F', '#{pane_id}').splitlines()[0]
    tm('new-window', '-d', '-t', 'close-me', '-n', 'extra')
    wait_for(lambda: 'TMX ' in tm('capture-pane', '-p', '-t', exit_pane))
    in_shell(exit_pane, 'tmx exit extra; test "$?" != 0')
    tm('send-keys', '-t', exit_pane, '-l', 'tmx exit')
    tm('send-keys', '-t', exit_pane, 'Enter')
    wait_for(lambda: run('tmux', '-L', 'tmux-style', 'has-session', '-t', '=close-me', ok=False).returncode != 0)
    assert tm('list-panes', '-a', '-F', '#{session_name}:#{pane_id}:#{pane_pid}') == stable
    checks.append('tmx exit closes all tabs/panes of its current session; other session processes survive; outer/argument calls rejected')
    tm('kill-server')
    reap_child()
    os.close(master)
    master = None

    run('bash', ROOT / 'unix/install.sh', '--theme', 'code')
    assert first_backup != Path((data / 'previous-backup').read_text().strip())
    run(launcher, 'restore')
    assert launcher.read_bytes() == first_launcher
    assert (data / 'previous-backup').read_text().strip() == str(first_backup)
    run(launcher, 'restore')
    assert not launcher.exists() and not legacy_launcher.exists() and not data.exists()
    assert (home / '.tmux.conf').is_symlink()
    assert original.read_text() == '# existing user configuration\n'
    assert all((home / p).read_text() == '# existing shell profile\n' for p in ['.bashrc', '.zshrc'])
    checks.append('upgrade, exact restore and uninstall preserve dotfiles and symlink')

    # Do not take over another tool's short command during installation.
    launcher.write_text('#!/bin/sh\necho another-tool\n')
    launcher.chmod(0o755)
    conflicting = launcher.read_bytes()
    assert run('bash', ROOT / 'unix/install.sh', ok=False).returncode
    assert launcher.read_bytes() == conflicting and not data.exists()
    launcher.unlink()
    original_legacy = '#!/bin/sh\necho original-user-command\n'
    legacy_launcher.write_text(original_legacy)
    legacy_launcher.chmod(0o755)
    run('bash', ROOT / 'unix/install.sh', '--theme', 'black')
    run('bash', ROOT / 'unix/install.sh', '--theme', 'neon')
    # Another tmux socket and every unrelated user file must survive uninstall.
    run('tmux', '-L', 'user-unrelated', '-f', '/dev/null', 'new-session', '-d', '-s', 'keep')
    unrelated = run('tmux', '-L', 'user-unrelated', 'list-panes', '-F', '#{pane_id}:#{pane_pid}').stdout
    try:
        installed_command = launcher.read_bytes()
        launcher.write_bytes(installed_command + b'\n# user edit\n')
        assert run(legacy_launcher, 'uninstall', ok=False).returncode
        assert data.exists() and launcher.read_bytes().endswith(b'# user edit\n')
        launcher.write_bytes(installed_command)
        run(launcher, 'uninstall')
        assert not launcher.exists() and not data.exists()
        assert legacy_launcher.read_text() == original_legacy
        assert list((home / '.local/share/tmux-style-backups').glob('uninstall.*/data/install.id'))
        assert run('tmux', '-L', 'user-unrelated', 'list-panes', '-F', '#{pane_id}:#{pane_pid}').stdout == unrelated
    finally:
        run('tmux', '-L', 'user-unrelated', 'kill-server', ok=False)
    assert (home / '.tmux.conf').is_symlink() and original.read_text() == '# existing user configuration\n'
    assert all((home / p).read_text() == '# existing shell profile\n' for p in ['.bashrc', '.zshrc'])
    checks.append('tmx alias compatibility, command collision protection and full uninstall across upgrades')
    checks.append('uninstall protects edited commands, original launcher, backups, dotfiles and unrelated tmux server')

    # A stale/unsupported tmux must be rejected before the installer writes data.
    fakebin = work / 'fake-bin'
    fakebin.mkdir()
    fake = fakebin / 'tmux'
    fake.write_text('#!/bin/sh\nprintf "tmux 3.1c\\n"\n')
    fake.chmod(0o755)
    env['PATH'] = str(fakebin) + ':' + env['PATH']
    assert run('bash', ROOT / 'unix/install.sh', ok=False).returncode
    assert not data.exists()
    checks.append('unsupported tmux rejected before writes')
    report = dict(platform=os.uname().sysname, architecture=os.uname().machine,
                  tmux=tested_version, metricSample=metric_sample, checks=checks)
    report_path = ROOT / 'dist' / ('unix-test-' + os.uname().sysname.lower() + '.json')
    report_path.parent.mkdir(exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
except BaseException:
    diagnostic = terminal_output.decode('utf-8', errors='replace').replace(os.uname().nodename, 'demo-host')
    diagnostic = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\([AB]', '', diagnostic)
    print('Captured test terminal:', diagnostic[-2500:], flush=True)
    raise
finally:
    env['PATH'] = os.environ['PATH']
    try:
        run('tmux', '-L', 'tmux-style', 'kill-server', ok=False)
    finally:
        reap_child()
        if master is not None:
            os.close(master)
    shutil.rmtree(work)
