# 客戶端：#4、英文介面和我們的網址 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ohimsmart/oh-im-smart-client` 的 `main` 帶有上游 PR #4 的改動、指向 ohimsmart 的連結和出處、完整的英文介面，版本為 1.0.0。

**Architecture:** 先把 #4 以 merge commit 併入 `main`，並修好 #4 弄壞的測試輔助函式。英文沿用 #4 的「原文作鍵、每種語言一份字典」：`web/i18n.js` 多認 `en`，語言次序改為 `?lang` → 已記住的值 → 瀏覽器語言；`t(key, params)` 先翻譯範本再填值，`text()` 顯示後端的 `{msg_key, msg_params}`。頁面裏影響英文詞序的拼接改為範本，日期在英文下用 `Intl`，句子之間的中文標點也經字典。字典完整性、「頁面腳本不在 `t()` 以外寫中文」和英文顯示都由測試強制。

**Tech Stack:** Python 3.12（aiohttp、pytest、pytest-asyncio）、瀏覽器 JavaScript（無建置步驟）、Node 22（只用於測試：`node --test`、`vm`）、bash。

**Global Constraints:**
- 對應 spec：`docs/specs/2026-11-09-oh-im-smart-v1-design.md` §4、§5.2、§5.3 第 4 點（客戶端 README）、§6.1、§6.2（客戶端部分）、§6.3、§6.4、§9。
- 工作目錄是 `~/src/oh-im-smart-client`（`origin` = `https://github.com/ohimsmart/oh-im-smart-client.git`，`upstream` = justhalfbit，`fork` = chris-yyau）。這份計劃本身放在主 repo。
- `main` 只用 merge：不 rebase、不 force-push（GitHub 分支保護已設定，包括 admin）。功能分支 merge 回 `main` 一律 `git merge --no-ff`。
- 不加新的執行期依賴。Node 只是開發和測試用。
- 回傳給頁面的 `message`、`error`、`notes`、`repeat` 欄位**保留**（`repeat`、`notes` 也是大模型和語音用的），新欄位 `msg_key`、`msg_params`、`notes_msg`、`rule` 是額外的。
- 用戶的值和名稱不翻譯：對話內容、模型名稱（`m.label`）、廠商名稱（`m.company`）、WiFi 名稱、藍牙裝置名稱、鬧鐘標籤。所以 `t()` 和 `msg_params` 裏的**普通字串一律原樣顯示**；要翻譯的參數以 `{msg_key: …}` 物件傳入。
- 「中文」在所有測試裏是同一個字元集：CJK 表意文字 U+4E00–U+9FFF、CJK 標點 U+3000–U+303F、全形字元 U+FF00–U+FFEF，定義在 `tests/i18n_keys.py` 的 `CHINESE`。
- 字典鍵就是介面上的原文。#4 的少數介面以繁中寫成（`web.py` 的自訂版本錯誤、更新卡的自訂版本提示、「繁體中文」），所以 `zh-Hant.js` 有兩份字典：`UI_ZH_HANT`（简中原文 → 繁中）和 `UI_ZH_HANS`（繁中原文 → 简中）。
- 測試指令（在 repo 根目錄）：`.venv/bin/python -m pytest -q -p no:cacheprovider` 和 `node --test tests/*.cjs`。`.venv` 由 Task 1 用 `uv` 建立（UM 沒有 `python3-venv`）。
- 每個 task 結束時兩組測試都是 0 失敗，除非該 task 明確寫出預期的失敗。

---

## 背景：基準

上游 `main`（`e7ec0de`，0.1.6）：pytest **164 passed**。

#4（`fork/feat/traditional-chinese-ui`，5 個 commit，以上游 `main` 為基礎，沒有分岔）：pytest **6 failed, 165 passed**，node `tests/test_i18n.cjs` 5/5。6 項失敗（`tests/test_models.py` 5 項、`tests/test_state_combos.py` 1 項）都是 `AttributeError: 'Client' object has no attribute 'wake_prompt'`：#4 在 `_apply_models()` 呼叫 `self.wake_prompt.update(...)`，但 `tests/test_barge_in.py` 的 `make_client()` 用 `Client.__new__` 建立物件、沒有設 `wake_prompt`。這是測試輔助函式漏了新屬性，不是程式錯誤（真正的 `__init__` 有設）。Task 1 修好後基準是 **171 passed** 和 node 5/5。

## 跨計劃的約定

這份計劃只改客戶端 repo。下面兩項由其他計劃實作，客戶端這邊必須照約定運作，並且在對方還沒做好時正常退回：

1. **kiosk 外殼的 `set_language`**（主 repo 的 kiosk 計劃，spec §6.2）：
   - 外殼注入的 `window.thinksmartShell` 加上 `language: true`；
   - 頁面送 `{"id": n, "cmd": "set_language", "lang": "zh-Hant" | "zh-Hans" | "en"}`；
   - 外殼回 `{"id": n, "ok": true}`，或 `{"id": n, "ok": false, "reason": "invalid" | "failed", "detail"?: "…"}`；
   - 外殼的 `page_commands()` 要讓本機客戶端頁面使用這個指令（目前只有 WiFi 指令）。
   - 客戶端：外殼有 `language` 時先經 `set_language` 寫入語言檔，成功才以新的 `?lang` 重新載入；失敗就提示「没能切换界面语言」並留在原語言。外殼沒有 `language`（舊映像）或不在 kiosk 裏（電腦瀏覽器）時，只寫這個瀏覽器的 localStorage。
2. **更新器的訊息鍵**（主 repo 的更新器計劃，spec §6.1）：
   - 更新器的 `status.json` 裏，job 除了原有的 `message`，加上 `msg_key`、`msg_params`（巢狀參數也是 `{msg_key, msg_params}`）和布林值 `reboot`；`check_error` 旁邊加 `check_error_msg: {msg_key, msg_params}`。
   - 客戶端：有 `msg_key` 就用 `UII18n.text()` 顯示，沒有就照舊顯示 `message`；有 `reboot` 就用它，沒有才照舊用正規表示式比對 `message` 裏的「重启设备后生效」。
   - 更新器的鍵由更新器計劃決定。客戶端在本計劃留一份空的 `tests/updater_keys.json`（`[]`），完整性測試把它算入原文；更新器計劃負責填這份清單，並在客戶端的三份字典加上對應條目。spec §6.1 要求的「連不上更新伺服器」「系統層自檢失敗後的回復訊息」顯示英文，由更新器計劃連同這些條目一起測試。

閘道的錯誤已經帶鍵（閘道計劃 Task 4，`ohimsmart/oh-im-smart-gateway` 的 `main` = `2d067d94`）。客戶端會把 `/kiosk/llm/use`（切換模型）和 `/kiosk/chat/clear`（清除聊天記錄）的回應原樣轉給頁面，所以這兩個端點可能回的鍵列在 `tests/gateway_kiosk_keys.json`（Task 4），由閘道 `core/admin/admin_handler.py` 的 `handle_kiosk_llm_use` 和 `handle_kiosk_chat_clear` 整理而來。巢狀的廠商名稱（`{vendor}`）是名稱，不翻譯。

## File Structure

| 檔案 | 責任 |
|---|---|
| `NOTICE` | 新檔：出處（spec §4） |
| `README.md` | 連結指向 ohimsmart、出處一行、介面語言一節改寫 |
| `web/i18n.js` | 語言判斷、`t(key, params)`、`text()`、`choose()`、外殼掛鉤 |
| `web/zh-Hant.js` | 繁中字典：補齊原文、移除不再使用的條目 |
| `web/en.js` | 新檔：英文字典 |
| `web/index.html`、`web/v2/index.html` | 語言選單加 English；載入 `en.js` |
| `web/app.js`、`web/v2/app.js` | 範本、日期、標點、後端的鍵、更新器的鍵和 `reboot`、外殼的 `set_language` |
| `thinksmart_client/alarms.py` | `view()` 加 `rule`；`take_due()` 可另外給出帶鍵的錯過提示 |
| `thinksmart_client/app.py` | 響鈴畫面的 `notes_msg` |
| `thinksmart_client/__init__.py` | `__version__ = '1.0.0'` |
| `tests/test_barge_in.py` | `make_client()` 設 `wake_prompt`（#4 的遺漏） |
| `tests/i18n_keys.py` | 新檔：原文的收集（HTML、`t()`、Python、其他 repo 的鍵）和讀取字典 |
| `tests/test_i18n_keys.py` | 新檔：字典完整性、值的規則、頁面腳本的中文守門 |
| `tests/test_i18n.cjs` | 語言判斷和 runtime 的測試（#4 的兩項預期按 spec §6.2 改寫） |
| `tests/test_i18n_page.cjs` | 新檔：頁面的日期、重複規則、更新訊息、錯誤訊息在英文和简中下的結果 |
| `tests/gateway_kiosk_keys.json`、`tests/updater_keys.json` | 新檔：其他 repo 送到頁面的鍵 |
| `tests/test_alarms.py` | 帶鍵的錯過提示、`rule`、響鈴畫面的 `notes_msg` |

---

### Task 1: 把 #4 併入 `main`，修好測試輔助函式

**Files:**
- Modify: `tests/test_barge_in.py`（`make_client()`）

**Interfaces:**
- Produces: `main` 含 #4；`.venv`；基準 171 passed、node 5/5。

#4 是在上游目前的 `main` 之上，不會有衝突。若 `git fetch` 後上游已前進而產生衝突，停下回報，不要自行解決。

- [ ] **合併**

```bash
cd ~/src/oh-im-smart-client
git fetch --all --quiet
git switch main && git merge --ff-only origin/main
git merge-base --is-ancestor origin/main fork/feat/traditional-chinese-ui && echo base-ok
git merge --no-ff fork/feat/traditional-chinese-ui -m "Merge #4: Traditional Chinese UI and gateway-selected wake voice"
```

