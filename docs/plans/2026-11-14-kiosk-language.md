# Kiosk 語言選擇 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 首次開機時，歡迎頁讓使用者選「繁體中文／简体中文／English」。kiosk 外殼把選擇存進自己的檔案，之後歡迎頁、本機的語音客戶端（載入時附上 `?lang=`）和螢幕鍵盤都用這個語言；客戶端設定頁換語言時，也經同一個通道寫進這個檔案（spec §6.2）。

**Spec:** `docs/specs/2026-11-09-oh-im-smart-v1-design.md` §6.1（字典和 `msg_key` 的規則）、§6.2（全部）、§6.4「kiosk 外殼」和「字典完整性」、§9 驗收第 1 項。

**Architecture:** `kiosk/thinksmart-kiosk.py` 新增四個模組層級的函式：`read_lang()`、`set_language(msg, progress)`、`client_url(url, lang)` 和 `leave_welcome(url, check)`。`main()` 裏的 `check_target()`、`reload()`、`page_status()` 改用它們。`set_language` 加入歡迎頁的指令集，並加入一個新的「本機客戶端」指令集（Wi‑Fi 加上 `set_language`）。注入每個頁面的 `window.thinksmartShell` 多了 `language`，客戶端看到它為真才會送 `set_language`。它只在設定的網址是本機客戶端時為真（`shell_script(url)`）：外殼不回覆別的頁面，設在另一台裝置的客戶端要用自己的語言設定。同一時間只寫一次語言檔（`LANG_LOCK`）。

歡迎頁新增一個精簡的 `kiosk/i18n.js`（`KioskI18n`：`t`、`text`、`apply`、`locale`），以及兩份字典 `kiosk/zh-Hant.js`、`kiosk/en.js`。`apply()` 第一次執行時記下頁面每段文字和屬性的原文，所以頁面可以就地換語言，不用重新載入。JavaScript 寫進頁面的每句話都經過 `t()`，更新器的結果按 `msg_key` 翻譯。`keyboard.js` 每次彈出時讀 `<html lang>`，再選按鍵文字。

**Tech Stack:** Python 3（只用標準函式庫）、pytest（`uv run --no-project --with pytest`）、node（在測試裏執行歡迎頁的 JavaScript）、Google Chrome headless（`--dump-dom`，檢查整頁翻譯）。

**Global Constraints:**
- 這是 v1 七份計劃中的第 3 份。其餘：映像打包（第 1 份，已完成）、更新器訊息鍵（第 2 份，已完成）、客戶端英文（已完成）、網關英文和網址（已完成）、bootstrap `prepare.sh`、教學和映像 Release。
- **只改主 repo。** 客戶端那一側已經做好，而且有測試：
  - `web/app.js:224-237` 和 `web/v2/app.js:814-820` 在 `window.thinksmartShell.language` 為真時，先送 `{id, cmd: 'set_language', lang}`，收到 `ok === true` 才切換；
  - `web/i18n.js` 已經是 `?lang` → 已記住的值 → 瀏覽器語言，無效的 `?lang` 直接忽略；
  - `tests/test_i18n_page.cjs:77` 測這個通道。
  
  本計劃要配合的是這個契約：指令名稱 `set_language`、參數 `lang`、回覆 `{ok: true}`，以及旗標 `thinksmartShell.language`。
- **映像不帶語言選擇：** `image/sanitize-rootfs.sh:210` 已經刪除 `home/ubuntu/.config/thinksmart-kiosk`，`image/check-rootfs.sh:324` 和 `image/tests/test-sanitize.sh:97,218` 已經檢查這件事（第 1 份計劃）。所以新刷的裝置一定會出現選語言畫面。本計劃不需要改映像腳本。
- **系統層 `VERSION` 不改：** 目前 0.2.1。跟第 2 份計劃相同，留給「教學和映像 Release」計劃一次改成 1.0.0（spec §5.2）。新的 kiosk 檔案寫進 `image/system-files.txt`（Task 4），發佈時 `make-release.py` 會要求 `VERSION` 已經改過。
- **字典格式跟客戶端相同：** 第一行是註解，第二行是 `window.UI_EN = ` 或 `window.UI_ZH_HANT = `，接着 `json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True)` 的結果（一行一個條目，按碼位排序），最後是 `;` 和換行。英文用彎引號 ’ “ ”。繁中沿用客戶端的用詞：重啟裝置、伺服器、網路、連線、儲存、裡、螢幕、介面。Wi‑Fi 沿用歡迎頁原文的寫法（中間是 U+2011 不斷行連字號）。
- **鍵是頁面上的简中原文**，跟 §6.1 相同。句中帶數值的地方改成整句範本，用 `t("…{name}…", {name})`。程式碼裏的 `t()` 一律寫成 `t("…")`（雙引號字面值），方便測試擷取。
- 主 repo 的改動在分支 `feat/kiosk-language` 上。merge 到 `main` 只用 merge commit（`git merge --no-ff`），不 rebase、不 force-push。
- 測試指令不接 `| tail`：管線的結束碼是 `tail` 的，會蓋掉失敗。主 repo 的測試一律以 `GIT_CONFIG_GLOBAL=/dev/null` 執行（這台機器的全域 `tag.gpgsign=true` 會讓 `test_make_release_carries_the_system_layer` 失敗，跟本計劃無關）。

---

## 背景：基準

- 主 repo `main` = `d53e63e`。`GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk`：66 passed。
- 客戶端 `main` = `1282847`（本計劃不動它）。
- 更新器的 53 個鍵（`update/msg_keys.json`）在客戶端的 `web/en.js` 和 `web/zh-Hant.js` 裏都已經有譯文（用 node 核對過：0 個缺漏，譯文裏沒有 OpenCC 的「透過」錯誤）。
- `/usr/bin/google-chrome` 在 UM 上可以用。

## 決定

1. **「預設的客戶端網址」按來源判斷：** `http`、主機是 `127.0.0.1`／`localhost`／`::1`、埠 8090，路徑不限（`/`、`/v2`、`/v1` 都是同一個客戶端）。符合的網址把 `lang` 合併進查詢字串：已有的 `lang` 先移除，其他參數和 `#片段` 保留。其餘網址是用戶自訂的，原樣不動。另一種做法是只比對 conf 的預設字串 `http://127.0.0.1:8090/`，缺點是使用者改成 `/v1` 就失效。
2. **兩份字典，不是三份：** spec 寫「三份字典沿用」。客戶端的做法是简中就是原文（`zh-Hans` 沒有字典檔），所以 kiosk 也只有 `zh-Hant.js` 和 `en.js`，`zh-Hans` 直接顯示原文。
3. **歡迎頁就地換語言：** spec 規定歡迎頁「不自行重新載入」。客戶端的 `init()` 把文字節點直接換成譯文，只能翻譯一次。所以 `KioskI18n.apply()` 第一次執行時記下 `[節點, 屬性, 原文]`，之後每次都從原文翻譯。JavaScript 寫的文字在換語言後由頁面重畫（`setLanguage()` 呼叫 `tick`、`renderStatus`、`renderUpdate`）。
4. **選語言畫面之後還能打開：** 頁腳加一個顯示目前語言名稱的小按鈕，點了重新打開三語畫面。這樣在客戶端還沒裝好時點錯語言，也不會困在看不懂的頁面裏。語言名稱（繁體中文、简体中文、English）放在 `data-no-i18n` 的區塊裏，永遠不翻譯。三語畫面開着時，頁面跟 Wi‑Fi 面板一樣送 `busy`，外殼不會在使用者選擇時切走（`holdPage()`：兩者任一開着就是 busy，關掉一個不會放開另一個）。重新打開後儲存失敗，頁面保留原本的語言，錯誤訊息也用原本的語言顯示。
5. **鍵盤沒有 `lang` 時用简中：** 規則是 `zh-Hant`／`zh-TW`／`zh-HK`／`zh-MO` 對應繁中，其他 `zh` 或沒有 `lang` 對應简中，其他語言對應英文。沒有 `lang` 用简中，保留目前的行為，因為用戶自訂的頁面常常不寫 `lang`。英文那一邊的判斷跟客戶端的 `normalize()` 相同（`en-HK` 是英文）。
6. **歡迎頁的「自检没通过，正在退回」寫成「自檢沒通過」：** 客戶端那一條是 OpenCC 的誤譯「沒透過」，不在本計劃修（見「不在這份計劃裏」）。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `kiosk/thinksmart-kiosk.py` | 修改 | `read_lang`、`set_language`、`client_url`、`leave_welcome`、`CLIENT_COMMANDS`；`main()` 用它們；`thinksmartShell.language` |
| `kiosk/test_kiosk_commands.py` | 修改 | 指令集；`set_language` 的驗證和寫入失敗；未選語言時留在歡迎頁；`?lang` |
| `kiosk/keyboard.js` | 修改 | 三語的按鍵文字，每次彈出時按 `<html lang>` 選 |
| `kiosk/test_keyboard_words.py` | 新增 | node 執行 `keyboard.js`，檢查各種 `lang` 對應的文字 |
| `kiosk/i18n.js` | 新增 | `KioskI18n`：`t`、`text`、`apply`、`locale` |
| `kiosk/zh-Hant.js`、`kiosk/en.js` | 新增 | 歡迎頁的字典（頁面文字和 `update/msg_keys.json` 的全部鍵） |
| `kiosk/welcome.html` | 修改 | 三語選擇、頁腳語言按鈕、所有文字經 `t()`、`Intl.DateTimeFormat`、更新結果按 `msg_key` |
| `kiosk/welcome_js.py` | 新增 | 測試用：在 node 裏載入 `i18n.js` 和字典，再執行歡迎頁的幾行程式 |
| `kiosk/test_welcome_i18n.py` | 新增 | 字典完整性、腳本裏沒有 `t()` 以外的中文、喚醒詞規則、`t`／`text`、Chrome 整頁檢查 |
| `kiosk/test_welcome_update.py` | 修改 | 改用 `welcome_js.run`；加英文的更新結果 |
| `image/system-files.txt` | 修改 | 三個新檔案 |
| `README.md` | 修改 | 介面語言的說明 |

