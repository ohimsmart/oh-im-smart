"""The welcome page's translations (spec §6.2, §6.4): both dictionaries hold exactly the page's text
and the updater's keys, the script writes no Chinese except through t(), English keeps the wake word,
and in Chrome the whole page follows the language. Needs node; the page test needs Chrome.

  GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q kiosk/test_welcome_i18n.py
"""
import json
import re
import shutil
import subprocess
from html.parser import HTMLParser
from pathlib import Path

import pytest

from welcome_js import run

HERE = Path(__file__).parent
WELCOME = HERE / 'welcome.html'
KEYS = HERE.parent / 'update' / 'msg_keys.json'
CHINESE = re.compile(r'[　-〿一-鿿＀-￯]')     # ideographs and fullwidth punctuation
PLACEHOLDER = re.compile(r'\{(\w+)\}')
T_CALL = re.compile(r'\bt\("((?:[^"\\]|\\.)*)"')
ATTRS = ('title', 'aria-label', 'placeholder', 'data-kb-enter')
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr'}
DICTS = {'zh-Hant.js': 'UI_ZH_HANT', 'en.js': 'UI_EN'}


class Markup(HTMLParser):
    """Chinese text and attributes outside <script>, <style> and [data-no-i18n] (what i18n.js translates)."""

    def __init__(self):
        super().__init__()
        self.skip, self.found = [], set()

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if self.skip or tag in ('script', 'style') or 'data-no-i18n' in a:
            if tag not in VOID:
                self.skip.append(tag)
            return
        self.found |= {a[k].strip() for k in ATTRS if a.get(k) and CHINESE.search(a[k])}

    def handle_endtag(self, tag):
        if self.skip and self.skip[-1] == tag:
            self.skip.pop()

    def handle_data(self, data):
        if not self.skip and CHINESE.search(data):
            self.found.add(data.strip())


def scripts(page):
    return '\n'.join(re.findall(r'<script>(.*?)</script>', page, re.S))


def sources():
    page = WELCOME.read_text(encoding='utf-8')
    m = Markup()
    m.feed(page)
    calls = {json.loads(f'"{s}"') for s in T_CALL.findall(scripts(page))}
    return m.found | calls | set(json.loads(KEYS.read_text(encoding='utf-8')))


def dictionary(name):
    text = (HERE / name).read_text(encoding='utf-8')
    m = re.fullmatch(rf'// [^\n]*\nwindow\.{DICTS[name]} = (\{{.*\}});\n', text, re.S)
    assert m, f'{name}: a comment line, then window.{DICTS[name]} = {{…}};'
    return m[1], json.loads(m[1])


def chinese_outside_t(js):
    """Chinese left in the script once comments, t("…") literals, the preview data (mock) and
    needsReboot's match on an older updater's message are taken out."""
    js = re.sub(r'/\*.*?\*/', '', js, flags=re.S)
    js = re.sub(r'(?m)(^|\s)//\s.*$', '', js)
    js = T_CALL.sub('', js)
    js = re.sub(r'\nfunction mock\(m\) \{.*?\n\}\n', '\n', js, flags=re.S)
    js = re.sub(r'(?m)^const needsReboot = .*$', '', js)
    return CHINESE.findall(js)


@pytest.mark.parametrize('name', DICTS)
def test_the_dictionary_holds_exactly_the_pages_text(name):
    keys, want = set(dictionary(name)[1]), sources()
    assert sorted(want - keys) == [], 'missing'
    assert sorted(keys - want) == [], 'not on the page'


@pytest.mark.parametrize('name', DICTS)
def test_the_dictionary_is_one_sorted_entry_a_line(name):
    body, d = dictionary(name)
    assert body == json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True)


@pytest.mark.parametrize('name', DICTS)
def test_every_translation_keeps_its_placeholders(name):
    d = dictionary(name)[1]
    assert [k for k, v in d.items() if not v.strip() and k.strip()] == [], 'empty'
    assert [k for k, v in d.items() if set(PLACEHOLDER.findall(v)) != set(PLACEHOLDER.findall(k))] == []