Expected：`base-ok`，合併沒有衝突。

- [ ] **測試環境**

```bash
uv venv -q -p 3.12 .venv
uv pip install -q -p .venv/bin/python -r requirements.lock pytest pytest-asyncio
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -3
```

Expected：`6 failed, 165 passed`，6 項都是 `wake_prompt` 的 `AttributeError`（見「背景」）。`.venv/` 已在 `.gitignore`。

- [ ] **修 `make_client()`**

在 `tests/test_barge_in.py` 的 `make_client()` 裏，`c.sounds = {}` 之後加一行：

```python
    c.wake_prompt = types.SimpleNamespace(update=lambda profile: None)   # #4: models carry the hub's TTS profile
```

- [ ] **測試**

```bash
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
node --test tests/*.cjs 2>&1 | grep -E '^# (pass|fail)'
```

Expected：`171 passed`；`# pass 5`、`# fail 0`。

- [ ] **litmus、commit、push**

```bash
git add tests/test_barge_in.py
# litmus（busdriver:litmus）PASS 後：
git commit -m "test: make_client sets wake_prompt, which #4's _apply_models now uses"
git push origin main
```

---

### Task 2: NOTICE 和 README 的連結

**Files:**
- Create: `NOTICE`
- Modify: `README.md` 第 3、5 行

**Interfaces:**
- Produces: 分支 `feat/en-and-urls`（Task 2–6 都在這個分支上）。

- [ ] **建立分支**

```bash
git switch -c feat/en-and-urls main
```

- [ ] **`NOTICE`**（LICENSE 已確認是 MIT，著作權人「半格 / HalfBit」，spec §3）

```text
Oh I'm Smart client (https://github.com/ohimsmart/oh-im-smart-client)

This repository starts from the history of xiaozhi-thinksmart-client by 半格 / HalfBit
(https://github.com/justhalfbit/xiaozhi-thinksmart-client), released under the MIT License;
the copyright notice is kept in LICENSE.

Changes in this repository are released under the same MIT License.
```

- [ ] **`README.md`**

第 3 行：`[xiaozhi-hub-server](https://github.com/justhalfbit/xiaozhi-hub-server)` 改為 `[oh-im-smart-gateway](https://github.com/ohimsmart/oh-im-smart-gateway)`。

第 5 行：`[thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image)` 改為 `[oh-im-smart](https://github.com/ohimsmart/oh-im-smart)`。

第 5 行之後加一個空行和這一段（出處；上游網址只留在這一行和 NOTICE）：

```markdown
本仓库是 Oh I'm Smart 的语音客户端，源自半格 / HalfBit 的 [xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client)（MIT），出处见 [NOTICE](NOTICE)。
```

- [ ] **確認上游網址只剩出處**

```bash
git grep -n -E '(github(usercontent)?\.com[/:]|githubusercontent\.com/)justhalfbit' -- .
```

Expected：只有 `NOTICE` 第 4 行和 `README.md` 的出處那一行。

- [ ] **litmus、commit**

```bash
git add NOTICE README.md
git commit -m "Point README links at ohimsmart; add NOTICE"
```

---

### Task 3: `i18n.js` 認得英文和新的語言次序

**Files:**
- Modify: `web/i18n.js`（整個檔案換成下面的內容）
- Modify: `tests/test_i18n.cjs`（整個檔案換成下面的內容）

**Interfaces:**
- Consumes: `window.UI_ZH_HANT`、`window.UI_ZH_HANS`（`zh-Hant.js`）、`window.UI_EN`（Task 5 才有；沒有時退回简中）。
- Produces: `UII18n.t(key, params?)`、`UII18n.msg(obj)`、`UII18n.text(value)`、`UII18n.choose(locale) → Promise<boolean>`、`UII18n.setBeforeSwitch(fn)`、`UII18n.locale`、`UII18n.applied`、`UII18n.normalize`。

這個 task 還沒有 `en.js`，頁面也不載入它：英文瀏覽器跟現在一樣看到简中（`applied` 的退回），語言選單也還沒有 English。所以這個 commit 不會出現半套英文。

**#4 測試的改動**（spec §6.2，只有這兩項預期改變）：「已記住的值優先」改為 `?lang` 優先；「無效的 `lang` 回到简中」改為忽略無效的 `?lang`、按瀏覽器語言決定（`en-US` → `en`）。#4 的選單測試（選擇後寫入 localStorage 並 `reload()`）**不改**：網址沒有 `?lang` 時，`choose()` 照舊寫入並重新載入。

- [ ] **`web/i18n.js`**

```javascript
/* Translate application-owned copy only. Conversation text, SSIDs and user input are never converted. */
window.UII18n = (() => {
  const key = 'thinksmart.uiLocale';
  const LOCALES = ['zh-Hans', 'zh-Hant', 'en'];
  const has = (obj, k) => Object.prototype.hasOwnProperty.call(obj, k);
  // zh-* with Hant/TW/HK/MO → Traditional; other zh → Simplified; everything else (including en-HK) → English
  const normalize = value => !/^zh(?:-|$)/i.test(value || '') ? 'en'
    : /^zh-(?:Hant|TW|HK|MO)(?:-|$)/i.test(value) ? 'zh-Hant' : 'zh-Hans';
  let saved;
  try { saved = localStorage.getItem(key); } catch (_) { /* Private browsing may disable storage. */ }
  const requested = new URLSearchParams(location.search).get('lang');
  // The kiosk adds ?lang from its language file on every load, so it beats the remembered value;
  // an unknown ?lang is ignored (spec §6.2).
  const locale = LOCALES.includes(requested) ? requested
    : LOCALES.includes(saved) ? saved : normalize(navigator.language);
  if (!LOCALES.includes(saved) && requested === locale) {
    try { localStorage.setItem(key, locale); } catch (_) { /* The URL still supplies this visit's locale. */ }
  }
  const catalogs = { 'zh-Hant': window.UI_ZH_HANT, 'zh-Hans': window.UI_ZH_HANS, en: window.UI_EN };
  // Never switch to a locale whose dictionary is missing or empty (e.g. en.js failed to load or parse)
  const available = l => l.startsWith('zh-') || Object.keys(catalogs[l] || {}).length > 0;
  const applied = available(locale) ? locale : 'zh-Hans';
  const catalog = catalogs[applied] || {};
  // Plain string parameters are names, numbers or third-party text and are shown exactly as given;
  // an object parameter is another {msg_key, msg_params} and is translated first.
  const param = value => (value && typeof value === 'object' ? text(value) : value === null || value === undefined ? '' : String(value));
  // t(key) translates; t(key, params) also fills {name} placeholders after translating the template.
  const t = (source, params) => {
    const s = has(catalog, source) ? catalog[source] : source;
    return params ? s.replace(/\{(\w+)\}/g, (whole, name) => (has(params, name) ? param(params[name]) : whole)) : s;
  };
  const msg = obj => (obj && typeof obj === 'object' && typeof obj.msg_key === 'string' ? t(obj.msg_key, obj.msg_params || {}) : null);
  // A backend value: a string (translated if it is ours) or a {msg_key, msg_params} object.
  const text = value => {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return t(value);
    const m = msg(value);
    return m === null ? String(value) : m;
  };
  // The voice client's page sets this: the kiosk shell writes its language file first (spec §6.2)
  let beforeSwitch = null;
  const go = value => {
    let stored = true;
    try { localStorage.setItem(key, value); } catch (_) { stored = false; }
    const params = new URLSearchParams(location.search);
    if (stored && !params.has('lang')) { location.reload(); return true; }   // the saved value decides
    params.set('lang', value);   // an old ?lang in the address would win over the choice
    location.search = '?' + params.toString();
    return true;
  };
  // Resolves true once the page is switching; false when the value is unknown or the shell refused.
  function choose(value) {
    if (!LOCALES.includes(value) || !available(value)) return Promise.resolve(false);
    if (!beforeSwitch) return Promise.resolve(go(value));
    return Promise.resolve(beforeSwitch(value)).then(ok => ok === true && go(value));
  }
  function init() {
    document.documentElement.lang = applied;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        return node.parentElement.closest('script,style,textarea,[data-no-i18n]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
      },
    });
    let node;
    while ((node = walker.nextNode())) {
      const txt = node.textContent.trim();
      if (txt) node.textContent = node.textContent.replace(txt, t(txt));
    }
    document.title = t(document.title);
    document.querySelectorAll('[title],[aria-label],[placeholder],[data-kb-enter]').forEach(el => {
      for (const attr of ['title', 'aria-label', 'placeholder', 'data-kb-enter']) {
        if (el.hasAttribute(attr)) el.setAttribute(attr, t(el.getAttribute(attr)));
      }
    });
    document.querySelectorAll('[data-language-picker]').forEach(select => {
      for (const option of select.options || []) option.disabled = !available(option.value);
      select.value = applied;
      select.addEventListener('change', () => {
        choose(select.value).then(ok => { if (!ok) select.value = applied; });
      });
    });
  }
  return { t, msg, text, init, choose, setBeforeSwitch: fn => { beforeSwitch = fn; }, locale, applied, normalize };
})();
```

- [ ] **`tests/test_i18n.cjs`**

測試 runtime 用一份小的英文字典（`EN`），不讀 `en.js`：這裏測的是判斷和填值，字典的內容由 Task 5 的完整性測試負責。