---

### Task 1: kiosk 外殼：`set_language`、語言檔、`?lang`

**Files:**
- Modify: `kiosk/thinksmart-kiosk.py`
- Test: `kiosk/test_kiosk_commands.py`

**Interfaces:**
- Produces:
  - `LANG_FILE: str`（`~/.config/thinksmart-kiosk/lang`）、`LOCALES = ('zh-Hant', 'zh-Hans', 'en')`；
  - `read_lang() -> str`（無效或沒有時為 `''`）；
  - `set_language(msg, progress) -> dict`：`{'ok': True}` 或 `{'ok': False, 'reason': 'invalid'}`，寫入失敗時拋出例外，由 `run_command` 回覆 `{'ok': False, 'reason': 'failed', …}`；
  - `client_url(url, lang) -> str`；
  - `leave_welcome(url, check=reachable) -> bool`；
  - `CLIENT_COMMANDS`；
  - `shell_script(url) -> str`：注入的 `window.thinksmartShell`，`language` 只在設定的網址是本機客戶端時為 `true`；
  - `page_status()` 多了 `lang`。

- [ ] **Step 1: 分支**

```bash
cd /home/chris/Projects/ohimsmart && git switch -c feat/kiosk-language
```

- [ ] **Step 2: 模組層級的函式**

在 `kiosk/thinksmart-kiosk.py` 的 `KEYBOARD = …` 下一行加上：

```python
LANG_FILE = os.path.expanduser('~/.config/thinksmart-kiosk/lang')   # the kiosk runs as ubuntu (spec §6.2)
LANG_LOCK = threading.Lock()   # every command runs in its own thread: a second tap may overlap the first save
LOCALES = ('zh-Hant', 'zh-Hans', 'en')
CLIENT_PORT = 8090
```

在 `update_request` 之後、`run_command` 之前加上：

```python
def read_lang():
    """The language chosen on this device; '' while there is none (or the file holds something else)."""
    try:
        with open(LANG_FILE, encoding='utf-8') as f:
            lang = f.read().strip()
    except (OSError, ValueError):   # ValueError: bytes that aren't text (UnicodeDecodeError)
        return ''
    return lang if lang in LOCALES else ''


def set_language(msg, _progress):
    """The welcome page's or the voice client's language choice, kept for every page (spec §6.2).
    A write that fails raises: run_command answers {ok: false, reason: failed} and the page says so."""
    lang = msg.get('lang')
    if lang not in LOCALES:
        return {'ok': False, 'reason': 'invalid'}
    with LANG_LOCK:
        os.makedirs(os.path.dirname(LANG_FILE), exist_ok=True)
        tmp = LANG_FILE + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(lang + '\n')
        os.replace(tmp, LANG_FILE)
    return {'ok': True}
```

把 `WIFI_COMMANDS`／`WELCOME_COMMANDS` 兩行換成：

```python
WIFI_COMMANDS = {'wifi_status': wifi_status, 'scan': wifi_scan, 'connect': wifi_connect, 'forget': wifi_forget}
CLIENT_COMMANDS = dict(WIFI_COMMANDS, set_language=set_language)
WELCOME_COMMANDS = dict(CLIENT_COMMANDS, update_status=update_status, update_install=update_request,
                        update_check=update_request)
```

`page_commands()` 的 docstring 和回傳值改成：

```python
def page_commands(uri, url):
    """What the page now on screen may ask for: the welcome page everything, the configured page
    only Wi-Fi and the language, and only when this device serves it (the voice client's settings),
    others nothing. A page on the network can't take over the device's Wi-Fi, nor can one the user
    navigates to."""
    if uri.startswith('file://' + WELCOME):
        return WELCOME_COMMANDS
    page, conf = urllib.parse.urlparse(uri), urllib.parse.urlparse(url or '')
    if (page.scheme in ('http', 'https') and (page.scheme, page.netloc) == (conf.scheme, conf.netloc)
            and page.hostname in LOOPBACK):
        return CLIENT_COMMANDS
    return {}


def shell_script(url):
    """window.thinksmartShell, injected into every page: what the shell offers. The language only when
    the configured page is this device's own: the shell answers no other page, and a voice client on
    another device would wait 90 s for a reply that never comes instead of using its own setting."""
    language = 'true' if 'set_language' in page_commands(url, url) else 'false'
    return 'window.thinksmartShell = {version: 3, keyboard: true, wifi: true, language: %s};' % language
```

在 `reachable()` 之後加上（`leave_welcome` 的預設參數用到 `reachable`，所以要放在它後面）：

```python
def client_url(url, lang):
    """The URL to load: the voice client on this device (http, 127.0.0.1/localhost, port 8090, any
    path) gets ?lang=<lang>, replacing one already there; any other URL is the user's own and stays."""
    try:
        u = urllib.parse.urlsplit(url)
        ours = u.scheme == 'http' and u.hostname in LOOPBACK and u.port == CLIENT_PORT
    except ValueError:   # a port that isn't a number
        return url
    if not lang or not ours:
        return url
    query = [(k, v) for k, v in urllib.parse.parse_qsl(u.query, keep_blank_values=True) if k != 'lang']
    return urllib.parse.urlunsplit(u._replace(query=urllib.parse.urlencode(query + [('lang', lang)])))


def leave_welcome(url, check=reachable):
    """The welcome page gives way once a language is chosen, something answers at url (check) and
    the device has been on a network (spec §6.2)."""
    return bool(url) and bool(read_lang()) and check(url) and not needs_network_setup()
```

- [ ] **Step 3: `main()` 用它們**

注入的旗標（後面那行 `shell.replace('keyboard: true', 'keyboard: false')` 不變）：

```python
    shell = shell_script(url)
```

`page_status()`：

```python
    def page_status():
        st = device_status()
        st.update(target=url, tries=state['tries'], help=conf.get('HELP_URL', ''), lang=read_lang())
        return st
```

`check_target()` 裏的 `work()` 和 `done()`：

```python
            def work():
                ok = leave_welcome(url)
                st = None if ok else page_status()

                def done():
                    state['checking'] = False
                    if not state['welcome']:
                        return False
                    if ok and not state['busy']:
                        state['welcome'] = False
                        view.load_uri(client_url(url, read_lang()))
                    elif not ok:
                        state['tries'] += 1
                        st['tries'] = state['tries']
                        run_js('thinksmartStatus', st)
                    return False
                GLib.idle_add(done)
```

`reload()`（不檢查能否連上：載入失敗時 `on_load_failed` 會顯示歡迎頁）：

```python
    def reload():
        if leave_welcome(url, check=lambda _url: True):
            view.load_uri(client_url(url, read_lang()))
        else:
            show_welcome()
        return False
```

模組 docstring 的最後一段之後加一段：

```
The welcome page asks for the screen's language first (繁體中文 / 简体中文 / English) and stays until
one is chosen; the choice is kept in ~/.config/thinksmart-kiosk/lang, set through the same handler
(set_language, also from the voice client's settings), and the voice client on this device is loaded
with ?lang=<it> (spec §6.2).
```

`on_message` 不用改：`set_language` 不是 `update_` 開頭，回覆之後歡迎頁會收到一次 `thinksmartStatus(page_status())`，裏面已經有新的 `lang`。

- [ ] **Step 4: 測試**

`kiosk/test_kiosk_commands.py`：docstring 第一行改成 `"""Which page may ask thinksmart-kiosk.py for what, and the language it keeps (no WebKit needed: gi is stubbed).`。`test_welcome_page_may_do_everything` 的集合加上 `'set_language'`。`test_the_local_client_may_only_do_wifi` 換成：

```python
def test_the_local_client_may_do_wifi_and_the_language():
    cmds = kiosk.page_commands('http://127.0.0.1:8090/v2?x#y', CLIENT)
    assert set(cmds) == {'scan', 'connect', 'forget', 'wifi_status', 'set_language'}
    assert set(kiosk.page_commands('http://localhost:8090/', 'http://localhost:8090/')) == set(cmds)
```

檔尾加上：

