"""Which page may ask thinksmart-kiosk.py for what, and the language it keeps (no WebKit needed: gi is stubbed).

  uv run --no-project --with pytest python -m pytest -q kiosk
"""
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import threading
import types

gi = types.ModuleType('gi')
gi.require_version = lambda *a: None
repo = types.ModuleType('gi.repository')
repo.GLib = repo.Gtk = repo.WebKit2 = None
sys.modules.setdefault('gi', gi)
sys.modules.setdefault('gi.repository', repo)

spec = importlib.util.spec_from_file_location('kiosk', pathlib.Path(__file__).with_name('thinksmart-kiosk.py'))
kiosk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kiosk)

CLIENT = 'http://127.0.0.1:8090/v2'


def test_welcome_page_may_do_everything():
    cmds = kiosk.page_commands('file://' + kiosk.WELCOME + '?ip=1', CLIENT)
    assert {'scan', 'connect', 'forget', 'wifi_status', 'update_install', 'set_language'} <= set(cmds)


def test_the_local_client_may_do_wifi_and_the_language():
    cmds = kiosk.page_commands('http://127.0.0.1:8090/v2?x#y', CLIENT)
    assert set(cmds) == {'scan', 'connect', 'forget', 'wifi_status', 'set_language'}
    assert set(kiosk.page_commands('http://localhost:8090/', 'http://localhost:8090/')) == set(cmds)


def test_other_pages_get_nothing():
    for uri, url in [
        ('http://127.0.0.1:9999/', CLIENT),                    # another local service
        ('http://192.168.1.5:8090/', 'http://192.168.1.5:8090/'),   # configured, but not this device
        ('https://example.com/', CLIENT),
        ('http://127.0.0.1:8090.evil.com/', CLIENT),
        ('file:///tmp/welcome.html', CLIENT),
        ('', CLIENT),
        ('http://127.0.0.1:8090/', ''),                       # no URL configured
        ('http://[::1:8090/', 'http://[::1:8090/'),           # an address that doesn't parse
    ]:
        assert kiosk.page_commands(uri, url) == {}, uri


def test_forget_reports_whether_nmcli_deleted_it(monkeypatch):
    # the pages say 已忘记 only on ok: a failed delete must not answer ok
    monkeypatch.setattr(kiosk, 'wifi_profiles', lambda: {'Home': 'u1', 'Other': 'u2'})
    calls = []
    for code, ok in ((0, True), (10, False)):
        monkeypatch.setattr(kiosk, 'nmcli', lambda *a, code=code, **k: (calls.append(a), types.SimpleNamespace(returncode=code))[1])
        assert kiosk.wifi_forget({'ssid': 'Home'}, None) == {'ok': ok}
    assert calls == [('connection', 'delete', 'uuid', 'u1')] * 2


def test_a_command_that_raises_still_answers():
    # the page waits for an answer: without one the Wi-Fi panel stays busy until a restart
    def hangs(msg, progress):
        raise kiosk.subprocess.TimeoutExpired(['nmcli'], 10)

    def breaks(msg, progress):
        raise RuntimeError('NetworkManager went away')
    assert kiosk.run_command(hangs, {'cmd': 'connect'}, None) == {'ok': False, 'reason': 'timeout'}
    r = kiosk.run_command(breaks, {'cmd': 'forget'}, None)
    assert r['ok'] is False and r['reason'] == 'failed'
    assert kiosk.run_command(lambda m, p: {'ok': True}, {'cmd': 'scan'}, None) == {'ok': True}


def test_set_language_keeps_only_the_three_locales(tmp_path, monkeypatch):
    lang = tmp_path / 'cfg' / 'lang'
    monkeypatch.setattr(kiosk, 'LANG_FILE', str(lang))
    assert kiosk.read_lang() == ''
    for bad in ('fr', '', None, 'en\n', ['en'], 'zh-hant'):
        assert kiosk.set_language({'lang': bad}, None) == {'ok': False, 'reason': 'invalid'}, bad
    assert kiosk.read_lang() == '' and not lang.exists()
    assert kiosk.set_language({'lang': 'en'}, None) == {'ok': True}
    assert lang.read_text() == 'en\n' and kiosk.read_lang() == 'en'
    lang.write_text('klingon\n')     # a file someone edited by hand counts as no choice
    assert kiosk.read_lang() == ''
    lang.write_bytes(b'\xff\xfeen')  # nor do bytes that aren't text: no crash at start-up
    assert kiosk.read_lang() == ''