def test_english_has_no_chinese_left():
    # the wake word aside (spec §6.3)
    en = dictionary('en.js')[1]
    assert {k: v for k, v in en.items() if CHINESE.search(v.replace('小麦', ''))} == {}


def test_the_script_writes_chinese_only_through_t():
    assert chinese_outside_t(scripts(WELCOME.read_text(encoding='utf-8'))) == []


def test_the_guard_catches_chinese_outside_t():
    ok = 'x = t("已连接 {ssid}", { ssid }); // 注释\n/* 注释 */\nfunction mock(m) {\n  a("客厅");\n}\n'
    assert chinese_outside_t(ok) == []
    assert chinese_outside_t(ok + "$('x').textContent = '已连接';\n") == list('已连接')
    assert chinese_outside_t('y = t(`已连接`);\n') == list('已连接')     # only t("…") counts


def test_every_script_the_page_loads_is_installed():
    # the system layer installs only what image/system-files.txt lists; a missing one breaks the page
    table = (HERE.parent / 'image' / 'system-files.txt').read_text(encoding='utf-8')
    installed = {line.split()[0] for line in table.splitlines() if line.startswith('kiosk/')}
    loaded = re.findall(r'<script src="([^"]+)"', WELCOME.read_text(encoding='utf-8'))
    assert 'i18n.js' in loaded and [f for f in loaded if f'kiosk/{f}' not in installed] == []


def test_english_keeps_the_wake_word():
    # spec §6.3: an entry with 小麦 keeps it in Chinese
    en = dictionary('en.js')[1]
    assert [k for k, v in en.items() if '小麦' in k and '小麦' not in v] == []


def test_t_fills_and_translates_nested_messages():
    nested = {'msg_key': '{version} 自检没通过（{why}），已退回 {old}',
              'msg_params': {'version': '1.0.2', 'old': '1.0.1', 'why': {'msg_key': '屏幕界面没有启动起来', 'msg_params': {}}}}
    expr = (f'[t("已连接 {{ssid}}", {{ ssid: "家" }}), KioskI18n.text({json.dumps(nested, ensure_ascii=False)}),'
            ' KioskI18n.text("未联网"), KioskI18n.text(null), t("不是鍵"), KioskI18n.locale]')
    assert run(expr, 'en') == ['Connected to 家', '1.0.2 failed its self-test (the screen interface did not start); went back to 1.0.1',
                               'Offline', '', '不是鍵', 'en']
    assert run('[t("连接"), KioskI18n.locale]', 'zh-Hant') == ['連線', 'zh-Hant']
    assert run('[t("连接"), KioskI18n.locale]', 'fr') == ['连接', 'zh-Hans']
    assert run('[KioskI18n.apply("en"), KioskI18n.apply("zh-Hant"), t("连接")]') == ['en', 'zh-Hant', '連線']


CHROME = shutil.which('google-chrome') or shutil.which('chromium')
STATUS = 'ip=192.168.1.9&host=ts&ssid=Home&target=http%3A%2F%2F127.0.0.1%3A8090%2F&tries=3'


@pytest.mark.skipif(not CHROME, reason='needs Chrome')
@pytest.mark.parametrize('lang, has', [
    ('en', ['<html lang="en"', 'tried 3 times', 'Device address', 'data-kb-enter="Connect"', 'aria-label="Refresh"']),
    ('zh-Hant', ['<html lang="zh-Hant"', '已重試 3 次', '裝置地址', 'data-kb-enter="連線"']),
    ('', ['<html lang="zh-Hans"', 'class="langs on"', '已重试 3 次']),
])
def test_the_page_in_chrome(tmp_path, lang, has):
    url = WELCOME.as_uri() + '?' + STATUS + (f'&lang={lang}' if lang else '')
    r = subprocess.run([CHROME, '--headless=new', '--disable-gpu', f'--user-data-dir={tmp_path}',
                        '--virtual-time-budget=3000', '--dump-dom', url], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    for s in has:
        assert s in r.stdout, s
    if lang == 'en':
        m = Markup()
        m.feed(r.stdout)
        assert m.found == set()     # every bit of the page's own text is English