```python
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


def test_only_the_local_client_is_offered_the_language():
    assert 'language: true' in kiosk.shell_script(CLIENT)
    assert 'language: true' in kiosk.shell_script('http://localhost:8090/v1')
    for url in ('http://192.168.1.5:8090/', 'https://example.com/', ''):
        assert 'language: false' in kiosk.shell_script(url), url


def test_a_language_that_cannot_be_written_is_reported(tmp_path, monkeypatch):
    # spec §6.2: a failed write goes back to the page, never silently dropped
    blocker = tmp_path / 'cfg'
    blocker.write_text('a file where the directory should be')
    monkeypatch.setattr(kiosk, 'LANG_FILE', str(blocker / 'lang'))
    r = kiosk.run_command(kiosk.set_language, {'cmd': 'set_language', 'lang': 'en'}, None)
    assert r['ok'] is False and r['reason'] == 'failed'


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
    ]
    for url, lang, want in cases:
        assert kiosk.client_url(url, lang) == want, url


def test_main_loads_the_client_with_the_language():
    # check_target and reload are closures in main(): read the source instead
    src = pathlib.Path(kiosk.__file__).read_text(encoding='utf-8')
    assert 'view.load_uri(url)' not in src
    assert src.count('view.load_uri(client_url(url, read_lang()))') == 2
    assert 'shell = shell_script(url)' in src and 'lang=read_lang()' in src
```

檔頭的 `import` 加上 `import threading`。

- [ ] **Step 5: 跑測試**

```bash
cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk
```

預期：73 passed（66 + 7 個新測試；改名的那一個仍算一個）。`python3 -m py_compile kiosk/thinksmart-kiosk.py` 沒有輸出。

- [ ] **Step 6: Commit（先跑 litmus）**

```bash
git add kiosk/thinksmart-kiosk.py kiosk/test_kiosk_commands.py
git commit -m "feat(kiosk): set_language keeps the screen's language; the welcome page waits for it, the client gets ?lang"
```

---

### Task 2: 螢幕鍵盤按頁面的語言

**Files:**
- Modify: `kiosk/keyboard.js`
- Create: `kiosk/test_keyboard_words.py`

**Interfaces:**
- Consumes: `<html lang>`（歡迎頁由 `KioskI18n.apply` 設定，客戶端由它的 `UII18n.init` 設定）。
- Produces: `ThinkSmartKeyboard.words() -> {space, keys: {go, done, next, send, search, enter}}`（按當時的 `<html lang>`）。

- [ ] **Step 1: 按鍵文字表**

`LABEL` 拿掉 `'{space}'`，下面加上 `WORDS` 和 `words()`：

```js
  const LABEL = { '{shift}': '⇧', '{bksp}': '⌫', '{123}': '123', '{sym}': '#+=', '{abc}': 'ABC' };
  // Key words in the page's language, read from <html lang> each time the keyboard comes up (spec §6.2):
  // zh-Hant/TW/HK/MO Traditional; other zh, or no lang at all (a user's own page), Simplified; else English
  const WORDS = {
    'zh-Hans': { space: '空格', keys: { go: '前往', done: '完成', next: '下一项', send: '发送', search: '搜索', enter: '换行' } },
    'zh-Hant': { space: '空格', keys: { go: '前往', done: '完成', next: '下一項', send: '傳送', search: '搜尋', enter: '換行' } },
    en: { space: 'space', keys: { go: 'Go', done: 'Done', next: 'Next', send: 'Send', search: 'Search', enter: 'Return' } },
  };
  function words() {
    const lang = document.documentElement.lang || '';
    if (lang && !/^zh(?:-|$)/i.test(lang)) return WORDS.en;
    return /^zh-(?:Hant|TW|HK|MO)(?:-|$)/i.test(lang) ? WORDS['zh-Hant'] : WORDS['zh-Hans'];
  }
```

`render()` 裏按鍵文字那一行改成：

```js
          b.textContent = k === '{enter}' ? (opts.enterLabel || words().keys.done)
            : k === '{space}' ? words().space
            : LABEL[k] || (shift && k.length === 1 ? k.toUpperCase() : k);
```

刪掉 `const ENTER_LABELS = …` 那一行，`enterLabel()` 改成：

```js
  function enterLabel(el) {
    const keys = words().keys;
    return (el.dataset && el.dataset.kbEnter) || keys[el.getAttribute('enterkeyhint')] ||
      (el.tagName === 'TEXTAREA' ? keys.enter : keys.done);
  }
```

`show()` 裏的重設條件改成（換了語言，同一個欄位也要重畫）：

```js
    const label = enterLabel(el), w = words();
    if (field !== el || kb.label !== label || kb.words !== w) { kb.words = w; kb.reset(); kb.setEnterLabel(label); }
```

最後一行改成 `window.ThinkSmartKeyboard = { create, hide, auto: true, words };`。開頭註解裏 `label of the enter key (default 完成)` 改成 `label of the enter key (default: Done, in the page's <html lang>)`，`enterLabel: '连接',` 這個範例不變。

- [ ] **Step 2: 測試**

`kiosk/test_keyboard_words.py`：

```python
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
```

- [ ] **Step 3: 跑測試**

```bash
cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk && node --check kiosk/keyboard.js
```

預期：75 passed，`node --check` 沒有輸出。

- [ ] **Step 4: Commit（先跑 litmus）**

```bash
git add kiosk/keyboard.js kiosk/test_keyboard_words.py
git commit -m "feat(kiosk): the on-screen keyboard labels its keys in the page's language"
```

---

### Task 3: 歡迎頁的翻譯和三語選擇

**Files:**
- Create: `kiosk/i18n.js`、`kiosk/zh-Hant.js`、`kiosk/en.js`、`kiosk/welcome_js.py`、`kiosk/test_welcome_i18n.py`
- Modify: `kiosk/welcome.html`、`kiosk/test_welcome_update.py`

**Interfaces:**
- Consumes: `page_status().lang`（Task 1；在網址的查詢字串裏，之後在每次的 `thinksmartStatus`）、`set_language`（Task 1）、`ThinkSmartKeyboard`（Task 2，讀 `<html lang>`）、`update/msg_keys.json`。
- Produces: `window.KioskI18n = {t(source, params?), text(value), apply(lang) -> locale, locale}`；`window.UI_ZH_HANT`、`window.UI_EN`；`welcome_js.run(expr, lang='zh-Hans', lines=()) -> object`、`welcome_js.page_lines(*names) -> [str]`。

- [ ] **Step 1: `kiosk/i18n.js`**

```js
/*
 * Translations for the kiosk's welcome page (spec §6.2). The page's text is its Simplified Chinese
 * source; zh-Hant.js and en.js translate it. The kiosk says which language (page_status lang: in the
 * address and in every thinksmartStatus); this page never stores one and never reloads itself.
 * The page's own text is remembered on the first apply(), so the page can switch again in place.
 */
window.KioskI18n = (() => {
  const LOCALES = ['zh-Hans', 'zh-Hant', 'en'];
  const ATTRS = ['title', 'aria-label', 'placeholder', 'data-kb-enter'];
  const has = (obj, k) => Object.prototype.hasOwnProperty.call(obj, k);
  let locale = 'zh-Hans', catalog = {}, sources = null;
  // Plain string parameters (names, versions, third-party text) are shown as given; an object
  // parameter is another {msg_key, msg_params} and is translated first.
  const param = v => (v && typeof v === 'object' ? text(v) : v === null || v === undefined ? '' : String(v));
  // t(key) translates; t(key, params) also fills {name} placeholders after translating the template.
  const t = (source, params) => {
    const s = has(catalog, source) ? catalog[source] : source;
    return params ? s.replace(/\{(\w+)\}/g, (whole, name) => (has(params, name) ? param(params[name]) : whole)) : s;
  };
  // A backend value: a string (translated if it is ours) or a {msg_key, msg_params} object.
  const text = v => (v && typeof v === 'object' && typeof v.msg_key === 'string' ? t(v.msg_key, v.msg_params || {})
    : v === null || v === undefined ? '' : t(String(v)));
  function collect() {
    sources = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode: n => (n.parentElement.closest('script,style,[data-no-i18n]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    for (let n = walker.nextNode(); n; n = walker.nextNode()) if (n.textContent.trim()) sources.push([n, null, n.textContent]);
    for (const el of document.querySelectorAll(ATTRS.map(a => `[${a}]`).join(','))) {
      if (el.closest('[data-no-i18n]')) continue;
      for (const a of ATTRS) if (el.hasAttribute(a)) sources.push([el, a, el.getAttribute(a)]);
    }
  }
  // Switch to value ('zh-Hans' for anything unknown) and translate the page's own text from its source.
  function apply(value) {
    locale = LOCALES.includes(value) ? value : 'zh-Hans';
    catalog = (locale === 'zh-Hant' ? window.UI_ZH_HANT : locale === 'en' ? window.UI_EN : null) || {};
    document.documentElement.lang = locale;
    if (!sources) collect();
    for (const [node, attr, src] of sources) {
      const s = src.trim();
      if (attr) node.setAttribute(attr, t(s));
      else node.textContent = src.replace(s, () => t(s));   // a function: no $& patterns
    }
    return locale;
  }
  return { t, text, apply, get locale() { return locale; } };
})();
```

JavaScript 換掉的文字節點（例如 `#statusText` 的初始文字）在記錄裏會變成已經脫離頁面的節點，`apply()` 改它沒有作用，也不會出錯。這些地方由頁面重畫。

- [ ] **Step 2: `kiosk/welcome.html` 的標記和樣式**

1. `<html lang="zh-CN">` 改成 `<html lang="zh-Hans">`。
2. 開頭註解加一句：`The screen's language comes from the kiosk too (lang, spec §6.2): without one the page asks for it first; text is translated by i18n.js with zh-Hant.js / en.js.`
3. `<style>` 結尾（`.net .meta.saved` 那一行之後）加上：