```javascript
// Run with: node --test tests/test_i18n.cjs (no npm dependencies).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// A small English dictionary: these tests are about the runtime, en.js about the words (test_i18n_keys.py)
const EN = {'设置': 'Settings', '有 {n} 条待汇报': '{n} reports waiting', '错过了 {time} 的{kind}': 'Missed the {kind} at {time}',
            '闹钟': 'alarm'};

function load(language, saved, blocked = false, search = '', {english = EN} = {}) {
  const values = new Map(saved ? [['thinksmart.uiLocale', saved]] : []);
  const picker = {value: '', addEventListener(event, fn) { this[event] = fn; }};
  const context = {navigator: {language}, URLSearchParams,
    localStorage: {getItem(k) { if (blocked) throw Error('disabled'); return values.get(k); }, setItem(k,v) { values.set(k,v); }},
    location: {search, reload() { this.reloaded = true; }},
    NodeFilter: {SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2},
    document: {documentElement: {}, body: {}, title: '小麦',
      createTreeWalker() {return {nextNode() {return null;}};},
      querySelectorAll(selector) {return selector === '[data-language-picker]' ? [picker] : [];}}
  };
  context.window = context;
  const root = path.join(__dirname, '..', 'web');
  vm.runInNewContext(fs.readFileSync(path.join(root, 'zh-Hant.js'), 'utf8'), context);
  if (english) context.UI_EN = english;
  vm.runInNewContext(fs.readFileSync(path.join(root, 'i18n.js'), 'utf8'), context);
  return {context, api: context.UII18n, values, picker};
}

test('traditional locale aliases and explicit saved preferences', () => {
  for (const language of ['zh-TW','zh-HK','zh-MO','zh-Hant','zh-Hant-TW']) {
    assert.equal(load(language).api.locale, 'zh-Hant');
  }
  assert.equal(load('zh-TW', 'zh-Hans').api.locale, 'zh-Hans');
  assert.equal(load('en-US', 'zh-Hant').api.locale, 'zh-Hant');
  assert.equal(load('zh-CN').api.locale, 'zh-Hans');
});

test('known UI copy is translated; arbitrary content and prototype names remain unchanged', () => {
  const {api} = load('zh-TW');
  assert.equal(api.t('设置'), '設定');
  assert.equal(api.t('软件更新'), '軟體更新');
  assert.equal(api.t('我的WiFi名称：设置网络'), '我的WiFi名称：设置网络');
  assert.equal(api.t('用户说：明天北京天气怎么样？'), '用户说：明天北京天气怎么样？');
  assert.equal(api.t('toString'), 'toString');
});

test('storage-disabled browsers can still load and translate', () => {
  assert.equal(load('zh-TW', null, true).api.t('设置'), '設定');
});

// spec §6.2: the kiosk adds ?lang on every load, so ?lang beats the saved value; an unknown ?lang is ignored
test('bookmarked locale initializes new devices and wins over a saved preference', () => {
  assert.equal(load('en-US', null, false, '?lang=zh-Hant').api.locale, 'zh-Hant');
  assert.equal(load('en-US', 'zh-Hans', false, '?lang=zh-Hant').api.locale, 'zh-Hant');
  assert.equal(load('en-US', null, false, '?lang=invalid').api.locale, 'en');
  assert.equal(load('zh-TW', 'zh-Hans', false, '?lang=invalid').api.locale, 'zh-Hans');
});

test('selector persists preference and document language is accessible', () => {
  const {api,context,picker,values} = load('zh-TW');
  api.init();
  assert.equal(context.document.documentElement.lang, 'zh-Hant');
  assert.equal(picker.value, 'zh-Hant');
  picker.value = 'zh-Hans'; picker.change();
  assert.equal(values.get('thinksmart.uiLocale'), 'zh-Hans');
  assert.equal(context.location.reloaded, true);
});

test('English: English browsers, ?lang=en and a saved en; zh-* stays Chinese, en-HK is English', () => {
  for (const language of ['en-US', 'en-HK', 'fr-FR', 'ja', '']) assert.equal(load(language).api.applied, 'en');
  assert.equal(load('zh-TW', null, false, '?lang=en').api.applied, 'en');
  assert.equal(load('zh-CN', 'en').api.applied, 'en');
  assert.equal(load('zh-SG').api.applied, 'zh-Hans');
  assert.equal(load('en-US').api.t('设置'), 'Settings');
});

test('without an English dictionary the page stays in Simplified Chinese', () => {
  const {api} = load('en-US', null, false, '', {english: null});
  assert.equal(api.locale, 'en');
  assert.equal(api.applied, 'zh-Hans');
  assert.equal(api.t('设置'), '设置');
});

test('templates: t() fills after translating; text() renders keyed answers, nested keys translated, plain values as given', () => {
  const {api} = load('en-US');
  assert.equal(api.t('有 {n} 条待汇报', {n: 3}), '3 reports waiting');
  assert.equal(api.t('不在字典里 {x}', {x: 'a'}), '不在字典里 a');
  assert.equal(api.text('设置'), 'Settings');
  assert.equal(api.text({msg_key: '错过了 {time} 的{kind}', msg_params: {time: '07:00', kind: {msg_key: '闹钟'}}}),
               'Missed the alarm at 07:00');
  assert.equal(api.text({msg_key: '错过了 {time} 的{kind}', msg_params: {time: '设置', kind: '闹钟'}}),
               'Missed the 闹钟 at 设置');
  assert.equal(api.text(null), '');
});

test('choosing a language replaces ?lang (the old one would win); the shell may refuse', async () => {
  const {api, context, values} = load('en-US', null, false, '?lang=zh-Hans&demo=1');
  assert.equal(await api.choose('en'), true);
  assert.equal(values.get('thinksmart.uiLocale'), 'en');
  assert.equal(new URLSearchParams(context.location.search).get('lang'), 'en');
  assert.equal(new URLSearchParams(context.location.search).get('demo'), '1');

  const refused = load('en-US', null, false, '?lang=zh-Hans');
  const asked = [];
  refused.api.setBeforeSwitch(lang => { asked.push(lang); return Promise.resolve(false); });
  assert.equal(await refused.api.choose('zh-Hant'), false);
  assert.deepEqual(asked, ['zh-Hant']);
  assert.equal(refused.values.get('thinksmart.uiLocale'), 'zh-Hans');   // what the bookmark saved, unchanged
  assert.equal(refused.context.location.search, '?lang=zh-Hans');

  assert.equal(await load('en-US').api.choose('fr'), false);
  assert.equal(await load('en-US', null, false, '', {english: null}).api.choose('en'), false);
});
```

- [ ] **測試**

```bash
node --test tests/*.cjs 2>&1 | grep -E '^(not ok|# (pass|fail))'
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
```

Expected：`# pass 9`、`# fail 0`；`171 passed`。

- [ ] **litmus、commit**

```bash
git add web/i18n.js tests/test_i18n.cjs
git commit -m "i18n runtime: English locale, ?lang first, templates and keyed backend messages"
```

---

### Task 4: 頁面的範本、日期、標點和後端的鍵；繁中字典補齊

**Files:**
- Modify: `web/v2/app.js`、`web/app.js`、`thinksmart_client/alarms.py`、`thinksmart_client/app.py`（以下面的一次性腳本修改）
- Modify: `web/zh-Hant.js`
- Create: `tests/i18n_keys.py`、`tests/test_i18n_keys.py`、`tests/gateway_kiosk_keys.json`、`tests/updater_keys.json`
- Modify: `tests/test_alarms.py`

**Interfaces:**
- Consumes: Task 3 的 `UII18n.t(key, params)`、`UII18n.text()`、`UII18n.setBeforeSwitch()`、`UII18n.applied`。
- Produces: `alarms.view()` 的 `rule`；`Alarms.take_due(now, ringing=(), msgs=None)`；`alarm_view()['ringing']['notes_msg']`；頁面函式 `longDate(d, gap)`、`weekdayName(day)`、`reason(r, fallback)`、`repeatText(rule)`、`updMsg(job)`、`needsReboot(job)`、`KIND_NAME`；`tests/i18n_keys.py` 的 `CHINESE`、`SCRIPTS`、`source_keys()`、`dictionaries()`。

**改動的範圍**（以 #4 的程式碼逐一盤點）：

- **詞序：** 片段夾着數值的地方改為一個範本鍵，例如 `${t("有")} ${n} ${t("条待汇报")}` → `t("有 {n} 条待汇报", {n})`。數值在最前面、英文照樣通順的（`${n} ${t("分钟前")}`、`${t("已切换到")} ${label}`）不改。
- **日期：** `WEEK = t("日一二三四五六")` 用字元位置取星期，翻譯後就錯了。改為中文時照舊顯示「11月14日 星期五」，英文時用 `toLocaleDateString('en', …)`（Friday, November 14）。鬧鐘的每週重複用 `weekdayName()`。
- **句子之間的中文標點**（`'。'`、`'，'`、`'、'`、`'；'`、`'：'`）改經字典：`t("。")` 等，英文值是 `". "`、`", "`、`", "`、`"; "`、`": "`。
- **後端送來的文字：**
  - `toast()` 改用 `UII18n.text()`，所以後端的普通字串（客戶端 Python 的固定句子）照舊按字典翻譯，`{msg_key, msg_params}` 也能顯示；
  - `r.error || t("…")` 改為 `reason(r, t("…"))`：有 `msg_key`（閘道轉來的錯誤）就整個物件交給 `text()`；
  - 鈴聲名稱（`alarms.TONES` 的值）經 `t()`；
  - 響鈴畫面的種類用頁面自己的 `KIND_NAME`，不用 Python 的中文 `type`；錯過提示用 `notes_msg`；
  - 鬧鐘清單的重複規則由頁面按 `rule` 組成，不顯示 Python 的中文 `repeat`（`repeat` 保留給大模型）。
