"""keyboard.js labels its keys in the page's language, read from <html lang> each time it comes up
(spec §6.2). Needs node.

  uv run --no-project --with pytest python -m pytest -q kiosk/test_keyboard_words.py
"""
import json
import shutil
import subprocess
from pathlib import Path

KEYBOARD = Path(__file__).with_name('keyboard.js')
NODE = shutil.which('node') or 'node'
# keyboard.js only listens and starts a timer when it loads; the rest needs no DOM
RUN = '''
const vm = require('vm'), fs = require('fs');
const ctx = { document: { documentElement: { lang: '' }, addEventListener() {} }, setInterval() {} };
ctx.window = ctx;
vm.runInNewContext(fs.readFileSync(process.argv[1], 'utf8'), ctx);
process.stdout.write(JSON.stringify(JSON.parse(process.argv[2]).map(lang => {
  ctx.document.documentElement.lang = lang;
  const w = ctx.ThinkSmartKeyboard.words();
  return [w.space, w.keys.done, w.keys.next];
})));
'''


def test_the_keys_follow_the_pages_language():
    langs = ['', 'zh-Hans', 'zh-CN', 'zh', 'zh-Hant', 'zh-TW', 'zh-HK', 'en', 'en-HK', 'fr']
    out = subprocess.run([NODE, '-e', RUN, str(KEYBOARD), json.dumps(langs)], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    hans, hant, en = ['空格', '完成', '下一项'], ['空格', '完成', '下一項'], ['space', 'Done', 'Next']
    assert json.loads(out.stdout) == [hans, hans, hans, hans, hant, hant, hant, en, en, en]


def test_the_keys_and_the_redraw_use_the_words():
    # render() and show() need a DOM: read the source for what words() alone can't show
    src = KEYBOARD.read_text(encoding='utf-8')
    assert "'{space}': '空格'" not in src and 'ENTER_LABELS' not in src
    assert 'words().space' in src and 'words().keys.done' in src and 'kb.words !== w' in src