def test_a_language_that_cannot_be_written_is_reported(tmp_path, monkeypatch):
    # spec §6.2: a failed write goes back to the page, never silently dropped
    blocker = tmp_path / 'cfg'
    blocker.write_text('a file where the directory should be')
    monkeypatch.setattr(kiosk, 'LANG_FILE', str(blocker / 'lang'))
    r = kiosk.run_command(kiosk.set_language, {'cmd': 'set_language', 'lang': 'en'}, None)
    assert r['ok'] is False and r['reason'] == 'failed'


def test_overlapping_choices_all_answer_and_leave_one_whole_language(tmp_path, monkeypatch):
    monkeypatch.setattr(kiosk, 'LANG_FILE', str(tmp_path / 'lang'))
    langs = ['en', 'zh-Hant', 'zh-Hans'] * 20
    replies = [None] * len(langs)

    def choose(i):
        replies[i] = kiosk.run_command(kiosk.set_language, {'cmd': 'set_language', 'lang': langs[i]}, None)
    threads = [threading.Thread(target=choose, args=(i,)) for i in range(len(langs))]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    assert replies == [{'ok': True}] * len(langs)
    assert kiosk.read_lang() in kiosk.LOCALES


def test_the_welcome_page_stays_until_a_language_is_chosen(tmp_path, monkeypatch):
    monkeypatch.setattr(kiosk, 'LANG_FILE', str(tmp_path / 'lang'))
    monkeypatch.setattr(kiosk, 'needs_network_setup', lambda: False)
    up = lambda _url: True
    assert not kiosk.leave_welcome(CLIENT, check=up)
    kiosk.set_language({'lang': 'zh-Hant'}, None)
    assert kiosk.leave_welcome(CLIENT, check=up)
    assert not kiosk.leave_welcome(CLIENT, check=lambda _url: False)   # nothing answers yet
    assert not kiosk.leave_welcome('', check=up)                         # no URL configured
    monkeypatch.setattr(kiosk, 'needs_network_setup', lambda: True)
    assert not kiosk.leave_welcome(CLIENT, check=up)                     # a fresh device sets up Wi-Fi first


def test_the_voice_client_is_loaded_with_the_language():
    cases = [
        ('http://127.0.0.1:8090/', 'en', 'http://127.0.0.1:8090/?lang=en'),
        ('http://127.0.0.1:8090/v2?x=1&lang=zh-Hans#top', 'en', 'http://127.0.0.1:8090/v2?x=1&lang=en#top'),
        ('http://localhost:8090/v1', 'zh-Hant', 'http://localhost:8090/v1?lang=zh-Hant'),
        ('http://127.0.0.1:8090/', '', 'http://127.0.0.1:8090/'),              # no language yet
        ('http://127.0.0.1:9000/', 'en', 'http://127.0.0.1:9000/'),             # another local service
        ('https://example.com/?a=1', 'en', 'https://example.com/?a=1'),          # the user's own page
        ('http://192.168.1.5:8090/', 'en', 'http://192.168.1.5:8090/'),         # a client on another device
        ('http://127.0.0.1:x/', 'en', 'http://127.0.0.1:x/'),                   # a port that isn't a number
        ('http://[::1:8090/', 'en', 'http://[::1:8090/'),                       # an address that doesn't parse
    ]
    for url, lang, want in cases:
        assert kiosk.client_url(url, lang) == want, url


NODE = shutil.which('node') or 'node'


def shell_language(url, at):
    """window.thinksmartShell.language as the page at `at` sees it (the script is injected into every page)."""
    js = ('globalThis.window = globalThis; const u = new URL(process.argv[1]);'
          'globalThis.location = { protocol: u.protocol, host: u.host };'
          + kiosk.shell_script(url) + 'process.stdout.write(JSON.stringify(window.thinksmartShell.language));')
    r = subprocess.run([NODE, '-e', js, at], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_only_the_local_client_is_offered_the_language():
    assert shell_language(CLIENT, 'http://127.0.0.1:8090/v2?lang=en') is True
    assert shell_language('http://localhost:8090/v1', 'http://localhost:8090/') is True
    # the configured client is local, but the page showing now is not: it keeps its own setting
    assert shell_language(CLIENT, 'http://192.168.1.5:8090/') is False
    assert shell_language(CLIENT, 'https://example.com/') is False
    for url in ('http://192.168.1.5:8090/', 'https://example.com/', '', 'http://[::1:8090/'):
        assert shell_language(url, 'http://127.0.0.1:8090/') is False, url


def test_main_loads_the_client_with_the_language():
    # check_target and reload are closures in main(): read the source instead
    src = pathlib.Path(kiosk.__file__).read_text(encoding='utf-8')
    assert 'view.load_uri(url)' not in src
    assert src.count('view.load_uri(client_url(url, read_lang()))') == 2
    assert 'shell = shell_script(url)' in src and 'lang=read_lang()' in src
    assert src.count("st['lang'] = read_lang()") == 2     # every status says the language as it is when sent