- **更新器：** `updMsg(job)` 和 `needsReboot(job)`，見「跨計劃的約定」第 2 點；`check_error` 先看 `check_error_msg`。
- **外殼：** `thinksmartShell.language` 為真時，`setBeforeSwitch()` 先經 `set_language` 寫入外殼的語言檔（「跨計劃的約定」第 1 點）。
- **v1 頁面**（`/v1`）的三個範例句：`「${t("今天北京天气怎么样？」")}` 這種把「 放在 `t()` 外面的寫法，改為整句 `t("「今天北京天气怎么样？」")`。

不改的：`describe_when()`、`describe_in()`、`describe_repeat()` 和 `notes` 的中文（大模型和語音用）；`mcp.py` 的工具說明；鬧鐘的語音。

- [ ] **一次性腳本：存為 `/tmp/i18n_templates.py`，在 repo 根目錄執行**

每一項舊文字必須剛好出現指定的次數（第三項，預設 1），否則腳本停下、什麼都不寫。這個腳本不 commit。

```python
"""One-off: the page edits for the English UI (word order, keyed messages, dates). Each old text must
occur exactly as often as its third item says (once by default); run from the repo root."""
from pathlib import Path

EDITS = {
    'web/v2/app.js': [
        ('const WEEK = UII18n.t("日一二三四五六");',
         "const WEEK = '日一二三四五六';   // Chinese weekday characters by getDay() (both scripts write them the same)\n"
         "// 11月14日 星期五 in Chinese, Friday, November 14 in English (word order differs: no fragments)\n"
         "function longDate(d, gap = ' ') {\n"
         "  return UII18n.applied === 'en' ? d.toLocaleDateString('en', { weekday: 'long', month: 'long', day: 'numeric' })\n"
         "    : `${d.getMonth() + 1}月${d.getDate()}日${gap}星期${WEEK[d.getDay()]}`;\n"
         "}\n"
         "// an alarm's weekly days: 1 is Monday … 7 is Sunday\n"
         "function weekdayName(day) {\n"
         "  return UII18n.applied === 'en' ? new Date(2024, 0, day).toLocaleDateString('en', { weekday: 'short' }) : WEEK[day % 7];\n"
         "}\n"
         "// what a backend answer says went wrong: its {msg_key, msg_params}, else its error text, else ours\n"
         "const reason = (r, fallback) => (r && (r.msg_key ? r : r.error)) || fallback;"),
        ("$('bigDate').textContent = `${now.getMonth() + 1}${UII18n.t(\"月\")}${now.getDate()}${UII18n.t(\"日  星期\")}${WEEK[now.getDay()]}`;",
         "$('bigDate').textContent = longDate(now, '  ');"),
        ('thinking: [`<em>${esc(modelName())}</em> ${UII18n.t("正在思考")}`,',
         'thinking: [UII18n.t("{name} 正在思考", { name: `<em>${esc(modelName())}</em>` }),'),
        ('`${UII18n.t("有")} ${reports} ${UII18n.t("条待汇报")}`',
         'UII18n.t("有 {n} 条待汇报", { n: reports })'),
        ('if (r.ok === false) error = r.error || UII18n.t("切换失败");',
         'if (r.ok === false) error = reason(r, UII18n.t("切换失败"));'),
        ('`${UII18n.t("现在是睡眠时段，到")} ${s.end} ${UII18n.t("结束")}` : `${UII18n.t("每天")} ${s.start} ${UII18n.t("到")} ${s.end} ${UII18n.t("是睡眠时段，现在不在")}`',
         'UII18n.t("现在是睡眠时段，到 {end} 结束", { end: s.end }) : UII18n.t("每天 {start} 到 {end} 是睡眠时段，现在不在", { start: s.start, end: s.end })'),
        ("toast(r.error || UII18n.t(\"没保存上\"), 'error');",
         "toast(reason(r, UII18n.t(\"没保存上\")), 'error');", 4),
        ("`${d.getMonth() + 1}${UII18n.t(\"月\")}${d.getDate()}${UII18n.t(\"日 星期\")}${WEEK[d.getDay()]}`;",
         'longDate(d);'),
        ('`${UII18n.t("倒计时，")}${hhmm(v.at)} ${UII18n.t("响")}${v.snoozed',
         '`${UII18n.t("倒计时，{time} 响", { time: hhmm(v.at) })}${v.snoozed'),
        ('if (v.repeat) sub.push(esc(v.repeat));',
         'if (v.rule) sub.push(repeatText(v.rule));'),
        ('function renderAlarms() {',
         "// the repeat rule as the alarm list shows it (alarms.py view()'s rule)\n"
         "function repeatText(rule) {\n"
         "  if (rule.type === 'daily') return UII18n.t(\"每天\");\n"
         "  if (rule.type === 'workdays') return UII18n.t(\"每个工作日（周一到周五）\");\n"
         "  if (rule.type === 'weekly') return UII18n.t(\"每周{days}\", { days: (rule.days || []).map(weekdayName).join(UII18n.t(\"、\")) });\n"
         "  return UII18n.t(\"每月 {day} 号\", { day: rule.day }) + (rule.day > 28 ? UII18n.t(\"（没有这一天的月份在最后一天）\") : '');\n"
         "}\n"
         "function renderAlarms() {"),
        ('`<button data-tone="${esc(k)}" class="${k === a.tone ? \'on\' : \'\'}">${esc(name)}</button>`',
         '`<button data-tone="${esc(k)}" class="${k === a.tone ? \'on\' : \'\'}">${esc(UII18n.t(name))}</button>`'),
        ('`<div class="mh more">${UII18n.t("还有")} ${a.missed.length - 3} ${UII18n.t("条")}</div>`',
         '`<div class="mh more">${UII18n.t("还有 {n} 条", { n: a.missed.length - 3 })}</div>`'),
        ('if (!sys.current || !ui.version) return job.message || UII18n.t("更新完成");',
         'if (!sys.current || !ui.version) return updMsg(job) || UII18n.t("更新完成");'),
        ("+ (/重启设备后生效/.test(job.message || '') ? UII18n.t(\"，部分改动重启设备后生效\") : '');",
         "+ (needsReboot(job) ? UII18n.t(\"，部分改动重启设备后生效\") : '');"),
        ('let updArmed = 0;',
         "// the updater's message: {msg_key, msg_params} from a keyed updater, else its plain message\n"
         "const updMsg = job => UII18n.text(job.msg_key ? job : job.message || '');\n"
         "// job.reboot from the updater; an older updater only says it in its Chinese message\n"
         "const needsReboot = job => (typeof job.reboot === 'boolean' ? job.reboot : /重启设备后生效/.test(job.message || ''));\n"
         "let updArmed = 0;"),
        ('`${UII18n.t("系统层")} ${sys.available.version} ${UII18n.t("要重刷新镜像才能装")}`',
         'UII18n.t("系统层 {version} 要重刷新镜像才能装", { version: sys.available.version })'),
        ('text = failed ? job.message + UII18n.t("。可以再试一次")',
         'text = failed ? updMsg(job) + UII18n.t("。可以再试一次")'),
        ('`${UII18n.t("更新时语音助手会停一会儿（约")} ${parts.length > 1 ? 2 : 1} ${UII18n.t("分钟）")}`',
         'UII18n.t("更新时语音助手会停一会儿（约 {n} 分钟）", { n: parts.length > 1 ? 2 : 1 })'),
        ('      : failed ? job.message\n      : u.check_error ? `${cur}。${u.check_error}`',
         '      : failed ? updMsg(job)\n      : u.check_error ? `${cur}。${UII18n.text(u.check_error_msg || u.check_error)}`'),
        ('`（${ago(u.checked)}${UII18n.t("检查过）")}`',
         'UII18n.t("（{ago}检查过）", { ago: ago(u.checked) })'),
        ("toast(job.state === 'done' ? updDoneText(ui.update, job) : job.message,",
         "toast(job.state === 'done' ? updDoneText(ui.update, job) : updMsg(job),"),
        ("toast((r && r.error) || UII18n.t(\"没能开始更新\"), 'error');",
         "toast(reason(r, UII18n.t(\"没能开始更新\")), 'error');"),
        ('`${r.agents.join(UII18n.t("和"))}${UII18n.t("自己那边的对话没有动")}`',
         'UII18n.t("{agents}自己那边的对话没有动", { agents: r.agents.join(UII18n.t("和")) })'),
        ("if (!r || !r.ok) return toast((r && r.error) || UII18n.t(\"没能清除\"), 'error');",
         "if (!r || !r.ok) return toast(reason(r, UII18n.t(\"没能清除\")), 'error');"),
        (': (r && r.error) || UII18n.t("没能清除"), r && r.ok',
         ': reason(r, UII18n.t("没能清除")), r && r.ok'),
        ('`${UII18n.t("在同一网络的电脑上打开 http://")}${ip}:16688/admin ${UII18n.t("进网关后台")}`',
         'UII18n.t("在同一网络的电脑上打开 {url} 进网关后台", { url: `http://${ip}:16688/admin` })'),
        ('`${UII18n.t("手机上显示为「")}${b.name}」`',
         'UII18n.t("手机上显示为「{name}」", { name: b.name })'),
        ('`${UII18n.t("正在等手机连接（还剩")} ${b.window} ${UII18n.t("秒）：在手机的蓝牙设置里点「")}${b.name}」，${UII18n.t("配对不用输密码。")}`',
         'UII18n.t("正在等手机连接（还剩 {s} 秒）：在手机的蓝牙设置里点「{name}」，配对不用输密码。", { s: b.window, name: b.name })'),
        ('`${UII18n.t("停止等待（")}${b.window} ${UII18n.t("秒）")}`',
         'UII18n.t("停止等待（{s} 秒）", { s: b.window })'),
        ("if (!r || !r.ok) toast((r && r.error) || UII18n.t(\"没能关机\"), 'error');",
         "if (!r || !r.ok) toast(reason(r, UII18n.t(\"没能关机\")), 'error');"),
        ('`${UII18n.t("与")} ${m.label} ${UII18n.t("的对话")}`',
         'UII18n.t("与 {name} 的对话", { name: m.label })'),
        ('  t.textContent = UII18n.t(text);',
         '  t.textContent = UII18n.text(text);   // a string of ours, or a {msg_key, msg_params} answer'),
        ('const KIND_ICON = { timer: UII18n.t("计时"), alarm: UII18n.t("闹钟"), reminder: UII18n.t("提醒") };',
         'const KIND_ICON = { timer: UII18n.t("计时"), alarm: UII18n.t("闹钟"), reminder: UII18n.t("提醒") };\n'
         'const KIND_NAME = { timer: UII18n.t("倒计时"), alarm: UII18n.t("闹钟"), reminder: UII18n.t("提醒") };'),
        ("[...new Set(items.map(v => v.type))].join('、')",
         '[...new Set(items.map(v => KIND_NAME[v.kind]))].join(UII18n.t("、"))'),
        ("items.map(v => v.label).filter(Boolean).join('、')",
         'items.map(v => v.label).filter(Boolean).join(UII18n.t("、"))'),
        ("(r.notes || []).join('；')",
         '(r.notes_msg || r.notes || []).map(UII18n.text).join(UII18n.t("；"))'),
        ("(cur ? cur + '。' : '')",
         '(cur ? cur + UII18n.t("。") : \'\')'),
        ('`${UPD_STAGE[job.state]}${pct}。`',
         '`${UPD_STAGE[job.state]}${pct}${UII18n.t("。")}`'),
        ('`${cur}，${UII18n.t("下载约")} ',
         '`${cur}${UII18n.t("，")}${UII18n.t("下载约")} '),
        ("(blocked ? `。${blocked}` : '')",
         '(blocked ? UII18n.t("。") + blocked : \'\')'),
        ('`${updDoneText(u, job)}，${UII18n.t("已是最新")}`',
         '`${updDoneText(u, job)}${UII18n.t("，")}${UII18n.t("已是最新")}`'),
        ('`${cur}。${UII18n.text(u.check_error_msg || u.check_error)}`',
         '`${cur}${UII18n.t("。")}${UII18n.text(u.check_error_msg || u.check_error)}`'),
        ('`${cur}。${blocked}`',
         '`${cur}${UII18n.t("。")}${blocked}`'),
        ('`${cur}，${UII18n.t("已是最新")}`',
         '`${cur}${UII18n.t("，")}${UII18n.t("已是最新")}`'),
        ('text += `。${UII18n.t("官方客戶端更新會移除此裝置的自訂修改，請確認新版本已包含所需功能後再更新。")}`',
         'text += `${UII18n.t("。")}${UII18n.t("官方客戶端更新會移除此裝置的自訂修改，請確認新版本已包含所需功能後再更新。")}`'),
        ("(note ? '。' + note : '')",
         '(note ? UII18n.t("。") + note : \'\')'),
        ("(r.detail ? '：' + r.detail : '')",
         '(r.detail ? UII18n.t("：") + r.detail : \'\')'),
        ('${ssid}，${UII18n.t("请再试一次")}',
         '${ssid}${UII18n.t("，")}${UII18n.t("请再试一次")}'),
        ('${ssid}，${UII18n.t("下次连接需要重新输入密码")}',
         '${ssid}${UII18n.t("，")}${UII18n.t("下次连接需要重新输入密码")}'),
        ('  if (done) done(r);\n};\n',
         '  if (done) done(r);\n};\n'
         '// The kiosk keeps the device\'s language in its own file and adds ?lang from it (spec §6.2): a shell that\n'
         '// offers set_language writes the file first; an older shell, or a desktop browser, only this browser\'s storage.\n'
         'if (shellWifi && window.thinksmartShell.language) {\n'
         '  UII18n.setBeforeSwitch(async lang => {\n'
         '    const r = await shellCall(\'set_language\', { lang });\n'
         '    if (r.ok !== true) toast(UII18n.t("没能切换界面语言"), \'error\');\n'
         '    return r.ok === true;\n'
         '  });\n'
         '}\n'),
    ],
    'web/app.js': [
        ('const WEEK = UII18n.t("日一二三四五六");',
         "const WEEK = '日一二三四五六';   // Chinese weekday characters by getDay()"),
        ("`${now.getMonth() + 1}${UII18n.t(\"月\")}${now.getDate()}${UII18n.t(\"日 星期\")}${WEEK[now.getDay()]}`;",
         "UII18n.applied === 'en' ? now.toLocaleDateString('en', { weekday: 'long', month: 'long', day: 'numeric' })\n"
         "    : `${now.getMonth() + 1}月${now.getDate()}日 星期${WEEK[now.getDay()]}`;"),
        ('`${esc(modelName())} ${UII18n.t("正在思考…")}`',
         'UII18n.t("{name} 正在思考…", { name: esc(modelName()) })'),
        ("if (r.ok === false) toast(r.error || UII18n.t(\"切换失败\"), 'error');",
         "if (r.ok === false) toast((r.msg_key ? r : r.error) || UII18n.t(\"切换失败\"), 'error');"),
        ('`${UII18n.t("与")} ${m.label} ${UII18n.t("的对话")}`',
         'UII18n.t("与 {name} 的对话", { name: m.label })'),
        ('  t.textContent = UII18n.t(text);',
         '  t.textContent = UII18n.text(text);'),
        ('「${UII18n.t("今天北京天气怎么样？」")}', '${UII18n.t("「今天北京天气怎么样？」")}'),
        ('「${UII18n.t("嗨 Claude，帮我想个周末计划」")}', '${UII18n.t("「嗨 Claude，帮我想个周末计划」")}'),
        ('「${UII18n.t("把音量调小一点」")}', '${UII18n.t("「把音量调小一点」")}'),
    ],
    'thinksmart_client/alarms.py': [
        ('    def take_due(self, now, ringing=()):',
         '    def take_due(self, now, ringing=(), msgs=None):'),
        ('        moved on to their next time."""\n        ring, notes, changed = [], [], False',
         '        moved on to their next time. msgs: a list that also gets each note as {msg_key, msg_params},\n'
         '        for the page (the notes themselves are spoken)."""\n        ring, notes, changed = [], [], False'),
        ('                notes.append(f"错过了 {datetime.datetime.fromtimestamp(t):%H:%M} 的{KINDS[item[\'kind\']]}")',
         '                hm = f\'{datetime.datetime.fromtimestamp(t):%H:%M}\'\n'
         '                notes.append(f"错过了 {hm} 的{KINDS[item[\'kind\']]}")\n'
         '                if msgs is not None:\n'
         '                    msgs.append({\'msg_key\': \'错过了 {time} 的{kind}\',\n'
         '                                 \'msg_params\': {\'time\': hm, \'kind\': {\'msg_key\': KINDS[item[\'kind\']]}}})'),
        ("                'repeat': describe_repeat(item['repeat']), 'snoozed'",
         "                'repeat': describe_repeat(item['repeat']), 'rule': item['repeat'], 'snoozed'"),
    ],
    'thinksmart_client/app.py': [
        ("        items, notes = self.alarms.take_due(now, self.ring['items'] if self.ring else ())",
         "        msgs = []\n        items, notes = self.alarms.take_due(now, self.ring['items'] if self.ring else (), msgs)"),
        ("            self.ring['notes'] += notes\n",
         "            self.ring['notes'] += notes\n            self.ring['notes_msg'] = self.ring.get('notes_msg', []) + msgs\n"),
        ("            self.ring = {'items': items, 'notes': notes, 'started': now,",
         "            self.ring = {'items': items, 'notes': notes, 'notes_msg': msgs, 'started': now,"),
        ("                                     'notes': ring['notes'], 'started': ring['started']},",
         "                                     'notes': ring['notes'], 'notes_msg': ring.get('notes_msg', []),\n"
         "                                     'started': ring['started']},"),
    ],
}

