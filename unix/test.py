"""Exercise the installed Linux/macOS workspace against a real isolated tmux."""
import fcntl
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
    wait_for(result.exists)
    assert result.read_text().strip() == '0', (command, tm('capture-pane', '-p', '-t', pane))


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
    assert len(run(launcher, 'themes').stdout.splitlines()) == 8
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
    checks.append('eight themes switch in place; same panes/processes; bottom status')
    print('PASS:', checks[-1], flush=True)

    primary = tm('list-panes', '-t', 'TMUX:1', '-F', '#{pane_id}').splitlines()[0]
    in_shell(primary, 'type theme >/dev/null && type tmx >/dev/null && type tmux-style >/dev/null')
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
        zrc = "export TMUX_STYLE_TEST_ZSHRC=loaded\nPS1='TMUX_STYLE_TEST_READY> '\n"
        (zdot / '.zshenv').write_text(zenv)
        (zdot / '.zshrc').write_text(zrc)
        tm('set-environment', '-g', 'ZDOTDIR', str(zdot))
        tm('set-option', '-g', 'default-shell', zsh)
        zsh_pane = tm('new-window', '-d', '-P', '-F', '#{pane_id}', '-t', 'lab', '-n', 'zsh')
        wait_for(lambda: 'TMUX_STYLE_TEST_READY>' in tm('capture-pane', '-p', '-t', zsh_pane))
        in_shell(zsh_pane, 'test "$TMUX_STYLE_TEST_ZSHENV" = loaded && test "$TMUX_STYLE_TEST_ZSHRC" = loaded && theme hacker')
        assert session_theme('lab') == 'hacker' and session_theme('TMUX') == 'code'
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
