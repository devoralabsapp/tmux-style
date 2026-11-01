"""Streaming display invariants, independent of any command allowlist."""
import importlib.util
import json
from pathlib import Path
import unittest
import subprocess
import tempfile
import shlex

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('tmx_render', ROOT/'shell/render.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
COLORS = json.loads((ROOT/'shell/output-colors.json').read_text())


class RenderTests(unittest.TestCase):
    def test_arbitrary_output_and_fragmented_control(self):
        display = module.Display(COLORS, 'test')
        self.assertEqual(display.feed(b'\x1b]777;tmx;test;comm'), b'')
        self.assertEqual(display.feed(b'and;hacker\x07'), b'')
        output = display.feed(b'success 42 /tmp/result\r\n')
        for color in ('166;237;176', '255;224;138', '125;220;254'):
            self.assertIn(color.encode(), output)
        self.assertIn(b'\r\n', output)
        self.assertEqual(display.feed(b'\x1b]777;tmx;test;prompt;hacker\x07'), b'')
        self.assertEqual(display.feed(b'prompt 42 /tmp'), b'prompt 42 /tmp')

    def test_ansi_fullscreen_and_clipboard_are_preserved(self):
        display = module.Display(COLORS, 'test')
        display.feed(b'\x1b]777;tmx;test;command;prism\x07')
        native = b'\x1b[31merror 42\x1b[0m'
        self.assertEqual(display.feed(native), native)
        full = b'\x1b[?1049h\x1b[2J\x1b[Htop 42\x1b[?1049l'
        self.assertEqual(display.feed(full), full)
        osc = b'\x1b]52;c;Y2xpcGJvYXJk\x07'
        self.assertEqual(display.feed(osc), osc)

    def test_disable_and_paper(self):
        display = module.Display(COLORS, 'test')
        display.feed(b'\x1b]777;tmx;test;command-off;paper\x07')
        self.assertEqual(display.feed(b'error 42'), b'error 42')
        display.feed(b'\x1b]777;tmx;test;command;paper\x07')
        self.assertIn(b'166;27;50', display.feed(b'error 42'))

    def test_fragmented_unicode(self):
        display = module.Display(COLORS, 'test')
        display.feed(b'\x1b]777;tmx;test;command;prism\x07')
        data = 'kết quả'.encode()
        rendered = b''.join(display.feed(bytes([byte])) for byte in data)
        import re
        self.assertEqual(re.sub(rb'\x1b\[[0-9;]*m', b'', rendered), data)

    def test_existing_bash_debug_hook_with_quotes(self):
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory)/'debug'
            action = '''printf "%s" "user-hook's" > "$TMX_HOOK_FILE"'''
            script = 'trap '+shlex.quote(action)+''' DEBUG
export TMX_RENDER_ACTIVE=1 TMX_RENDER_TOKEN=test
source ''' + shlex.quote(str(ROOT/'shell/render.sh')) + '''
:
'''
            import os
            proc = subprocess.run(['bash','--noprofile','--norc','-c',script], env=dict(os.environ, TMX_HOOK_FILE=str(result)), capture_output=True)
            self.assertEqual(proc.returncode,0,proc.stderr)
            self.assertEqual(result.read_text(),"user-hook's")
            self.assertIn(b'777;tmx;test;command;',proc.stdout)

    def test_fragmented_unicode(self):
        display = module.Display(COLORS, 'test')
        display.feed(b'\x1b]777;tmx;test;command;prism\x07')
        data = 'kết quả'.encode()
        rendered = b''.join(display.feed(bytes([byte])) for byte in data)
        import re
        self.assertEqual(re.sub(rb'\x1b\[[0-9;]*m', b'', rendered), data)


if __name__ == '__main__':
    unittest.main()
