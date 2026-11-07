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
    control_end = re.compile(rb'\x1b\\|[\x07\x18\x1a]')
    csi_end = re.compile(rb'[\x18\x1a\x40-\x7e]')
    control_limit = 4096  # TMX's own markers are much smaller than this.

    def __init__(self, colors, nonce):
        self.colors = colors
        self.nonce = nonce.encode()
        self.theme = 'midnight'
        self.command = False
        self.alt = False
        self.styled = False
        self.native = False
        self.pending = b''
        self.streaming_control = None
        self.enabled = True
        self.utf8 = codecs.getincrementaldecoder('utf-8')('surrogateescape')

    def plain(self, data):
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
        if self.streaming_control:
            stop = self.streaming_control.search(data)
            if not stop:
                # Preserve an ESC that might be the first byte of a split ST.
                if self.streaming_control is self.control_end and data.endswith(b'\x1b'):
                    self.pending = b'\x1b'
                    return data[:-1]
                return data
            at = stop.end()
            out.append(data[:at])
            self.streaming_control = None
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
                terminator = self.csi_end
            elif kind in (b']', b'P', b'_', b'^'):
                terminator = self.control_end
            else:
                terminator = None
            end += 1
            if terminator:
                stop = terminator.search(data, end)
                if not stop:
                    if len(data) - esc <= self.control_limit:
                        self.pending = data[esc:]
                    else:
                        # Stream long control strings verbatim. The pane must
                        # not buffer gigabytes waiting for an application to
                        # terminate a sequence, or color bytes inside it.
                        self.streaming_control = terminator
                        limit = len(data)
                        if terminator is self.control_end and data.endswith(b'\x1b'):
                            limit -= 1
                            self.pending = b'\x1b'
                        out.append(data[esc:limit])
                    break
                end = stop.end()
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