if __name__ == '__main__':
    for name, pairs in EDITS.items():
        path = Path(name)
        src = path.read_text(encoding='utf-8')
        for old, new, *count in pairs:
            n, want = src.count(old), (count or [1])[0]
            assert n == want, f'{name}: {n} matches (want {want}) for {old[:60]!r}'
            src = src.replace(old, new)
        path.write_text(src, encoding='utf-8')
        print(name, len(pairs), 'edits')
```

```bash
python3 /tmp/i18n_templates.py && rm /tmp/i18n_templates.py
node --check web/v2/app.js && node --check web/app.js && echo syntax-ok
```

Expected：`web/v2/app.js 51 edits`、`web/app.js 9 edits`、`thinksmart_client/alarms.py 4 edits`、`thinksmart_client/app.py 4 edits`、`syntax-ok`。

- [ ] **其他 repo 的鍵**

`tests/gateway_kiosk_keys.json`（閘道 `main` = `2d067d94` 的 `handle_kiosk_llm_use`、`handle_kiosk_chat_clear` 裏 `self._error()` 的第一個參數和 `msg()`、`label()` 的範本）：

```json
["仅限本机", "缺少 device", "没有这个 Grok Bot，请先在管理后台的 Grok Bot 页勾选", "配置里没有 {name}", "不支持这个厂商", "{vendor} 还没配置好，请先填写接口地址、模型和 API Key 并保存", "模型没有配置好", "切换失败：{error}"]
```

`tests/updater_keys.json`（由更新器計劃填）：

```json
[]
```

- [ ] **`tests/i18n_keys.py`**

```python
"""The page's source text: every dictionary key the client can show (spec §6.4).

Shared by tests/test_i18n_keys.py; run directly to print the keys missing from a dictionary."""
import ast
import json
import re
import shutil
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / 'web'
PAGES = [WEB / 'index.html', WEB / 'v2' / 'index.html']
SCRIPTS = [WEB / 'app.js', WEB / 'v2' / 'app.js']
ATTRS = ('title', 'aria-label', 'placeholder', 'data-kb-enter')
SKIP = ('script', 'style', 'textarea')
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr'}
# Chinese in every test: CJK ideographs, CJK punctuation, full-width forms
CHINESE = re.compile('[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]')
T_CALL = re.compile(r'UII18n\.t\(("(?:[^"\\]|\\.)*")')