```css
  /* ---- language: asked on the first start, reopened from the footer ---- */
  .langs { position: fixed; inset: 0; z-index: 20; display: none; place-items: center; text-align: center;
           background: radial-gradient(900px 600px at 50% 0%, #17224a 0%, transparent 60%), linear-gradient(160deg, #0d1430, #070b16); }
  .langs.on { display: grid; animation: fade .18s ease-out; }
  .langs h3 { margin: 0 0 36px; font-size: 26px; font-weight: 600; color: var(--ink2); }
  .langs-row { display: flex; gap: 20px; justify-content: center; }
  .langs-row button { height: 96px; min-width: 260px; padding: 0 28px; border-radius: 22px; border: 1px solid var(--line);
                      background: var(--card); font-size: 30px; font-weight: 600; }
  .langs-row button:active { transform: scale(.97); }
  .langs-row button[disabled] { opacity: .4; }
  .langs .msg { justify-content: center; margin-top: 24px; }
```

4. `<code id="ssh">…</code>` 改成 `<code id="ssh"></code>`（`renderStatus()` 在第一次顯示前填好）。
5. 頁腳在 `<span class="grow">` 之前加上 `<span><button class="chip" id="chipLang" data-no-i18n></button></span>`。
6. `</div>`（Wi‑Fi `sheet` 結束）之後加上：

```html
<!-- language: asked until one is chosen (the kiosk waits for it, spec §6.2); the names are never translated -->
<div class="langs" id="langs" data-no-i18n>
  <div>
    <h3>選擇語言 · 选择语言 · Choose a language</h3>
    <div class="langs-row">
      <button data-lang="zh-Hant">繁體中文</button>
      <button data-lang="zh-Hans">简体中文</button>
      <button data-lang="en">English</button>
    </div>
    <div class="msg bad" id="langMsg"></div>
  </div>
</div>
```

7. 腳本載入順序：

```html
<script src="qrcode.js"></script>
<script src="zh-Hant.js"></script>
<script src="en.js"></script>
<script src="i18n.js"></script>
<!-- the kiosk injects the system keyboard into every page; this copy is for previewing in a desktop browser -->
<script src="keyboard.js"></script>
```

- [ ] **Step 3: `kiosk/welcome.html` 的腳本**

整段 `<script>…</script>` 換成下面這段。沒有提到的部分（`drawQr`、`call`、`thinksmartReply`、`mock`、`showPane`／`showList`、`bars`、`LOCK`、`focusField`、`typing`、`canConnect`、`setMsg`、更新的按鈕和事件、輸入框的事件）一字不改。

```js
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const t = KioskI18n.t;
// the language the kiosk put in the address, before anything below writes to the page (spec §6.2)
KioskI18n.apply(new URLSearchParams(location.search).get('lang'));

const dateFormats = {};
function tick() {
  const now = new Date(), locale = KioskI18n.locale;
  $('time').textContent = String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0');
  dateFormats[locale] = dateFormats[locale] || new Intl.DateTimeFormat(locale, { month: 'long', day: 'numeric', weekday: 'long' });
  $('date').textContent = dateFormats[locale].format(now);
}

let shownHelp = null;
function drawQr(url) {
  /* unchanged */
}

/* ---- language (spec §6.2): the kiosk keeps the choice in its own file and passes it in the status ---- */
let lastStatus = {}, chosen = false;
// Called by thinksmart-kiosk.py (and once from the query string): what the device knows, and its language
window.thinksmartStatus = function (st) {
  lastStatus = st;
  // no language yet: the kiosk stays here until one is chosen. A status taken just before a choice
  // was saved can arrive after it: once chosen, an empty lang doesn't open the picker again.
  if (!st.lang && !chosen && !$('langs').classList.contains('on')) openLanguages();
  if (st.lang && st.lang !== KioskI18n.locale) setLanguage(st.lang);
  else renderStatus();
};
function setLanguage(lang) {
  KioskI18n.apply(lang);
  tick();
  renderStatus();
  renderUpdate();
}
// keep the kiosk from switching pages while the Wi-Fi sheet or the language picker is open
function holdPage() {
  call('busy', { value: $('sheet').classList.contains('open') || $('langs').classList.contains('on') });
}
function openLanguages() {
  $('langMsg').textContent = '';
  $('langs').classList.add('on');
  holdPage();
}
async function chooseLanguage(lang) {
  const buttons = document.querySelectorAll('[data-lang]');
  buttons.forEach(b => { b.disabled = true; });   // one save at a time
  $('langMsg').textContent = '';
  const r = await call('set_language', { lang });
  buttons.forEach(b => { b.disabled = false; });
  // on the first start a failure is told in the language just tapped; once a language is saved the
  // page keeps it (the next status would switch back anyway)
  if (r.ok || !lastStatus.lang) setLanguage(lang);
  if (r.ok) {
    chosen = true;
    $('langs').classList.remove('on');
    holdPage();
  } else $('langMsg').textContent = t("没能保存语言设置，请再试一次");
}
function renderStatus() {
  const st = lastStatus;
  const ip = (st.ip || '').split(',').filter(Boolean);
  const online = ip.length > 0;
  $('ip').textContent = online ? ip.join('  ') : t("未联网");
  $('host').textContent = st.host || '—';
  $('ssid').textContent = st.ssid || (online ? t("有线 / USB") : t("未连接"));
  $('ssh').innerHTML = `ssh ubuntu@${esc(ip[0] || '<' + t("设备 IP") + '>')}<br>sudo kiosk-mode url http://${esc(t("你的地址"))}`;
  $('chipLang').textContent = document.querySelector(`[data-lang="${KioskI18n.locale}"]`).textContent;
  const box = $('status');
  box.classList.toggle('offline', !online);
  if (!online) {
    $('statusText').textContent = t("设备还没有联网");
    $('statusSub').textContent = t("点右边的按钮连接 Wi‑Fi");
  } else if (st.target) {
    $('statusText').textContent = t("展示页面暂时打不开，正在等待它启动");
    $('statusSub').textContent = st.target + (st.tries ? '  ·  ' + t("已重试 {tries} 次", { tries: st.tries }) : '');
  } else {
    $('statusText').textContent = t("还没有设置展示页面");
    $('statusSub').textContent = t("按右侧的方法装上小智客户端，或设置你自己的地址");
  }
  drawQr(st.help || 'https://github.com/ohimsmart/oh-im-smart-gateway');
}

/* ---- talking to thinksmart-kiosk.py ---- */
// bridge, seq, pending, CALL_TIMEOUT, call(), window.thinksmartReply, mock(): unchanged
// (mock answers set_language with its default { ok: true })

/* ---- Wi-Fi sheet ---- */
const REASON = r => ({
  password: t("密码不对，请再试一次"),
  notfound: t("找不到这个网络，可能离得太远或名称有误"),
  timeout: t("连接超时，请靠近路由器后再试"),
  noreply: t("设备没有回应，请过一会儿再看看网络状态"),
})[r];
let nets = [], target = null, fields = { ssid: '', pw: '' }, showPw = false, busy = false;

function openSheet() {
  $('sheet').classList.add('open');
  holdPage();  // keep the kiosk from switching pages under the user's fingers
  showList();
  scan();
}
function closeSheet() {
  if (document.activeElement) document.activeElement.blur();
  $('sheet').classList.remove('open');
  holdPage();  // the language picker may still hold the page
}
// showPane, showList: unchanged

async function scan() {
  $('btnScan').classList.add('spin');
  if (!nets.length) $('nets').innerHTML = `<div class="empty">${t("正在搜索附近的 Wi‑Fi…")}</div>`;
  const r = await call('scan');
  $('btnScan').classList.remove('spin');
  nets = r.ok ? r.networks : [];
  renderNets(r.ok ? '' : t("搜索失败，点右上角刷新再试"));
}

// bars, LOCK: unchanged

function renderNets(error) {
  const box = $('nets');
  box.textContent = '';
  if (error || !nets.length) {
    box.innerHTML = `<div class="empty">${error || t("附近没有搜到 Wi‑Fi")}</div>`;
    return;
  }
  for (const n of nets) {
    const b = document.createElement('button');
    b.className = 'net' + (n.active ? ' cur' : '');
    b.innerHTML = `${bars(n.signal)}<span class="name">${esc(n.ssid)}</span>` +
      (n.active ? `<span class="meta">${t("已连接")}</span>` : n.saved ? `<span class="meta saved">${t("已保存")}</span>` : '') +
      (n.secure ? LOCK : '');
    b.addEventListener('click', () => join(n, false));
    box.appendChild(b);
  }
}

// mode: 'type' (enter a password), 'saved' (a saved network: connect or forget), 'info' (the
// connected network: forget). Saved networks wait for a tap on 连接 so 忘记 stays reachable.
function join(net, hidden) {
  target = { ssid: net ? net.ssid : '', secure: net ? net.secure : true, hidden, saved: !!(net && net.saved),
             mode: net && net.active ? 'info' : net && net.saved ? 'saved' : 'type' };
  fields = { ssid: target.ssid, pw: '' };
  showPw = false;
  $('joinTitle').textContent = hidden ? t("添加隐藏网络") : target.ssid;
  const quality = !net ? '' : net.signal > 75 ? t("信号很好") : net.signal > 50 ? t("信号良好")
    : net.signal > 25 ? t("信号一般") : t("信号较弱");
  $('joinHint').textContent = hidden ? t("输入网络名称和密码（没有密码就留空），然后点「连接」")
    : target.mode === 'info' ? t("已连接 · {quality}", { quality })
    : target.mode === 'saved' ? t("已保存的网络 · {quality}，点「连接」用保存的密码连接", { quality })
    : target.secure ? t("加密网络 · {quality}，输入密码后点「连接」", { quality }) : t("开放网络 · {quality}", { quality });
  setMsg('');
  showPane('paneJoin');
  renderFields();
  if (target.mode === 'type' && !target.secure && !hidden) connect();  // open network: nothing to type
  else focusField();
}

