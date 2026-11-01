#!/usr/bin/env python3
"""PTY display filter: the child and every command retain a real terminal."""
import errno
import codecs
import codecs
import fcntl
import json
import os
import pty
import re
import select
import signal
import sys
import termios
import tty


class Display:
    token = re.compile(rb'''https?://[^\s]+|(?:~?/|\.{1,2}/)[^\s]+|"[^"\r\n]*"|'[^'\r\n]*'|--?[A-Za-z][\w-]*|\b\d+(?:[.:/%-]\d+)*%?|\b(?:error|failed|failure|fatal|denied|exception|success|passed|running|true|enabled|warning|warn|pending|false|disabled)\b''', re.I)

    def __init__(self, colors, nonce):
        self.colors = colors
        self.nonce = nonce.encode()
        self.theme = 'midnight'
        self.command = False
        self.alt = False
        self.styled = False
        self.native = False
        self.pending = b''
        self.enabled = True
        self.utf8 = codecs.getincrementaldecoder('utf-8')('surrogateescape')
        self.utf8 = codecs.getincrementaldecoder('utf-8')('surrogateescape')

    def plain(self, data):
        # Never insert color escapes inside a multibyte glyph split by read().
        data = self.utf8.decode(data).encode('utf-8', errors='surrogateescape')
        # Never insert color escapes inside a multibyte glyph split by read().
        data = self.utf8.decode(data).encode('utf-8', errors='surrogateescape')
        if not (self.enabled and self.command) or self.alt or self.styled or self.native:
            return data
        palette = self.colors.get(self.theme, self.colors['midnight'])
        def color(role, text):
            return b'\x1b[38;2;' + palette[role].encode() + b'm' + text + b'\x1b[39m'
        parts = []
        at = 0
        for match in self.token.finditer(data):
            if at < match.start():
                parts.append(color('text', data[at:match.start()]))
            word = match[0]
            lower = word.lower()
            role = 'number'
            if lower in (b'error', b'failed', b'failure', b'fatal', b'denied', b'exception'):
                role = 'error'
            elif lower in (b'success', b'passed', b'running', b'true', b'enabled'):
                role = 'good'
            elif lower in (b'warning', b'warn', b'pending', b'false', b'disabled'):
                role = 'warning'
            elif word.startswith((b'"', b"'")):
                role = 'quote'
            elif b'/' in word or word.startswith(b'-'):
                role = 'path'
            parts.append(color(role, word))
            at = match.end()
        if at < len(data):
            parts.append(color('text', data[at:]))
        return b''.join(parts)

    def feed(self, data):
        data = self.pending + data
        self.pending = b''
        out = []
        at = 0
        while at < len(data):
            esc = data.find(b'\x1b', at)
            if esc < 0:
                out.append(self.plain(data[at:]))
                break
            out.append(self.plain(data[at:esc]))
            end = esc + 1
            if end == len(data):
                self.pending = data[esc:]
                break
            kind = data[end:end+1]
            if kind == b'[':
                end += 1
                while end < len(data) and not 0x40 <= data[end] <= 0x7e:
                    end += 1
                end += 1
            elif kind in (b']', b'P', b'_', b'^'):
                stops = [n for n in (data.find(b'\x1b\\', end+1), data.find(b'\x07', end+1)) if n >= 0]
                if not stops:
                    self.pending = data[esc:]
                    break
                stop = min(stops)
                end = stop + (1 if data[stop] == 7 else 2)
            else:
                end += 1
            if end > len(data):
                self.pending = data[esc:]
                break
            sequence = data[esc:end]
            if kind == b']' and sequence.startswith(b'\x1b]777;tmx;' + self.nonce + b';'):
                body = sequence[len(b'\x1b]777;tmx;' + self.nonce + b';'):].rstrip(b'\x07')
                mode, _, theme = body.partition(b';')
                self.theme = theme.decode('ascii', errors='ignore')
                self.command = mode == b'command'
                self.enabled = mode != b'command-off'
                self.native = self.styled = False
            else:
                out.append(sequence)
                if kind == b'[':
                    if sequence in (b'\x1b[?1049h', b'\x1b[?1047h', b'\x1b[?47h'):
                        self.alt = True
                    elif sequence in (b'\x1b[?1049l', b'\x1b[?1047l', b'\x1b[?47l'):
                        self.alt = False
                    elif sequence.endswith(b'm'):
                        # Preserve applications' ANSI styling, including backgrounds.
                        values = sequence[2:-1].split(b';')
                        if all(v in (b'', b'0', b'39', b'49', b'22', b'23', b'24', b'27') for v in values):
                            self.styled = False
                        else:
                            self.styled = True
                    elif sequence[-1:] in (b'H', b'f', b'J', b'A', b'B', b'C', b'D'):
                        self.native = True
            at = end
        return b''.join(out)


def relay(argv):
    if not argv:
        raise SystemExit('Usage: render.py SHELL [ARG ...]')
    if not os.isatty(0) or not os.isatty(1):
        os.execvp(argv[0], argv)
    with open(os.path.join(os.path.dirname(__file__), 'output-colors.json')) as source:
        colors = json.load(source)
    nonce = os.urandom(12).hex()
    pid, master = pty.fork()
    if pid == 0:
        os.environ['TMX_RENDER_ACTIVE'] = '1'
        os.environ['TMX_RENDER_TOKEN'] = nonce
        os.execvp(argv[0], argv)
    saved = termios.tcgetattr(0)
    display = Display(colors, nonce)
    def resize(*_):
        try:
            fcntl.ioctl(master, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b'\0'*8))
        except OSError:
            pass
    def stop(signum, _):
        try:
            os.killpg(pid, signum)
        except ProcessLookupError:
            pass
    signal.signal(signal.SIGWINCH, resize)
    signal.signal(signal.SIGHUP, stop)
    signal.signal(signal.SIGTERM, stop)
    def write(fd, data):
        while data:
            data = data[os.write(fd, data):]
    resize()
    try:
        tty.setraw(0)
        while True:
            ready, _, _ = select.select([0, master], [], [])
            if master in ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                write(1, display.feed(chunk))
            if 0 in ready:
                chunk = os.read(0, 65536)
                if not chunk:
                    stop(signal.SIGHUP, None)
                    break
                write(master, chunk)
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, saved)
        os.close(master)
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status) if hasattr(os, 'waitstatus_to_exitcode') else (status >> 8)


if __name__ == '__main__':
    sys.exit(relay(sys.argv[1:]))
