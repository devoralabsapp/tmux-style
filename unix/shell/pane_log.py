"""Capture an owned tmux pane's output in three rotating 10 MiB segments."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


SEGMENT_BYTES = 10 * 1024 * 1024
OPTION = '@tmx_log_dir'


def record(directory):
    path = directory / 'pane.log'
    with (directory / 'writer.lock').open('xb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with path.open('xb'):
            pass
        size = 0
        for block in iter(lambda: sys.stdin.buffer.read1(65536), b''):
            remaining = memoryview(block)
            while remaining:
                if size == SEGMENT_BYTES:
                    previous = directory / 'pane.log.1'
                    if previous.exists():
                        previous.replace(directory / 'pane.log.2')
                    path.replace(previous)
                    size = 0
                piece = remaining[:SEGMENT_BYTES - size]
                with path.open('ab') as stream:
                    stream.write(piece)
                size += len(piece)
                remaining = remaining[len(piece):]


def tmux(*args):
    result = subprocess.run(['tmux', '-L', 'tmux-style', *args], check=True,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.rstrip('\n')


def writer_running(directory):
    if directory is None:
        return False
    try:
        with (directory / 'writer.lock').open('rb') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    except FileNotFoundError:
        pass
    return False


def control(action, asset_root, pane):
    log_root = asset_root.with_name(asset_root.name + '-logs')
    log_root.mkdir(mode=0o700, exist_ok=True)
    if log_root.is_symlink() or log_root.stat().st_uid != os.getuid() or log_root.stat().st_mode & 0o077:
        raise ValueError('The TMX log directory must be private and owned by this account.')
    with (log_root / 'control.lock').open('ab') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        saved = tmux('show-options', '-pqv', '-t', pane, OPTION)
        previous = Path(saved) if saved and Path(saved).parent == log_root else None
        active = writer_running(previous)
        if action == 'status' or (action == 'start' and active):
            status = 'active' if active else 'stopped'
            print(f'Pane log: {status}' + (f' ({previous / "pane.log"})' if previous else ''))
            return
        if action == 'stop':
            if not active:
                print('Pane log: stopped')
                return
            tmux('pipe-pane', '-t', pane)
            for _ in range(100):
                if not writer_running(previous):
                    break
                time.sleep(0.02)
            print(f'Pane log stopped: {previous / "pane.log"}')
            return
        if tmux('display-message', '-p', '-t', pane, '#{pane_pipe}') != '0':
            raise ValueError('This pane already has an output pipe.')
        directory = Path(tempfile.mkdtemp(prefix=f'pane-{pane[1:]}-', dir=log_root))
        tmux('set-option', '-p', '-t', pane, OPTION, str(directory), ';',
             'set-option', '-p', '-t', pane, '@tmx_log_python', sys.executable)
        tmux('pipe-pane', '-o', '-t', pane,
             'umask 077; exec #{q:@tmx_log_python} #{q:TMUX_STYLE_HOME}/shell/pane_log.py write #{q:@tmx_log_dir}')
        for _ in range(100):
            if writer_running(directory) and (directory / 'pane.log').exists():
                print(f'Pane log started: {directory / "pane.log"}')
                return
            time.sleep(0.02)
        raise ValueError('The pane logger did not start. Run tmx log status.')


if __name__ == '__main__':
    try:
        os.umask(0o077)
        if sys.argv[1] == 'write':
            record(Path(sys.argv[2]))
        else:
            control(sys.argv[1], Path(sys.argv[2]), sys.argv[3])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'TMX pane log: {error}')