// focusField, typing, canConnect: unchanged

function renderFields() {
  if ($('inSsid').value !== fields.ssid) $('inSsid').value = fields.ssid;
  if ($('inPw').value !== fields.pw) $('inPw').value = fields.pw;
  $('inPw').type = showPw ? 'text' : 'password';
  $('inPw').placeholder = target.hidden ? t("没有密码就留空") : t("至少 8 位");
  $('inSsid').disabled = $('inPw').disabled = busy;
  $('btnEye').textContent = showPw ? t("隐藏") : t("显示");
  // fields and keyboard only while typing; forgetting only for a network that has a saved profile
  $('fieldSsid').style.display = typing() && target.hidden ? '' : 'none';
  $('fieldPw').style.display = typing() && target.secure ? '' : 'none';
  $('btnForget').style.display = target.saved || target.mode === 'info' ? '' : 'none';
  $('btnJoin').style.display = target.mode === 'saved' ? '' : 'none';
  $('btnJoin').disabled = $('btnForget').disabled = busy;
}

// setMsg: unchanged

async function connect() {
  if (target.mode !== 'saved' && !canConnect()) return;
  busy = true;
  renderFields();
  const usingSaved = target.mode === 'saved';
  setMsg(usingSaved ? t("正在用已保存的密码连接 {ssid}…", { ssid: fields.ssid }) : t("正在连接 {ssid}…", { ssid: fields.ssid }), 'wait');
  connectId = seq + 1;  // the id call() is about to use: progress reports carry it
  const r = await call('connect', { ssid: fields.ssid, password: usingSaved || !target.secure ? '' : fields.pw,
                                     hidden: !!target.hidden });
  connectId = null;
  busy = false;
  if (r.ok) {
    // Back to the list (now showing it connected) rather than out of Wi-Fi settings: the
    // user may still want to forget a network; × leaves
    target.mode = 'info';
    target.saved = true;
    setMsg(t("已连接 {ssid}", { ssid: fields.ssid }), 'ok');
    renderFields();
    setTimeout(() => { if (!busy && $('paneJoin').classList.contains('on')) { showList(); scan(); } }, 1500);
    return;
  }
  // Whatever went wrong, let the user type a password next
  if (target.secure) target.mode = 'type';
  if (r.reason === 'password') fields.pw = '';
  setMsg(usingSaved && r.reason === 'password' ? t("保存的密码已失效，请重新输入")
    : REASON(r.reason) || (r.detail ? t("连接失败：{detail}", { detail: r.detail }) : t("连接失败")), 'bad');
  renderFields();
  focusField();
}

// Stages reported by thinksmart-kiosk.py while it joins (from wpa_supplicant's state)
const STAGE = s => ({
  scan: t("正在搜索网络…"),
  join: t("正在连接路由器…"),
  auth: t("正在验证密码…"),
  ip: t("密码正确，正在获取网络地址…"),
})[s];
let connectId = null;
window.thinksmartProgress = function (p) {
  if (busy && p.id === connectId && STAGE(p.stage)) setMsg(STAGE(p.stage), 'wait');
};

async function forget() {
  if (busy) return;
  busy = true;
  const ssid = target.ssid;
  setMsg(t("正在忘记 {ssid}…", { ssid }), 'wait');
  renderFields();
  const r = await call('forget', { ssid });
  busy = false;
  if (!r.ok) {
    setMsg(t("没能忘记 {ssid}，请再试一次", { ssid }), 'bad');
    return renderFields();
  }
  target.saved = false;
  setMsg(t("已忘记 {ssid}，下次连接需要重新输入密码", { ssid }), 'ok');
  renderFields();
  nets = nets.map(n => n.ssid === ssid ? Object.assign({}, n, { saved: false }) : n);
  setTimeout(() => { if (!busy) { showList(); scan(); } }, 1400);
}

/* ---- updates (client and system layer): the root updater installs, this page only shows and asks (via thinksmart-kiosk.py) ---- */
const UPD_STAGE = () => ({ preparing: t("正在准备"), downloading: t("正在下载"), installing: t("正在安装"),
                           testing: t("正在重启并自检"), rolling_back: t("自检没通过，正在退回") });
// job.reboot from the updater; an older updater only says it in its Chinese message
const needsReboot = job => (typeof job.reboot === 'boolean' ? job.reboot : /重启设备后生效/.test(job.message || ''));
// the updater's result in this page's language; an older updater's job has only its Chinese message
const updMsg = job => KioskI18n.text(job.msg_key ? job : job.message || '');
// a failed or rolled-back result; the system layer before it may still need a restart (spec §6.1)
const updFail = job => updMsg(job) + (job.state !== 'done' && needsReboot(job) ? t("。") + t("系统层的部分改动重启设备后生效") : '');
let upd = null, updArmed = 0;
let updStarting = 0;   // request sent, the updater hasn't reported yet (it takes a few seconds to start)
function updParts(u) {
  // what one tap installs, in the updater's order: the system layer first
  const parts = [], sa = (u.system || {}).available;
  if (sa && !(sa.missing || []).length) parts.push({ key: 'system', name: t("系统层"), ...sa });
  if (u.available) parts.push({ key: 'client', name: t("客户端"), ...u.available });
  return parts;
}
function renderUpdate() {
  const u = upd || {}, job = u.job || {}, sys = u.system || {}, parts = updParts(u);
  const busy = job.state in UPD_STAGE();
  // between the confirming tap and the updater's first report: don't show 更新 again (looks like
  // the tap missed); ends when the updater reports or after 30 s of silence
  if (updStarting && (busy || (job.time || 0) * 1000 > updStarting - 2000 || Date.now() - updStarting > 30000)) updStarting = 0;
  const starting = !!updStarting;
  const recent = !!job.time && Date.now() / 1000 - job.time < 3600;
  const result = !busy && recent && job.message;
  $('upd').classList.toggle('on', !!(parts.length || busy || result || starting));
  let title, text, bad = false;
  if (starting) {
    title = t("正在开始更新…");
    text = t("正在连接更新服务器，请稍等");
  } else if (busy) {
    title = job.component === 'system' ? t("正在更新系统层 {version}", { version: job.version })
      : t("正在更新客户端 {version}", { version: job.version });
    const pct = job.state === 'downloading' && job.progress != null ? ` ${Math.round(job.progress * 100)}%` : '';
    text = t("{stage}{pct}，请不要断电", { stage: UPD_STAGE()[job.state], pct });
  } else if (parts.length) {
    title = t("有新版本 {list}", { list: parts.map(p => `${p.name} ${p.version}`).join(' · ') });
    bad = !!result && job.state !== 'done';
    text = bad ? updFail(job) : !u.current ? t("小智客户端")
      : sys.current ? t("当前：客户端 {client} · 系统层 {system}", { client: u.current, system: sys.current })
      : t("当前：客户端 {client}", { client: u.current });
    if (Date.now() - updArmed < 5000) {
      // waiting for the confirming tap: keep the hint (the status poll re-renders every 3 s)
      bad = false;
      text = parts.some(p => p.key === 'system')
        ? t("更新时屏幕会闪一下、客户端会重启（约 {minutes} 分钟），再点一下「确认更新」开始", { minutes: parts.length > 1 ? 2 : 1 })
        : t("更新时客户端会重启（约 {minutes} 分钟），再点一下「确认更新」开始", { minutes: 1 });
    }
  } else {
    title = job.state === 'done' ? t("更新完成") : t("更新没有完成");
    // the state the update left, both versions: one tap installs the system layer then the client,
    // and an older updater keeps only the last one's message
    text = job.state === 'done' && u.current && sys.current
      ? t("现在是 系统层 {system} · 客户端 {client}", { system: sys.current, client: u.current })
        + (needsReboot(job) ? t("，部分改动重启设备后生效") : '')
      : updFail(job);
    bad = job.state !== 'done';
  }
  $('updTitle').textContent = title || '';
  $('updSub').textContent = text || '';
  $('updSub').classList.toggle('bad', !!bad);
  $('updNotes').innerHTML = parts.length && !busy && !starting
    ? parts.map(p => (parts.length > 1 ? `<li class="h">${esc(p.name)} ${esc(p.version)}</li>` : '')
                     + (p.notes || []).map(n => `<li>${esc(n)}</li>`).join('')).join('') : '';
  $('updBtn').hidden = !parts.length || busy || starting;
  $('updBtn').textContent = Date.now() - updArmed < 5000 ? t("确认更新") : t("更新");
}
// pollUpdate: unchanged
// the updBtn click handler: unchanged except its failure line:
//   if (!r.ok) { updStarting = 0; renderUpdate(); $('updSub').textContent = t("没能开始更新"); $('updSub').classList.add('bad'); }

for (const b of document.querySelectorAll('[data-lang]')) b.addEventListener('click', () => chooseLanguage(b.dataset.lang));
$('chipLang').addEventListener('click', openLanguages);
// the remaining listeners and the start-up lines (tick, setInterval, thinksmartStatus from the query
// string, #wifi, pollUpdate): unchanged
```

（上面的 `/* unchanged */` 和 `// …: unchanged` 是給這份計劃讀的標記：實作時那些部分照原檔保留，不寫成註解。）

