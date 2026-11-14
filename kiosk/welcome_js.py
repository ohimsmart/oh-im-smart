"""Run the welcome page's translation code in node for the kiosk tests: i18n.js and both dictionaries,
then lines taken from welcome.html (no browser, no DOM: apply() finds no page text to translate)."""
import json
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
WELCOME = HERE / 'welcome.html'
NODE = shutil.which('node') or 'node'
PRELUDE = '''globalThis.window = globalThis;
globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2 };
globalThis.document = { documentElement: {}, body: {}, querySelectorAll: () => [],
                        createTreeWalker: () => ({ nextNode: () => null }) };
'''


def page_lines(*names):
    """The one-line `const NAME = …` definitions of welcome.html's script, in the order asked."""
    page = WELCOME.read_text(encoding='utf-8')
    found = [re.search(rf'^const {name} = .*$', page, re.M) for name in names]
    assert all(found), f'not all of {names} found in welcome.html'
    return [m[0] for m in found]


def run(expr, lang='zh-Hans', lines=()):
    """Evaluate expr (JSON out) with KioskI18n applied to lang, t defined, and lines loaded."""
    src = PRELUDE + ''.join((HERE / f).read_text(encoding='utf-8') + ';\n' for f in ('i18n.js', 'zh-Hant.js', 'en.js'))
    src += f'KioskI18n.apply({json.dumps(lang)});\nconst t = KioskI18n.t;\n' + '\n'.join(lines)
    src += f'\nprocess.stdout.write(JSON.stringify({expr}));'
    r = subprocess.run([NODE, '-e', src], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)