class _Page(HTMLParser):
    """Text nodes and attributes the way i18n.js init() walks them."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack, self.keys = [], set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        skip = tag in SKIP or 'data-no-i18n' in attrs or (self.stack and self.stack[-1])
        for name in ATTRS:
            if attrs.get(name):
                self.keys.add(attrs[name])
        if tag not in VOID:
            self.stack.append(bool(skip))

    def handle_endtag(self, tag):
        if tag not in VOID and self.stack:
            self.stack.pop()

    def handle_data(self, data):
        if data.strip() and not (self.stack and self.stack[-1]):
            self.keys.add(data.strip())


def html_keys():
    keys = set()
    for page in PAGES:
        p = _Page()
        p.feed(page.read_text(encoding='utf-8'))
        keys |= p.keys
    return {k for k in keys if CHINESE.search(k)}


def script_keys():
    return {json.loads(m) for path in SCRIPTS for m in T_CALL.findall(path.read_text(encoding='utf-8'))}


def _consts(node):
    return {n.value for n in ast.walk(node) if isinstance(n, ast.Constant) and isinstance(n.value, str)
            and CHINESE.search(n.value)}


def python_keys():
    """What the client's Python sends the page: toast texts, 'error' answers, msg_key templates,
    alarm kinds (nested in msg_params) and ring-tone names."""
    keys = set()
    pkg = ROOT / 'thinksmart_client'
    for name in ('app.py', 'web.py', 'alarms.py'):
        for node in ast.walk(ast.parse((pkg / name).read_text(encoding='utf-8'))):
            if isinstance(node, ast.Dict):
                for k, v in zip(node.keys, node.values):
                    if isinstance(k, ast.Constant) and k.value in ('text', 'error', 'msg_key'):
                        keys |= _consts(v)
    for node in ast.walk(ast.parse((pkg / 'alarms.py').read_text(encoding='utf-8'))):
        if isinstance(node, ast.Assign) and any(getattr(t, 'id', '') in ('TONES', 'KINDS') for t in node.targets):
            keys |= _consts(node.value)
    return keys


def fixture_keys():
    """Keys other repos send the page: the gateway's /kiosk/llm/use and /kiosk/chat/clear answers
    (gateway_kiosk_keys.json) and the updater's messages (updater_keys.json, filled by the updater plan)."""
    keys = set()
    for name in ('gateway_kiosk_keys.json', 'updater_keys.json'):
        keys |= set(json.loads((ROOT / 'tests' / name).read_text(encoding='utf-8')))
    return keys


def source_keys():
    return html_keys() | script_keys() | python_keys() | fixture_keys()