中文輸出跟改動前逐字相同：每個範本都是原本拼接出來的整句（`正在更新系统层 {version}` ＝ 原本的 `正在更新${'系统层'} ${version}`，`{stage}{pct}，请不要断电` ＝ 原本的 `${UPD_STAGE[state]}${pct}，请不要断电`，以此類推）。唯一的差別是 `已重试 {tries} 次` 前面的 `  ·  ` 不再算在鍵裏，畫面上照舊。

- [ ] **Step 4: 字典**

鍵 = 下表的「原文」欄 ＋ `update/msg_keys.json` 的 53 個鍵。53 個更新器的鍵，譯文從客戶端的 `web/zh-Hant.js`、`web/en.js` 逐字複製。下表裏標「客戶端」的列，譯文也跟客戶端相同（已核對過）。

用一個臨時腳本產生兩個檔案（放在 scratchpad，不 commit）。腳本讀這份計劃裏 `<!-- dict:start -->` 和 `<!-- dict:end -->` 之間的表格，再從客戶端字典補上更新器的鍵：

```python
# scratch: python3 gen_kiosk_dicts.py
import json, re, subprocess
from pathlib import Path
REPO, CLIENT = Path('/home/chris/Projects/ohimsmart'), Path('/home/chris/src/oh-im-smart-client/web')
plan = (REPO / 'docs/plans/2026-11-14-kiosk-language.md').read_text(encoding='utf-8')
# the markers on lines of their own: the text above quotes them too
table = re.search(r'^<!-- dict:start -->\n(.*?)^<!-- dict:end -->$', plan, re.S | re.M)[1]
rows = [[c.strip() for c in line.strip().strip('|').split('|')] for line in table.splitlines()
        if line.startswith('|') and not line.startswith('|---') and not line.startswith('| 原文')]
assert len(rows) == 98 and len({r[0] for r in rows}) == 98, len(rows)
src = lambda c: c.strip('`')
hant = {src(r[0]): src(r[1]) for r in rows}
en = {src(r[0]): src(r[2]) for r in rows}
dump = 'const fs=require("fs"),vm=require("vm"),W={};for(const f of ["en.js","zh-Hant.js"])vm.runInNewContext(fs.readFileSync(process.argv[1]+"/"+f,"utf8"),{window:W});process.stdout.write(JSON.stringify(W))'
W = json.loads(subprocess.run(['node', '-e', dump, str(CLIENT)], capture_output=True, text=True, check=True).stdout)
for k in json.loads((REPO / 'update/msg_keys.json').read_text(encoding='utf-8')):
    hant.setdefault(k, W['UI_ZH_HANT'][k])
    en.setdefault(k, W['UI_EN'][k])
for name, var, d in (('zh-Hant.js', 'UI_ZH_HANT', hant), ('en.js', 'UI_EN', en)):
    body = json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True)
    (REPO / 'kiosk' / name).write_text('// The kiosk welcome page\'s text (spec §6.2); keys are its Simplified Chinese source.\n'
                                       f'window.{var} = {body};\n', encoding='utf-8')
