"""Exercise the installed Linux/macOS workspace against a real isolated tmux."""
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import signal
import shutil
import struct
import subprocess
import tempfile
import termios
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix='ts-'))
home = work / "home with $ spaces'"
home.mkdir()
env = dict(os.environ, HOME=str(home), TMUX_TMPDIR=str(work), TERM='xterm-256color')
env.pop('TMUX', None)
env.pop('XDG_DATA_HOME', None)
launcher = home / '.local/bin/tmux-style'
data = home / '.local/share/tmux-style'
checks = []
pid = None
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


try:
    print('Testing:', run('tmux', '-V').stdout.strip(), os.uname().sysname, flush=True)
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
    assert len(run(launcher, 'themes').stdout.splitlines()) == 8
    first_backup = Path((data / 'previous-backup').read_text().strip())
    first_launcher = launcher.read_bytes()
    checks.append('install without base config; paths with spaces, dollar and apostrophe')
    print('PASS:', checks[-1], flush=True)

    pid, master = pty.fork()
    if pid == 0:
        os.execvpe('bash', ['bash', str(launcher)], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 38, 170, 0, 0))
    threading.Thread(target=drain_terminal, args=(master,), daemon=True).start()
    wait_for(lambda: len(run('tmux', '-L', 'tmux-style', 'list-panes', '-F', '#{pane_id}', ok=False).stdout.splitlines()) == 3)
    before = tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
    assert len(before.splitlines()) == 3
    for theme in run(launcher, 'themes').stdout.splitlines():
        run(launcher, 'theme', theme)
        assert tm('show-option', '-gqv', '@tmux_style_theme') == theme
        assert before == tm('list-panes', '-a', '-F', '#{pane_id}:#{pane_pid}')
        assert tm('show-option', '-gv', 'status-position') == 'bottom'
    checks.append('eight themes switch in place; same panes/processes; bottom status')
    print('PASS:', checks[-1], flush=True)

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
    os.write(master, b'\x1b[24~')
    wait_for(lambda: tm('show-option', '-Av', 'prefix') == 'C-a')
    checks.append('real F12 pass-through toggles off and on')
    assert re.fullmatch(r'CPU (?:\d+|--)%  RAM (?:\d+|--)%\n', run(launcher, 'metrics').stdout)
    checks.append('local operating-system CPU/RAM sampling')
    assert run(launcher, 'restore', ok=False).returncode
    assert data.exists()
    checks.append('restore refuses to remove assets while sessions are running')
    tm('kill-server')
    reap_child()
    os.close(master)

    run('bash', ROOT / 'unix/install.sh', '--theme', 'code')
    assert first_backup != Path((data / 'previous-backup').read_text().strip())
    run(launcher, 'restore')
    assert launcher.read_bytes() == first_launcher
    assert (data / 'previous-backup').read_text().strip() == str(first_backup)
    run(launcher, 'restore')
    assert not launcher.exists() and not data.exists()
    assert (home / '.tmux.conf').is_symlink()
    assert original.read_text() == '# existing user configuration\n'
    assert all((home / p).read_text() == '# existing shell profile\n' for p in ['.bashrc', '.zshrc'])
    checks.append('upgrade, exact restore and uninstall preserve dotfiles and symlink')

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
    report = dict(platform=os.uname().sysname, architecture=os.uname().machine, checks=checks)
    report_path = ROOT / 'dist' / ('unix-test-' + os.uname().sysname.lower() + '.json')
    report_path.parent.mkdir(exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
except BaseException:
    print('Captured test terminal:', terminal_output.decode('utf-8', errors='replace')[-16000:], flush=True)
    raise
finally:
    env['PATH'] = os.environ['PATH']
    try:
        run('tmux', '-L', 'tmux-style', 'kill-server', ok=False)
    finally:
        reap_child()
    shutil.rmtree(work)