def dictionaries():
    """{name: dict} from web/zh-Hant.js and web/en.js, read by node exactly as the browser would."""
    node = shutil.which('node') or 'node'
    code = ("const vm=require('vm'),fs=require('fs');const c={};c.window=c;"
            "for (const f of process.argv.slice(1)) if (fs.existsSync(f)) vm.runInNewContext(fs.readFileSync(f,'utf8'),c);"
            "process.stdout.write(JSON.stringify({UI_ZH_HANT:c.UI_ZH_HANT||{},UI_ZH_HANS:c.UI_ZH_HANS||{},UI_EN:c.UI_EN||{}}))")
    out = subprocess.run([node, '-e', code, str(WEB / 'zh-Hant.js'), str(WEB / 'en.js')],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


if __name__ == '__main__':
    keys, d = source_keys(), dictionaries()
    print(len(keys), 'source keys;', {k: len(v) for k, v in d.items()})
    zh = set(d['UI_ZH_HANT']) | set(d['UI_ZH_HANS'])
    print('not in either zh dictionary:', sorted(keys - zh))
    print('zh entries no longer in the source:', sorted(zh - keys))
    print('not in en.js:', sorted(keys - set(d['UI_EN'])))
    print('en.js entries no longer in the source:', sorted(set(d['UI_EN']) - keys))
```

- [ ] **`tests/test_i18n_keys.py`（中文部分和守門）**

```python
"""Dictionary completeness (spec §6.4): every source text the page can show has exactly one Chinese entry
and one English entry, and the page scripts write no Chinese of their own outside UII18n.t("…").

Source text: tests/i18n_keys.py. Needs node (the dictionaries are read as the browser reads them)."""
import re
import shutil

import pytest

from i18n_keys import CHINESE, SCRIPTS, dictionaries, source_keys

pytestmark = pytest.mark.skipif(shutil.which('node') is None, reason='needs node')
PLACEHOLDER = re.compile(r'\{(\w+)\}')
# the language picker names each language in its own script, in every language
ENDONYMS = {'简体中文', '繁體中文'}
# Chinese the page writes outside t(): only on Chinese pages, or to read an older updater's message
CHINESE_ONLY = {
    "const WEEK = '日一二三四五六';   // Chinese weekday characters by getDay()",
    "const WEEK = '日一二三四五六';   // Chinese weekday characters by getDay() (both scripts write them the same)",
    ': `${now.getMonth() + 1}月${now.getDate()}日 星期${WEEK[now.getDay()]}`;',
    ': `${d.getMonth() + 1}月${d.getDate()}日${gap}星期${WEEK[d.getDay()]}`;',
    "const needsReboot = job => (typeof job.reboot === 'boolean' ? job.reboot : /重启设备后生效/.test(job.message || ''));",
}
T_CALL = re.compile(r'UII18n\.t\("(?:[^"\\]|\\.)*"')
COMMENT = re.compile(r'(?<![:\'"\\])//.*$')


def test_every_source_text_has_one_chinese_entry():
    keys, d = source_keys(), dictionaries()
    hant, hans = set(d['UI_ZH_HANT']), set(d['UI_ZH_HANS'])
    assert hant & hans == set()
    assert sorted(keys - hant - hans) == [], 'missing from zh-Hant.js'
    assert sorted((hant | hans) - keys) == [], 'zh-Hant.js entries no source shows'


def test_values_keep_placeholders_and_english_has_no_chinese():
    d = dictionaries()
    for name, catalog in d.items():
        for k, v in catalog.items():
            assert v.strip(), (name, k)
            assert set(PLACEHOLDER.findall(v)) == set(PLACEHOLDER.findall(k)), (name, k, v)
    for k, v in d['UI_EN'].items():
        if '小麦' in k:
            assert '小麦' in v, k   # the wake word stays as said (spec §6.3)
        elif k in ENDONYMS:
            assert v == k
        else:
            assert not CHINESE.search(v), (k, v)


def test_page_scripts_write_chinese_only_through_t():
    stray = []
    for path in SCRIPTS:
        for i, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            code = COMMENT.sub('', T_CALL.sub('T', line)).strip()
            if CHINESE.search(code) and line.strip() not in CHINESE_ONLY:
                stray.append(f'{path.parent.name}/{path.name}:{i}: {line.strip()}')
    assert stray == []
```

**守門能失敗的證明：** 在腳本執行前（#4 的 `app.js`），`test_page_scripts_write_chinese_only_through_t` 會列出二十多行（`'。'`、`join('、')`、`「${…}` 等）；執行後只剩 `CHINESE_ONLY` 的五行。實作時先在腳本執行前跑一次這個測試，確認它失敗，再跑腳本。

- [ ] **補齊繁中字典**

```bash
python3 tests/i18n_keys.py
```

照輸出的兩份清單改 `web/zh-Hant.js`：

1. `not in either zh dictionary`：简中原文加進 `UI_ZH_HANT`，繁中原文加進 `UI_ZH_HANS`。繁中寫法沿用 #4 的用詞（設定、軟體、連線、網路、螢幕、儲存、搜尋、訊息、裝置、週）。简繁寫法相同的（例如「今天」「模型」「、」）也要加，值就是原文：完整性測試要求每一條原文都有條目，不靠人工判斷哪些可以省略。標點條目（`。`、`，`、`、`、`；`、`：`）的繁中值跟原文相同。
2. `zh entries no longer in the source`：刪除。包括 #4 本來就沒用到的三條（`已保存`、`未登录`、`没有修改`）和這個 task 換成範本後不再出現的片段（例如 `有`、`条待汇报`、`月`、`日一二三四五六`）。
3. 範本鍵的繁中值保留同樣的 `{名稱}`。

- [ ] **鬧鐘的測試（加在 `tests/test_alarms.py` 末尾）**

```python


def test_missed_notes_also_come_keyed_for_the_page(tmp_path):
    clock = Clock(2026, 11, 3, 6, 0)
    alarms.Alarms(tmp_path, clock).create('alarm', '起床', time='07:00')
    clock.t = ts(2026, 11, 3, 7, 40)    # off from before 7:00 until 7:39
    msgs = []
    ring, notes = alarms.Alarms(tmp_path, clock).take_due(clock(), (), msgs)
    assert notes == ['错过了 07:00 的闹钟']   # still spoken as before
    assert msgs == [{'msg_key': '错过了 {time} 的{kind}', 'msg_params': {'time': '07:00', 'kind': {'msg_key': '闹钟'}}}]


def test_view_carries_the_repeat_rule_for_the_page(tmp_path):
    a = alarms.Alarms(tmp_path, Clock(2026, 11, 3, 6, 0))
    item = a.create('alarm', '吃药', time='07:10', repeat={'type': 'weekly', 'days': [3, 1]})
    v = a.view(a.get(item['id']))
    assert v['rule'] == a.get(item['id'])['repeat'] and v['rule']['type'] == 'weekly'
    assert v['repeat'] == '每周一、三'   # the model still reads the Chinese description


@pytest.mark.asyncio
async def test_the_ring_screen_gets_the_missed_notes_keyed(tmp_path, monkeypatch):
    Speaker(monkeypatch, 40)
    clock = Clock(2026, 11, 3, 6, 0)
    c = make_client(tmp_path, monkeypatch, clock)
    c.alarms.create('alarm', '起床', time='07:00')
    clock.t = ts(2026, 11, 3, 7, 40)
    await c._alarm_tick(clock())
    await asyncio.sleep(0.05)
    ringing = c.alarm_view()['ringing']
    assert ringing['notes'] == ['错过了 07:00 的闹钟']
    assert ringing['notes_msg'][0]['msg_key'] == '错过了 {time} 的{kind}'
    await c.stop_alarm()
```

- [ ] **測試**

```bash
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
node --test tests/*.cjs 2>&1 | grep -E '^# (pass|fail)'
```

Expected：`177 passed`（171 加上 `test_i18n_keys.py` 的 3 項和鬧鐘的 3 項）；node `# pass 9`、`# fail 0`。

- [ ] **litmus、commit**

```bash
git add web/v2/app.js web/app.js thinksmart_client/alarms.py thinksmart_client/app.py web/zh-Hant.js \
        tests/i18n_keys.py tests/test_i18n_keys.py tests/gateway_kiosk_keys.json tests/updater_keys.json tests/test_alarms.py
git commit -m "Page text through templates and keys: word order, dates, punctuation, backend and updater messages"
```

---

### Task 5: 英文字典和語言選單

**Files:**
- Create: `web/en.js`、`tests/test_i18n_page.cjs`
- Modify: `web/index.html`、`web/v2/index.html`、`tests/test_i18n_keys.py`、`README.md`

**Interfaces:**
- Consumes: Task 4 的頁面函式、`tests/i18n_keys.py`。
- Produces: `window.UI_EN`。

- [ ] **語言選單和載入 `en.js`**（兩個頁面各兩處）

`web/index.html` 和 `web/v2/index.html`：

- `<option value="zh-Hans">简体中文</option><option value="zh-Hant">繁體中文</option>` 改為 `<option value="zh-Hans">简体中文</option><option value="zh-Hant">繁體中文</option><option value="en">English</option>`；
- `<script src="/static/zh-Hant.js"></script>` 之後加一行 `<script src="/static/en.js"></script>`（在 `i18n.js` 之前）。

- [ ] **英文的完整性測試（加在 `tests/test_i18n_keys.py`）**

```python
def test_english_has_exactly_the_source_texts():
    keys, en = source_keys(), set(dictionaries()['UI_EN'])
    assert sorted(keys - en) == [], 'missing from en.js'
    assert sorted(en - keys) == [], 'en.js entries no source shows'
```

先跑一次，確認它失敗並列出全部原文（`en.js` 還不存在）：

```bash
.venv/bin/python -m pytest -q -p no:cacheprovider tests/test_i18n_keys.py 2>&1 | tail -1
```

Expected：`1 failed, 3 passed`。

- [ ] **`web/en.js`**

以腳本產生，不要用編輯器手寫：鍵有前後空格和 HTML 標記，手寫容易漏掉空格。做法：

1. 寫一個暫存的 Python 檔（不 commit），內含一個 `{原文: 英文}` 的 dict，涵蓋 `python3 tests/i18n_keys.py` 列出的 `not in en.js` 全部條目；
2. 以 `json.dumps(…, ensure_ascii=False, indent=2)` 寫出 `web/en.js`，第一行是 `// Application copy only; preserve conversation content and user-entered values.`，然後是 `window.UI_EN = {…};`，鍵按原文排序；
3. 刪除暫存檔。

翻譯原則（spec §6.3：Claude 起草，維護者審閱）：

- 鍵前後的空格、`<span …>` 這類標記和屬性原樣保留，只翻譯文字；
- `{名稱}` 佔位符原樣保留（測試檢查）；
- 喚醒詞：鍵含「小麦」的條目，值保留「小麦小麦」或「小麦同学」，後面加拼音說明，例如 `说「小麦小麦」开始聊天` → `Say “小麦小麦” (xiǎo mài xiǎo mài) to start`；
- `简体中文`、`繁體中文` 的值跟鍵相同（每種語言都用自己的文字顯示）；
- 產品和協定名稱（Claude、Grok、WiFi、Bluetooth 在英文用 Bluetooth）不翻譯；
- 標點條目：`。` → `". "`、`，` → `", "`、`、` → `", "`、`；` → `"; "`、`：` → `": "`；以標點開頭的句子片段（例如 `，部分改动重启设备后生效`、`。可以再试一次`）同樣以 `", "`、`". "` 開頭；
- 範例句（v1 的三句提示、天氣等）譯成英文說法。

下面這些值由 `tests/test_i18n_page.cjs` 檢查，必須一字不差：

| 原文 | 英文 |
|---|---|
| `每天` | `Every day` |
| `每个工作日（周一到周五）` | `Every weekday (Monday to Friday)` |
| `每周{days}` | `Every {days}` |
| `每月 {day} 号` | `Monthly on day {day}` |
| `（没有这一天的月份在最后一天）` | ` (on the last day in shorter months)` |
| `、` | `, ` |
| `错过了 {time} 的{kind}` | `Missed the {kind} at {time}` |
| `闹钟` | `alarm` |
| `设置` | `Settings` |

- [ ] **`tests/test_i18n_page.cjs`**

```javascript
// The page's own helpers in English and Simplified Chinese (web/v2/app.js): node --test tests/test_i18n_page.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const WEB = path.join(__dirname, '..', 'web');
const APP = fs.readFileSync(path.join(WEB, 'v2', 'app.js'), 'utf8');
const CHINESE = /[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]/;

// the helpers' source, cut out of app.js the way tests/test_welcome.py does
function piece(re) {
  const m = APP.match(re);
  assert.ok(m, `not found in web/v2/app.js: ${re}`);
  return m[0];
}
const HELPERS = [
  piece(/^const WEEK = .*$/m),
  piece(/^function longDate\(.*?\n}\n/ms),
  piece(/^function weekdayName\(.*?\n}\n/ms),
  piece(/^const reason = .*$/m),
  piece(/^function repeatText\(.*?\n}\n/ms),
  piece(/^const updMsg = .*$/m),
  piece(/^const needsReboot = .*$/m),
].join('\n') + '\nthis.page = { longDate, weekdayName, reason, repeatText, updMsg, needsReboot };';

function page(language) {
  const context = {navigator: {language}, URLSearchParams, localStorage: {getItem() {}, setItem() {}},
                   location: {search: ''}};
  context.window = context;
  for (const f of ['zh-Hant.js', 'en.js', 'i18n.js']) vm.runInNewContext(fs.readFileSync(path.join(WEB, f), 'utf8'), context);
  vm.runInNewContext(HELPERS, context);
  return context.page;
}

test('dates follow the language: English word order, the Chinese format unchanged', () => {
  const day = new Date(2026, 10, 14);   // a Saturday
  assert.equal(page('en-US').longDate(day), 'Saturday, November 14');
  assert.equal(page('zh-CN').longDate(day), '11月14日 星期六');
  assert.equal(page('zh-CN').longDate(day, '  '), '11月14日  星期六');
  assert.deepEqual([1, 3, 7].map(page('en-US').weekdayName), ['Mon', 'Wed', 'Sun']);
  assert.deepEqual([1, 3, 7].map(page('zh-CN').weekdayName), ['一', '三', '日']);
});

test('alarm repeat rules in English', () => {
  const {repeatText} = page('en-US');
  for (const rule of [{type: 'daily'}, {type: 'workdays'}, {type: 'weekly', days: [1, 3]}, {type: 'monthly', day: 31}]) {
    assert.doesNotMatch(repeatText(rule), CHINESE, JSON.stringify(rule));
  }
  assert.equal(repeatText({type: 'weekly', days: [1, 3]}), 'Every Mon, Wed');
  assert.equal(page('zh-CN').repeatText({type: 'weekly', days: [1, 3]}), '每周一、三');
});

test("the updater's keyed messages and reboot flag; an older updater's plain message still works", () => {
  const en = page('en-US');
  const job = {message: '已更新到 1.0.1', msg_key: '错过了 {time} 的{kind}', msg_params: {time: '07:00', kind: {msg_key: '闹钟'}}};
  assert.equal(en.updMsg(job), 'Missed the alarm at 07:00');
  assert.equal(en.updMsg({message: '设置'}), 'Settings');
  assert.equal(en.updMsg({}), '');
  assert.equal(en.needsReboot({reboot: true}), true);
  assert.equal(en.needsReboot({reboot: false, message: '系统层已更新到 1.0.1，部分改动重启设备后生效'}), false);
  assert.equal(en.needsReboot({message: '系统层已更新到 1.0.1，部分改动重启设备后生效'}), true);
  assert.equal(en.needsReboot({message: '已更新到 1.0.1'}), false);
});

test('error answers: the gateway\'s {msg_key, msg_params}, else the error text, else our fallback', () => {
  const {reason} = page('en-US');
  const keyed = {ok: false, error: '配置里没有 X', msg_key: '配置里没有 {name}', msg_params: {name: 'X'}};
  assert.equal(reason(keyed, 'fallback'), keyed);
  assert.equal(reason({ok: false, error: '设置'}, 'fallback'), '设置');
  assert.equal(reason({ok: false}, 'fallback'), 'fallback');
  assert.equal(reason(null, 'fallback'), 'fallback');
});
```

（`updMsg` 的測試借用鬧鐘的鍵，因為更新器的鍵要等更新器計劃。）

- [ ] **README 的介面語言一節**

`## 介面語言` 之後的前三行（從「在設定頁的「介面語言」可切換」到「已儲存的手動選擇優先。」）換成：

```markdown
在設定頁的「介面語言」可切換简体中文、繁體中文和 English。決定次序：網址的 `?lang=` → 這個瀏覽器記住的選擇 → 瀏覽器的語言（`zh-TW`、`zh-HK`、`zh-MO`、`zh-Hant` 用繁體中文，其他 `zh` 用简体中文，其餘用英文）；無效的 `?lang` 會被忽略。
在裝置上，展示屏外殼保存裝置的介面語言，每次載入客戶端都會附上 `?lang`；外殼支援 `set_language` 時，切換語言會先由外殼寫入，再以新的 `?lang` 重新載入。
```

同一節的「v1、v2 介面共用 `web/i18n.js` 與 `web/zh-Hant.js`；新增介面文案時，使用 `UII18n.t()` 並補上字典。」換成：

```markdown
v1、v2 介面共用 `web/i18n.js`、`web/zh-Hant.js` 與 `web/en.js`。新增介面文案時使用 `UII18n.t()` 並補上三份字典；句子裏有數值時寫成範本 `UII18n.t("还有 {n} 条", { n })`，不要拼接片段。後端回傳 `{msg_key, msg_params}` 時用 `UII18n.text()` 顯示。
```

「語系測試（不需要音訊裝置或 npm 套件）：`node --test tests/test_i18n.cjs`。」換成：

```markdown
語系測試（不需要音訊裝置或 npm 套件）：`node --test tests/*.cjs`；字典完整性（需要 node）：`.venv/bin/python -m pytest tests/test_i18n_keys.py`。
```

- [ ] **測試**

```bash
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
node --test tests/*.cjs 2>&1 | grep -E '^# (pass|fail)'
```

Expected：`178 passed`；node `# pass 13`、`# fail 0`。

- [ ] **litmus、commit**

`en.js` 是一個不能拆的資料檔。若 litmus 因單檔大小以 exit 2 停下，只對這次 commit 設 `LITMUS_MAX_WEIGHTED_LINES_SINGLE_FILE` 和 `LITMUS_MAX_TOTAL_LINES`（兩者都要）。

```bash
git add web/en.js web/index.html web/v2/index.html tests/test_i18n_keys.py tests/test_i18n_page.cjs README.md
git commit -m "English UI: en.js, English in the language picker, page helpers tested in English"
```

---

### Task 6: 瀏覽器檢查、版本 1.0.0、merge

**Files:**
- Modify: `thinksmart_client/__init__.py`

- [ ] **在 headless Chrome 看 demo 頁面**

客戶端頁面的 `?demo=1` 不需要裝置：所有按鈕和資料都在頁面裏模擬。以靜態伺服器提供 `web/`（和 `web.py` 一樣：`/` 是 `v2/index.html`，`/static/` 是 `web/`）：

```bash
D=$(mktemp -d) && cp web/v2/index.html "$D/index.html" && ln -s "$PWD/web" "$D/static"
(cd "$D" && python3 -m http.server 18090 --bind 127.0.0.1 >/dev/null 2>&1 &)
```

以 headless Chrome（CDP，跟閘道計劃 Task 9 相同的做法）依序打開 `http://127.0.0.1:18090/?demo=1&lang=en` 和 `?demo=1&lang=zh-Hant`，每次在首頁、按 `#btnSettings` 打開設定頁之後，各讀一次 `document.body.innerText`，列出含中文的行，並記下 `Runtime.exceptionThrown`。

Expected：

- 英文頁面：沒有腳本錯誤。含中文的只有用戶的值和名稱（demo 的模型名稱、廠商名稱、鬧鐘標籤、對話內容）、語言選單的「简体中文」「繁體中文」和含「小麦」的句子；
- 繁中頁面：沒有简中的介面文字（對話內容和 demo 的用戶值除外）。

結束後停掉伺服器（`ss -ltnp | grep 18090` 找到 pid 再 `kill`），刪除 `$D`。

- [ ] **版本**

`thinksmart_client/__init__.py`：`__version__ = '0.1.6'` 改為 `__version__ = '1.0.0'`（spec §5.2：從 1.0.0 開始，高於母機現有的版本，避免跟上游日後的 0.x 重疊）。

```bash
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
node --test tests/*.cjs 2>&1 | grep -E '^# (pass|fail)'
git add thinksmart_client/__init__.py
# litmus PASS 後：
git commit -m "Version 1.0.0: the first Oh I'm Smart client"
```

Expected：`178 passed`；node `# pass 13`、`# fail 0`。

- [ ] **merge、push**

```bash
git switch main
git merge --no-ff feat/en-and-urls -m "Merge feat/en-and-urls: English UI, ohimsmart links, version 1.0.0"
.venv/bin/python -m pytest -q -p no:cacheprovider 2>&1 | tail -1
node --test tests/*.cjs 2>&1 | grep -E '^# (pass|fail)'
git push origin main
git merge-base --is-ancestor e7ec0de main && echo ancestor-ok
```

Expected：`178 passed`、node 13/13、`ancestor-ok`。

- [ ] **為映像計劃記錄出處的行**

```bash
git grep -n -E '(github(usercontent)?\.com[/:]|githubusercontent\.com/)justhalfbit' main --
```

把輸出（`NOTICE` 和 README 的出處行）記入主 repo 的工作狀態，映像計劃 Task 8 的 `line` 條目會用到。

---

## 實作記錄

`ohimsmart/oh-im-smart-client` 的 `main` = `2f1df0e`：pytest **179 passed**，node **14/14**。跟上面寫的不同之處（design review 第 1 輪的中、低問題和 litmus 的意見）：

- **Task 3：** `choose()` 把丟出例外或 reject 的掛鉤當作拒絕，留在原語言（加了測試）；`init()` 的文字替換改用函式，譯文裏的 `$` 不會被當成替換樣式。
- **Task 4：**
  - 一次性腳本先在記憶體裏檢查全部檔案，全部符合才寫入；
  - 另外三項修改：更新中的標題改為範本 `正在更新{what} {version}`；系統層更新時的兩個片段合成一句 `屏幕可能会闪一下，语音助手会暂停一会儿，请不要断电`；demo 的工作日鬧鐘加上 `rule`；
  - `tests/gateway_kiosk_keys.json` 加上閘道以 `label()` 巢狀傳來的廠商名稱（`通义千问`、`豆包`、`智谱 GLM`、`自定义`）：閘道要頁面翻譯它們；
  - 喚醒詞規則改為 `wake_ok()`：英文值裏的喚醒詞（`小麦小麦`、`小麦同学`、`小麦`）必須跟鍵完全一樣，去掉喚醒詞後不能有其他中文，另加反例測試；
  - 英文的完整性測試在 Task 4 先以 `xfail(strict=True)` 加入，Task 5 加入 `en.js` 時拿掉標記；
  - 分成兩個 commit：鬧鐘的 Python 改動（`4d4ccca`）和頁面、繁中字典（`c09da02`）；繁中字典裏「网关」照 #4 譯作「閘道器」。
- **Task 5：** `闹钟` 譯為 `Alarm`，`错过了 {time} 的{kind}` 譯為 `Missed: {kind} at {time}`（不用表格裏的小寫 `alarm`，因為同一個鍵也是鬧鐘種類的標籤）；`tests/test_i18n_page.cjs` 相應改為 `Missed: Alarm at 07:00`。
- **Task 6：** `?demo=1` 會無限遞迴（沒有叫 `1` 的場景），所以改用 `?demo=<場景>&still`，檢查了 8 個場景（idle 加設定頁、settings、ring、listening、thinking、chat、models、volume）和 `/v1`。英文頁面上的中文只有含「小麦」的句子和「简体中文」「繁體中文」；繁中頁面沒有简中專用字；沒有腳本錯誤。
- **merge 之後：** `/v1` 的語言選單也經外殼的 `set_language` 寫入語言檔（`languageBridge()`，加了測試），README 相應修改（`2f1df0e`）。
- **已知限制：** 外殼還不附 `?lang` 的裝置，由已記住的值或瀏覽器語言決定；kiosk 計劃加入 `?lang` 之後才以外殼的語言檔為準。

## 不在這份計劃裏

- kiosk 外殼的 `set_language`、狀態檔、首次開機的語言選擇、歡迎頁的翻譯和 `keyboard.js`（主 repo 的 kiosk 計劃，spec §6.2）。
- 更新器的訊息鍵和 `job.reboot`，以及更新器的鍵在客戶端字典的條目（主 repo 的更新器計劃，spec §6.1；見「跨計劃的約定」第 2 點）。
- 發佈 `c1.0.0-s<系統層>` 的線上更新 Release（`make-release.py`，spec §5.6 第 3 步）。
- 向上游 #4 回報 `make_client()` 的遺漏：這是對外溝通，由維護者決定。
- 鬧鐘的語音、`describe_*()` 給大模型的中文說明、`mcp.py` 的工具說明：不是介面文字。
- 喚醒詞只有中文（spec §10）。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