```

表格裏每格用反引號包住（保留開頭和結尾的空白、`·` 和標點），腳本去掉反引號。英文譯文裏不用全形字元：`＋ 添加隐藏网络` 的英文用半形的 `+`，否則 Chrome 檢查會把它算成沒翻譯的中文。

<!-- dict:start -->
| 原文 | zh-Hant | en |
|---|---|---|
| `AI 语音终端` | `AI 語音終端` | `AI voice terminal` |
| `你好，欢迎使用` | `你好，歡迎使用` | `Hello and welcome` |
| `这台设备已经准备好接入 AI。装上小智客户端，说一声唤醒词，就能和 DeepSeek、Claude 等大模型，以及 Claude Code、云端 Agent 直接对话。` | `這台裝置已經準備好接入 AI。裝上小智客戶端，說一聲喚醒詞，就能和 DeepSeek、Claude 等大模型，以及 Claude Code、雲端 Agent 直接對話。` | `This device is ready for AI. Install the Xiaozhi client, say the wake word, and talk directly with large models such as DeepSeek and Claude, as well as Claude Code and cloud agents.` |
| `正在连接展示页面…` | `正在連線展示頁面…` | `Connecting to the display page…` |
| `连接 Wi‑Fi` | `連線 Wi‑Fi` | `Connect to Wi‑Fi` |
| `更新` | `更新` | `Update` |
| `接入小智 AI 网关` | `接入小智 AI 閘道器` | `Connect to the Xiaozhi AI gateway` |
| `推荐` | `推薦` | `Recommended` |
| `部署 xiaozhi-hub-server（装在本机或家里任意一台电脑上）` | `部署 xiaozhi-hub-server（裝在本機或家裡任意一台電腦上）` | `Deploy xiaozhi-hub-server (on this device or any computer at home)` |
| `在本机安装 ThinkSmart 小智客户端` | `在本機安裝 ThinkSmart 小智客戶端` | `Install the ThinkSmart Xiaozhi client on this device` |
| `开机直接进入语音对话界面` | `開機直接進入語音對話介面` | `It then starts straight into voice chat` |
| `扫码查看安装教程` | `掃碼查看安裝教學` | `Scan for the install guide` |
| `使用你自己的服务` | `使用你自己的服務` | `Use your own service` |
| `展示屏会全屏打开任意网页。用电脑 SSH 登录本机后，设置要打开的地址：` | `展示屏會全螢幕開啟任意網頁。用電腦 SSH 登入本機後，設定要開啟的地址：` | `The screen can show any web page full screen. Log in to this device over SSH from a computer and set the address to open:` |
| `设备地址` | `裝置地址` | `Device address` |
| `主机名` | `主機名稱` | `Host name` |
| `切换` | `切換` | `Switch` |
| `配置的页面恢复后会自动切换过去` | `設定的頁面恢復後會自動切換過去` | `The configured page opens by itself once it’s back` |
| `选择 Wi‑Fi` | `選擇 Wi‑Fi` | `Choose Wi‑Fi` |
| `刷新` | `重新整理` | `Refresh` |
| `关闭` | `關閉` | `Close` |
| `＋ 添加隐藏网络` | `＋ 新增隱藏網路` | `+ Add a hidden network` |
| `返回` | `返回` | `Back` |
| `连接` | `連線` | `Connect` |
| `网络名称` | `網路名稱` | `Network name` |
| `输入网络名称` | `輸入網路名稱` | `Enter the network name` |
| `密码` | `密碼` | `Password` |
| `显示` | `顯示` | `Show` |
| `忘记这个网络` | `忘記這個網路` | `Forget this network` |
| `未联网` | `未聯網` | `Offline` |
| `有线 / USB` | `有線 / USB` | `Wired / USB` |
| `未连接` | `未連線` | `Not connected` |
| `设备 IP` | `裝置 IP` | `device-IP` |
| `你的地址` | `你的地址` | `your-address` |
| `设备还没有联网` | `裝置還沒有聯網` | `The device isn’t online yet` |
| `点右边的按钮连接 Wi‑Fi` | `點右邊的按鈕連線 Wi‑Fi` | `Tap the button on the right to connect to Wi‑Fi` |
| `展示页面暂时打不开，正在等待它启动` | `展示頁面暫時打不開，正在等待它啟動` | `The display page can’t be opened yet; waiting for it to start` |
| `已重试 {tries} 次` | `已重試 {tries} 次` | `tried {tries} times` |
| `还没有设置展示页面` | `還沒有設定展示頁面` | `No display page is set yet` |
| `按右侧的方法装上小智客户端，或设置你自己的地址` | `按右側的方法裝上小智客戶端，或設定你自己的地址` | `Install the Xiaozhi client as shown on the right, or set your own address` |
| `密码不对，请再试一次` | `密碼不對，請再試一次` | `Wrong password; try again` |
| `找不到这个网络，可能离得太远或名称有误` | `找不到這個網路，可能離得太遠或名稱有誤` | `Network not found: it may be too far away, or the name is wrong` |
| `连接超时，请靠近路由器后再试` | `連線超時，請靠近路由器後再試` | `Connection timed out; move closer to the router and try again` |
| `设备没有回应，请过一会儿再看看网络状态` | `裝置沒有回應，請過一會兒再看看網路狀態` | `The device didn’t answer; check the network status again in a while` |
| `正在搜索附近的 Wi‑Fi…` | `正在搜尋附近的 Wi‑Fi…` | `Looking for Wi‑Fi nearby…` |
| `搜索失败，点右上角刷新再试` | `搜尋失敗，點右上角重新整理再試` | `Search failed; tap Refresh at the top right to try again` |
| `附近没有搜到 Wi‑Fi` | `附近沒有搜到 Wi‑Fi` | `No Wi‑Fi found nearby` |
| `已连接` | `已連線` | `Connected` |
| `已保存` | `已儲存` | `Saved` |
| `添加隐藏网络` | `新增隱藏網路` | `Add a hidden network` |
| `信号很好` | `訊號很好` | `Excellent signal` |
| `信号良好` | `訊號良好` | `Good signal` |
| `信号一般` | `訊號一般` | `Fair signal` |
| `信号较弱` | `訊號較弱` | `Weak signal` |
| `输入网络名称和密码（没有密码就留空），然后点「连接」` | `輸入網路名稱和密碼（沒有密碼就留空），然後點「連線」` | `Enter the network name and password (leave the password empty if there is none), then tap “Connect”` |
| `已连接 · {quality}` | `已連線 · {quality}` | `Connected · {quality}` |
| `已保存的网络 · {quality}，点「连接」用保存的密码连接` | `已儲存的網路 · {quality}，點「連線」用儲存的密碼連線` | `Saved network · {quality}. Tap “Connect” to use the saved password` |
| `加密网络 · {quality}，输入密码后点「连接」` | `加密網路 · {quality}，輸入密碼後點「連線」` | `Secured network · {quality}. Enter the password, then tap “Connect”` |
| `开放网络 · {quality}` | `開放網路 · {quality}` | `Open network · {quality}` |
| `没有密码就留空` | `沒有密碼就留空` | `Leave empty if there is no password` |
| `至少 8 位` | `至少 8 位` | `At least 8 characters` |
| `隐藏` | `隱藏` | `Hide` |
| `正在用已保存的密码连接 {ssid}…` | `正在用已儲存的密碼連線 {ssid}…` | `Connecting to {ssid} with the saved password…` |
| `正在连接 {ssid}…` | `正在連線 {ssid}…` | `Connecting to {ssid}…` |
| `已连接 {ssid}` | `已連線 {ssid}` | `Connected to {ssid}` |
| `保存的密码已失效，请重新输入` | `儲存的密碼已失效，請重新輸入` | `The saved password no longer works; enter it again` |
| `连接失败` | `連線失敗` | `Couldn’t connect` |
| `连接失败：{detail}` | `連線失敗：{detail}` | `Couldn’t connect: {detail}` |
| `正在搜索网络…` | `正在搜尋網路…` | `Looking for networks…` |
| `正在连接路由器…` | `正在連線路由器…` | `Connecting to the router…` |
| `正在验证密码…` | `正在驗證密碼…` | `Checking the password…` |
| `密码正确，正在获取网络地址…` | `密碼正確，正在獲取網路地址…` | `Password accepted, getting a network address…` |
| `正在忘记 {ssid}…` | `正在忘記 {ssid}…` | `Forgetting {ssid}…` |
| `没能忘记 {ssid}，请再试一次` | `沒能忘記 {ssid}，請再試一次` | `Couldn’t forget {ssid}; try again` |
| `已忘记 {ssid}，下次连接需要重新输入密码` | `已忘記 {ssid}，下次連線需要重新輸入密碼` | `Forgot {ssid}; you’ll need its password to connect next time` |
| `自检没通过，正在退回` | `自檢沒通過，正在退回` | `Self-test failed, going back` |
| `系统层` | `系統層` | `System layer` |
| `客户端` | `客戶端` | `Client` |
| `正在开始更新…` | `正在開始更新…` | `Starting the update…` |
| `正在连接更新服务器，请稍等` | `正在連線更新伺服器，請稍等` | `Connecting to the update server, please wait` |
| `正在更新系统层 {version}` | `正在更新系統層 {version}` | `Updating the system layer to {version}` |
| `正在更新客户端 {version}` | `正在更新客戶端 {version}` | `Updating the client to {version}` |
| `{stage}{pct}，请不要断电` | `{stage}{pct}，請不要斷電` | `{stage}{pct}. Don’t turn off the power` |
| `有新版本 {list}` | `有新版本 {list}` | `Available: {list}` |
| `小智客户端` | `小智客戶端` | `Xiaozhi client` |
| `当前：客户端 {client}` | `目前：客戶端 {client}` | `Current: client {client}` |
| `当前：客户端 {client} · 系统层 {system}` | `目前：客戶端 {client} · 系統層 {system}` | `Current: client {client} · system layer {system}` |
| `更新时屏幕会闪一下、客户端会重启（约 {minutes} 分钟），再点一下「确认更新」开始` | `更新時螢幕會閃一下、客戶端會重啟（約 {minutes} 分鐘），再點一下「確認更新」開始` | `The screen flickers and the client restarts during the update (about {minutes} min). Tap “Confirm update” to start` |
| `更新时客户端会重启（约 {minutes} 分钟），再点一下「确认更新」开始` | `更新時客戶端會重啟（約 {minutes} 分鐘），再點一下「確認更新」開始` | `The client restarts during the update (about {minutes} min). Tap “Confirm update” to start` |
| `更新完成` | `更新完成` | `Update done` |
| `更新没有完成` | `更新沒有完成` | `The update didn’t finish` |
| `现在是 系统层 {system} · 客户端 {client}` | `現在是 系統層 {system} · 客戶端 {client}` | `Now on system layer {system} · client {client}` |
| `，部分改动重启设备后生效` | `，部分改動重啟裝置後生效` | `; some changes take effect after a restart` |
| `确认更新` | `確認更新` | `Confirm update` |
| `没能开始更新` | `沒能開始更新` | `Couldn’t start the update` |
| `。` | `。` | `. ` |
| `系统层的部分改动重启设备后生效` | `系統層的部分改動重啟裝置後生效` | `Some system layer changes take effect after a restart` |
| `没能保存语言设置，请再试一次` | `沒能儲存語言設定，請再試一次` | `Couldn’t save the language; try again` |
<!-- dict:end -->

跟客戶端相同的列：`更新`、`切换`、`刷新`、`关闭`、`返回`、`连接`、`网络名称`、`输入网络名称`、`密码`、`显示`、`隐藏`、`忘记这个网络`、`未联网`、四個連線失敗的原因、`搜索失败，点右上角刷新再试`、`已连接`、`添加隐藏网络`、四個訊號強弱、`没有密码就留空`、`至少 8 位`、`保存的密码已失效，请重新输入`、`连接失败`、四個連線階段、`系统层`、`客户端`、`正在开始更新…`、`正在连接更新服务器，请稍等`、`更新完成`、`确认更新`、`没能开始更新`、`。`、`系统层的部分改动重启设备后生效`。`自检没通过，正在退回` 的繁中刻意不同（決定 6）。

有幾個鍵同時是頁面文字和更新器的鍵（`正在准备`、`正在下载`、`正在安装`、`正在重启并自检`）。它們只在更新器那一份出現一次，譯文用客戶端的。

- [ ] **Step 5: 測試的共用程式 `kiosk/welcome_js.py`**

```python
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
```

- [ ] **Step 6: `kiosk/test_welcome_update.py` 改用它**

`run_helpers` 和它的 `import`（`re`、`shutil`、`subprocess`、`NODE`、`WELCOME`）換成：

```python
import json
import re
import subprocess
from pathlib import Path

from welcome_js import NODE, page_lines, run

WELCOME = Path(__file__).with_name('welcome.html')
HELPERS = page_lines('needsReboot', 'updMsg', 'updFail')


def run_helpers(expr, lang='zh-Hans'):
    """Evaluate expr (JSON out) next to the page's needsReboot, updMsg and updFail."""
    return run(expr, lang, HELPERS)
```

`test_the_page_script_still_parses` 要用的 `re` 和 `subprocess` 保留，`NODE` 改從 `welcome_js` 匯入（`from welcome_js import NODE, page_lines, run`），`shutil` 不再需要。現有三個測試的斷言不改：它們的 job 沒有 `msg_key`，`t("。")` 在简中是「。」，所以結果跟原本一樣。檔尾加上：

```python
def test_the_english_page_translates_the_updaters_message():
    why = {'msg_key': '屏幕界面没有启动起来', 'msg_params': {}}
    jobs = [{'state': 'failed', 'message': '连不上更新服务器', 'msg_key': '连不上更新服务器', 'msg_params': {},
             'reboot': True},
            {'state': 'failed', 'message': '1.0.2 自检没通过（屏幕界面没有启动起来），已退回 1.0.1',
             'msg_key': '{version} 自检没通过（{why}），已退回 {old}',
             'msg_params': {'version': '1.0.2', 'why': why, 'old': '1.0.1'}, 'reboot': False},
            {'state': 'failed', 'message': '下载太慢'}]      # an older updater: no key, its Chinese as it is
    assert run_helpers(f'{json.dumps(jobs, ensure_ascii=False)}.map(updFail)', 'en') == [
        'Can’t reach the update server. Some system layer changes take effect after a restart',
        '1.0.2 failed its self-test (the screen interface did not start); went back to 1.0.1',
        '下载太慢']
```

`welcome_js` 能直接匯入，是因為 pytest 預設的 `prepend` 匯入模式會把測試檔所在的 `kiosk/` 放進 `sys.path`。

- [ ] **Step 7: `kiosk/test_welcome_i18n.py`**

```python
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
CHINESE = re.compile('[　-〿一-鿿＀-￯]')     # ideographs and fullwidth punctuation
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


def test_the_script_writes_chinese_only_through_t():
    assert chinese_outside_t(scripts(WELCOME.read_text(encoding='utf-8'))) == []


def test_the_guard_catches_chinese_outside_t():
    ok = 'x = t("已连接 {ssid}", { ssid }); // 注释\n/* 注释 */\nfunction mock(m) {\n  a("客厅");\n}\n'
    assert chinese_outside_t(ok) == []
    assert chinese_outside_t(ok + "$('x').textContent = '已连接';\n") == list('已连接')
    assert chinese_outside_t('y = t(`已连接`);\n') == list('已连接')     # only t("…") counts


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
```

`Markup` 跳過 `data-no-i18n` 的區塊（語言名稱），所以英文頁面上不應該剩下任何中文。

- [ ] **Step 8: 產生字典、跑測試**

```bash
cd /home/chris/Projects/ohimsmart && python3 <scratchpad>/gen_kiosk_dicts.py \
  && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk
```

預期：87 passed（75 ＋ `test_welcome_i18n.py` 的 11 個（兩個參數化的測試各 2、Chrome 3、其他 4）＋ `test_welcome_update.py` 的 1 個新測試）。

確認守門的測試會失敗：

1. 暫時在 `renderStatus()` 加一行 `$('host').textContent = '主机';`，`test_the_script_writes_chinese_only_through_t` 必須失敗。
2. 暫時刪掉 `kiosk/en.js` 的一個條目，`test_the_dictionary_holds_exactly_the_pages_text[en.js]` 必須失敗。

兩處都還原後，再跑一次全部測試。

- [ ] **Step 9: 看畫面**

```bash
cd /home/chris/Projects/ohimsmart && for l in en zh-Hant ''; do
  google-chrome --headless=new --disable-gpu --user-data-dir=$(mktemp -d) --window-size=1280,800 --virtual-time-budget=3000 \
    --screenshot=<scratchpad>/welcome-${l:-none}.png \
    "file://$PWD/kiosk/welcome.html?ip=192.168.1.9&host=ts&ssid=Home&target=http%3A%2F%2F127.0.0.1%3A8090%2F&tries=3&upd=both${l:+&lang=$l}"
done
```

用 Read 看三張截圖（1280×800，跟裝置旋轉後的畫面相同）。要確認的是：英文的頁腳和更新區塊不會擠出畫面或重疊；沒有 `lang` 時三語畫面蓋住整頁；頁腳的語言按鈕顯示目前的語言名稱。有排版問題就只改那一處的 CSS，不改文字。

- [ ] **Step 10: Commit（先跑 litmus；字典檔大，用 `LITMUS_MAX_WEIGHTED_LINES=2500 LITMUS_MAX_TOTAL_LINES=2500`）**

```bash
git add kiosk/i18n.js kiosk/zh-Hant.js kiosk/en.js kiosk/welcome.html kiosk/welcome_js.py \
        kiosk/test_welcome_i18n.py kiosk/test_welcome_update.py
git commit -m "feat(kiosk): the welcome page asks for the language first and shows everything in it, the updater's results too"
```

---

### Task 4: 系統層的檔案表、README、merge

**Files:**
- Modify: `image/system-files.txt`、`image/system-post.sh`（一行註解）、`README.md`

- [ ] **Step 1: 檔案表**

`image/system-files.txt` 在 `kiosk/qrcode.js` 那一行之後加上：

```
kiosk/i18n.js                       /usr/local/share/thinksmart-kiosk/i18n.js       644 root kiosk
kiosk/zh-Hant.js                    /usr/local/share/thinksmart-kiosk/zh-Hant.js    644 root kiosk
kiosk/en.js                         /usr/local/share/thinksmart-kiosk/en.js         644 root kiosk
```

`image/system-post.sh:25` 的註解 `# Only welcome.html, keyboard.js and qrcode.js are used here; …` 改成 `# Only welcome.html, keyboard.js, qrcode.js, i18n.js, zh-Hant.js and en.js are used here; …`（後半句不變，指令不變）。

- [ ] **Step 2: README**

`README.md` 的「屏幕键盘是系统键盘」那一條之後加上：

```markdown
- 首次开机先选界面语言（繁體中文／简体中文／English），选好之前展示屏停在欢迎页。选择存在 `/home/ubuntu/.config/thinksmart-kiosk/lang`：欢迎页、语音客户端（外壳打开本机 8090 端口的客户端时加上 `?lang=`）和屏幕键盘都跟着它。客户端设置页换语言也写进这个文件；欢迎页底部的语言按钮可以重新选。
```

下一條「语音客户端的设置页也能切换 WiFi：外壳只接受两种页面的 WiFi 请求」改成「语音客户端的设置页也能切换 WiFi 和界面语言：外壳只接受两种页面的这些请求」，其餘不變。

- [ ] **Step 3: 檢查**

```bash
cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk \
  && bash image/tests/test-sanitize.sh
```

預期：87 passed。`test-sanitize.sh` 全部 ok：它用 `image/tests/make-fake-root.sh` 按檔案表造一個假的 rootfs，所以三個新檔案也會走一遍。如果這個腳本要 root 或 Docker 才能跑，就記下來跳過，在實作記錄裏寫明。

- [ ] **Step 4: Commit（先跑 litmus）、merge、push**

```bash
git add image/system-files.txt image/system-post.sh README.md
git commit -m "feat(image): the welcome page's translations are part of the system layer; README on the screen language"
git switch main && git merge --no-ff feat/kiosk-language -m "Merge branch 'feat/kiosk-language': the screen asks for its language first (plan 3 of 7)"
GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk
git push origin main
```

---

### Task 5: 實作記錄

實作完成後，在下面的「實作記錄」寫下：commit、測試數目、跟計劃不同的地方（含理由），以及 Step 9 截圖看到的問題和處理方式。

## 實作記錄

- **Commit：** `d5e377b`（鍵盤）、`567daff`（外殼、歡迎頁、字典、檔案表）、`91a1293`（README），merge `c81e1c8`，已 push。測試 91 passed（66 → 91）；`fakeroot sh image/tests/test-sanitize.sh` 232 個全部 ok。
- **Task 1、3、4 的檔案表合成一個 commit：** litmus 指出只有 Task 1 時，外殼要等語言，舊歡迎頁卻沒有選擇畫面；只有 Task 3 時，歡迎頁要用的三個新檔案不在 `image/system-files.txt`。兩個中間狀態都會讓裝置停在歡迎頁，所以一起 commit。`image/system-post.sh` 的註解也在這個 commit 裏。
- **第 2 輪設計審查的兩個 medium，在實作時修好：**
  - `page_commands()` 遇到解析不了的網址（`http://[::1:8090/`）回傳 `{}`，啟動時不會崩潰；`client_url` 也接住同樣的 `ValueError`。
  - 重新打開的三語畫面在已經有語言時多了關閉按鈕（`#langClose`，第一次選擇時隱藏）。
- **第 2 輪的 low，也一併處理：**
  - `language` 旗標在注入的腳本裏按當下頁面的 `location` 判斷，不再只看設定的網址。測試用 node 執行注入的腳本。
  - 每次送出狀態時才讀語言檔（`st['lang'] = read_lang()`），所以在儲存之前取得的狀態不會把舊語言帶回來；頁面上原本計劃的 `chosen` 旗標因此不需要了。
  - `show_welcome()` 重設 `busy`；`reload()` 載入客戶端時把 `welcome` 設為否。
  - 只有歡迎頁的指令才計算 `page_status()`，客戶端的 `set_language` 不用等 `ip` 和 `nmcli`。
  - `已重试 0 次` 不再顯示（`Number(st.tries) > 0`）。
  - 字典多兩個測試：佔位符一致、英文沒有中文；另加「頁面載入的每個腳本都在檔案表裏」。
  - 測試的正規表示式改用 `\u` 跳脫。
  - `.field .label` 改成不換行、最少 92px。
- **截圖發現的問題：** Noto Sans CJK SC 把 ’ 畫成全形（`can’ t`），所以英文頁面先用 Noto Sans（映像有 `fonts-noto-core`）。`有新版本 {list}` 的英文改成 `Available: {list}`，比較短。兩個更新加上更新說明一起出現時，左欄還是會稍微壓到頁腳；中文更新說明長的時候也一樣，是原本就有的版面限制，沒有改。
- **`update/test_system_layer.py`：** 發佈測試原本只把未暫存和未追蹤的檔案複製進它的 clone，已暫存的新檔案沒有被複製，檔案表就指向不存在的檔案。現在也複製 `git diff --cached` 的檔案。
- **沒有做的：** litmus 兩次建議加 property-based 測試，沒有採用：要加新的相依套件，而範例已經涵蓋邊界情況。
- **另外發現（客戶端的事，不在本計劃）：** 客戶端 `web/v2/app.css` 也以 Noto Sans CJK SC 為首選字型，英文介面的 ’ 應該同樣顯示成全形。

## 不在這份計劃裏

- **在裝置上驗證**（§9 驗收第 1 項：選 English 之後歡迎頁、客戶端、鍵盤都是英文，重新開機後仍然是英文）：要等「教學和映像 Release」計劃把新的系統層裝上母機。本計劃只用單元測試和 Chrome 檢查。
- **Release 說明（`notes`）不翻譯：** 它是發佈時寫的內容，照原文顯示，跟客戶端相同。
- **歡迎頁的文案和品牌**（「小智客户端」、`xiaozhi-hub-server`、ThinkSmart View）照原意翻譯，不改寫；要改留給教學計劃。
- **繁中字型：** 頁面仍以 Noto Sans CJK SC 為首選。繁體字顯示正常，只是少數字形是简中的寫法。
- **客戶端 `web/zh-Hant.js` 的「自檢沒透過」**（OpenCC 誤譯）：客戶端的事，另外處理。
- **在 `#wifi` 開啟的 Wi‑Fi 清單上選語言：** 歡迎頁只有首次開機時才會同時出現兩者。換語言後，靜態文字立即換掉，清單在下次掃描時重畫。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
