# 網關：#9、英文介面和我們的網址 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ohimsmart/oh-im-smart-gateway` 的 `main` 帶有上游 PR #9 的改動、指向 ohimsmart 的網址，以及完整的英文管理後台。

**Architecture:** 先把 #9 以 merge commit 併入 `main`。網址改動集中在安裝腳本、文件和兩個寫死的連結。英文沿用 #9 的「原文作鍵、每種語言一份字典」：`runtime.js` 多認 `en`，新增 `en.js`；後端填了數值的句子改為回傳 `{msg_key, msg_params}`，頁面用同一個函式翻譯普通字串和這種物件。字典完整性、英文顯示和「後端沒有漏網的中文 f-string」都由測試強制。

**Tech Stack:** Python 3.10（aiohttp、pytest、pytest-asyncio）、瀏覽器 JavaScript（無建置步驟）、Node 18 以上（只用於測試，以 `vm` 執行 `runtime.js` 和字典）、bash。

**Global Constraints:**
- 對應 spec：`docs/specs/2026-11-09-oh-im-smart-v1-design.md` §4、§5.3 第 4 點、§6.1、§6.3、§6.4、§9。
- 工作目錄是 `~/src/oh-im-smart-gateway`（`origin` = `https://github.com/ohimsmart/oh-im-smart-gateway.git`，`upstream` = justhalfbit，`fork` = chris-yyau）。這份計劃本身放在主 repo。
- `main` 只用 merge：不 rebase、不 force-push（GitHub 分支保護已設定，包括 admin）。功能分支 merge 回 `main` 一律 `git merge --no-ff`。
- 裝置上的安裝目錄名稱維持 `~/xiaozhi-hub-server`：只改網址，不改目錄名稱（主 repo 的映像打包、`ts.sh` 和裝置都依賴它）。
- 不加新的執行期依賴。Node 只是開發和測試用。
- 回傳給頁面的 `message`、`error`、`note` 欄位**保留**（舊頁面和第三方用戶仍讀它們），新欄位 `msg_key`、`msg_params` 是額外的。
- 不翻譯 `scripts/update.sh` 的輸出：頁面照原樣顯示在已有的「更新输出」標題下（spec §6.1、§10）。
- 用戶輸入、模型名稱、提示詞原文和對話內容不翻譯。所以 `msg_params` 裏的**普通字串一律原樣顯示**（喚醒後說的「接着上次聊」這類關鍵詞也是字典的鍵，翻成英文後設備就認不出來）；要翻譯的參數（我們自己的詞語、`catalog.py` 的標籤）以 `label(x)` 包成 `{msg_key: x}` 物件傳入。
- 「中文」在所有測試裏是同一個字元集：CJK 表意文字 U+4E00–U+9FFF，加上 CJK 標點 U+3000–U+303F 和全形字元 U+FF00–U+FFEF（`（）`、`：`、`；` 只有這些時也算），定義在 `tests/admin/i18n_node.py` 的 `CHINESE`，各測試共用。
- 後台顯示的每一個由後端送來、屬於我們的句子或標籤，頁面都經 `UII18n.text()`；由 Task 6 的頁面守門測試強制，不靠 Task 9 的人工檢查。
- 字典鍵就是介面上的原文。#9 的新介面有一部分以繁中寫成，所以 `zh-Hant.js` 有兩份字典：`UI_ZH_HANT`（简中原文 → 繁中）和 `UI_ZH_HANS`（繁中原文 → 简中）。英文字典要涵蓋兩者的所有鍵。
- 測試指令（在 `main/xiaozhi-server` 裏）：`.venv/bin/python -m pytest -q -p no:cacheprovider`。

---

## 背景：基準

在 #9 的分支上（`fork/feat/speech-api-mcp-admin`，6 個 commit，跟上游 `main` 沒有分岔），照下面 Task 1 的方式建立環境後，測試結果是 **707 passed, 5 failed, 5 skipped**。5 項失敗都來自環境，不是程式碼：

- `tests/test_stt.py` 的 4 項需要本地語音辨識模型（`models/sherpa-onnx-x-asr-…`，由 `install.sh` 下載，約數百 MB）；
- `tests/admin/test_admin.py::test_missing_packages_real_providers` 檢查真實 provider 的套件。

這 5 項在每個 task 之後都只能是同樣的 5 項，不能多。

## File Structure

| 檔案 | 責任 |
|---|---|
| `NOTICE` | 新檔：出處（spec §4） |
| `README.md`、`README.en.md` | 開頭加出處一行；安裝和 clone 指令改指我們的 repo |
| `hub-docs/guide.md` | 安裝和 clone 指令改指我們的 repo |
| `scripts/bootstrap.sh` | 預設 repo、用法說明；「是不是本專案」的判斷多認 `oh-im-smart-gateway` |
| `main/xiaozhi-server/tests/scripts/test_bootstrap.py` | 新檔：bootstrap 的判斷 |
| `main/xiaozhi-server/core/admin/pipeline.py` | `DESIGN_DOC_URL`；所有填了數值的欄位改為 `msg()` 物件 |
| `main/xiaozhi-server/core/admin/i18n_msg.py` | 新檔：`msg()`、`render()`、`UIError` |
| `main/xiaozhi-server/core/admin/admin_handler.py` | 靜態檔允許清單加 `en.js`；`_error()` 帶 key；填了數值的錯誤改用 `msg()` |
| `main/xiaozhi-server/core/admin/{speech_settings,mcp_settings,pages,plugin_settings,status,updater,grokbot,config_store,speech_probe}.py` | 驗證錯誤和填了數值的訊息改用 `UIError`／`msg()`；顯示用欄位多帶 `<欄位>_msg` |
| `main/xiaozhi-server/core/providers/asr/doubao_stream.py` | 只改 `check_connection()`：後台的「測試連線」顯示它的錯誤 |
| `main/xiaozhi-server/plugins_func/functions/{web_search,get_weather}.py` | `SearchError`／`WeatherError` 改為帶 key（後台的插件「測試」顯示它們）；設備朗讀的播報不改 |
| `main/xiaozhi-server/core/admin/static/i18n/runtime.js` | 認得 `en`；`normalize()`；三選一字典；`msg()`、`text()` |
| `main/xiaozhi-server/core/admin/static/i18n/en.js` | 新檔：英文字典 |
| `main/xiaozhi-server/core/admin/static/i18n/zh-Hant.js` | 補上新的鍵 |
| `main/xiaozhi-server/core/admin/static/index.html` | 載入 `en.js`；語言選單加 English；GitHub 連結；`api()` 和流程頁用 `UII18n.text()` |
| `main/xiaozhi-server/tests/admin/i18n_node.py` | 新檔：測試輔助，以 Node 載入字典和 `runtime.js` |
| `main/xiaozhi-server/tests/admin/test_i18n_runtime.py` | 新檔：語言判斷、`msg()`、`text()` |
| `main/xiaozhi-server/tests/admin/test_i18n_catalog.py` | 新檔：字典完整性、喚醒詞規則 |
| `main/xiaozhi-server/tests/admin/test_i18n_backend.py` | 新檔：後端沒有漏網的中文 f-string；英文顯示 |
| `main/xiaozhi-server/tests/admin/i18n-fstring-allow.txt` | 新檔：刻意保留的中文 f-string（送給模型或設備、不顯示在後台的） |
| `main/xiaozhi-server/tests/admin/test_i18n_page.py` | 新檔：頁面守門測試（後端送來的顯示欄位都經 `UII18n.text()`） |
| `main/xiaozhi-server/tests/admin/i18n-page-allow.txt` | 新檔：頁面上刻意原樣顯示的欄位（設備名稱、SSID、模型名稱等用戶值） |
| `~/src/gw-baseline-failures.txt` | 不進 repo：基準的 5 個失敗測試 ID，Task 9 推送前比對 |

---

### Task 1: 把 #9 併入 `main`，建立測試環境

**Files:** 無檔案改動（merge commit）。

- [ ] **Merge #9**

```bash
cd ~/src/oh-im-smart-gateway
git fetch --multiple upstream fork
git checkout -q main
git merge-base --is-ancestor upstream/main fork/feat/speech-api-mcp-admin && echo ancestor-ok   # 沒印出就停下
git merge --no-ff -m "Merge upstream PR #9: Traditional Chinese admin, speech APIs, language selection and MCP" fork/feat/speech-api-mcp-admin
```

#9 是在上游目前的 `main` 之上，不會有衝突。若 `git fetch` 後上游已前進而產生衝突，停下回報，不要自行解決。

- [ ] **建立測試環境**

```bash
cd ~/src/oh-im-smart-gateway/main/xiaozhi-server
uv venv -q --python 3.10 .venv
python3 ../../scripts/install_deps.py --python .venv/bin/python
uv pip install -q --python .venv/bin/python pytest pytest-asyncio freezegun
mkdir -p data && cp ../../scripts/config.template.yaml data/.config.yaml
node --version   # 必須是 v18 以上
.venv/bin/python -m pytest -q -p no:cacheprovider
```

Expected：`707 passed, 5 failed, 5 skipped`，失敗的正是「背景」列出的 5 項。`.venv` 和 `data/` 都已在 `.gitignore`。把這 5 個 ID 記下來，Task 9 推送前用它比對：

```bash
.venv/bin/python -m pytest -q -rf -p no:cacheprovider | grep '^FAILED' | sed 's/ - .*//' | sort > ~/src/gw-baseline-failures.txt
wc -l < ~/src/gw-baseline-failures.txt   # 5
```

不要裝 `hypothesis`：它跟 `freezegun` 的裝飾器衝突，`tests/core/utils/test_current_time.py` 會在收集時出錯。

- [ ] **推送**

```bash
git push origin main
```

Expected：成功（fast-forward）。這一步不經 litmus：merge commit 沒有新的程式碼，內容就是已公開的 #9。

---

### Task 2: 網址、出處和 bootstrap

**Files:**
- Create: `NOTICE`、`main/xiaozhi-server/tests/scripts/__init__.py`、`main/xiaozhi-server/tests/scripts/test_bootstrap.py`
- Modify: `scripts/bootstrap.sh:3,8,16,36`、`README.md:93,101-102`、`README.en.md:73,81-82`、`hub-docs/guide.md:35,41-42,58-59,318`、`main/xiaozhi-server/core/admin/pipeline.py:78`、`main/xiaozhi-server/core/admin/static/index.html:329`

先開分支：`git checkout -b feat/en-and-urls main`。

- [ ] **bootstrap.sh**

第 3 行：

```bash
# 用法：curl -fsSL https://raw.githubusercontent.com/ohimsmart/oh-im-smart-gateway/main/scripts/bootstrap.sh | bash
```

第 8 行：

```bash
#   XIAOZHI_HUB_REPO    仓库地址，默认 https://github.com/ohimsmart/oh-im-smart-gateway.git
```

第 16 行：

```bash
  local repo="${XIAOZHI_HUB_REPO:-https://github.com/ohimsmart/oh-im-smart-gateway.git}"
```

第 34–36 行的判斷改為同時接受兩個名稱（上游安裝的裝置經 `update.sh` 升級時，origin 可能還是舊名稱）。不用 extglob，因為 macOS 的 bash 3.2 要另外開啟：

```bash
  if [[ -e "$dir" ]]; then
    local origin=""
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 && origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin" == *xiaozhi-hub-server* || "$origin" == *oh-im-smart-gateway* ]]; then
```

後面的內容（`update.sh` 那一段和 `fi`）不變。

- [ ] **README、guide.md 的指令**

`README.md` 第 93 行和 `README.en.md` 第 73 行、`hub-docs/guide.md` 第 35 行：

```bash
curl -fsSL https://raw.githubusercontent.com/ohimsmart/oh-im-smart-gateway/main/scripts/bootstrap.sh | bash
```

`hub-docs/guide.md` 第 318 行同樣換網址，保留 `HF_ENDPOINT=https://hf-mirror.com`。

clone 的兩行（`README.md` 101–102、`README.en.md` 81–82、`guide.md` 41–42 和 58–59）改為明確指定目錄，否則會 clone 到 `oh-im-smart-gateway`，下一行的 `cd` 就失敗：

```bash
git clone --depth 1 https://github.com/ohimsmart/oh-im-smart-gateway.git xiaozhi-hub-server
cd xiaozhi-hub-server
```

徽章（`README*.md` 第 10、13、14 行）和天氣外掛的 User-Agent（`plugins_func/functions/get_weather.py:28`）不改：它們是出處標示。主 repo 的 `image/upstream-provenance.txt` 目前只有 `file` 條目（`LICENSE*`、`NOTICE*`），**還沒有**這些行的 `line` 條目，`check-rootfs.sh` 會擋下它們。這是交給主 repo 映像計劃 Task 8 的工作（那一步按擷取結果修改 `upstream-provenance.txt`）：Task 9 最後一步把這幾行的確切內容記進 work state。

在 `README.md` 第一個 `</p>`（徽章區塊結束）之後**空一行**再加這一行（HTML 區塊後面沒有空行時，Markdown 不會把下一行當成引用和連結）。上游網址只寫在 NOTICE（已由 `file` 條目允許），README 這一行不放上游網址，以免多一條要允許的行：

```markdown
> Oh I'm Smart 网关：基于 xiaozhi-hub-server（MIT），加上繁体中文、英文界面和 ThinkSmart View 的设定。出处见 [NOTICE](NOTICE)。
```

`README.en.md` 同一位置：

```markdown
> Oh I'm Smart gateway: based on xiaozhi-hub-server (MIT), with Traditional Chinese and English interfaces and ThinkSmart View settings. See [NOTICE](NOTICE).
```

- [ ] **NOTICE**

```text
Oh I'm Smart gateway (https://github.com/ohimsmart/oh-im-smart-gateway)

This repository starts from the history of xiaozhi-hub-server by 半格 / HalfBit
(https://github.com/justhalfbit/xiaozhi-hub-server), which in turn builds on
xiaozhi-esp32-server by xinnan-tech. Both are released under the MIT License;
the copyright notices are kept in LICENSE.

Changes in this repository are released under the same MIT License.
```

- [ ] **兩個寫死的連結**

`pipeline.py` 第 78 行：

```python
DESIGN_DOC_URL = "https://github.com/ohimsmart/oh-im-smart-gateway/blob/main/hub-docs/design.md"
```

`index.html` 第 329 行的 `href` 改為 `https://github.com/ohimsmart/oh-im-smart-gateway`，`title` 改為 `网关开源仓库`（這個新鍵在 Task 6 加入字典）。

- [ ] **bootstrap 測試**

`main/xiaozhi-server/tests/scripts/__init__.py` 是空檔。`test_bootstrap.py`：

```python
"""bootstrap.sh 判斷「已經裝過」的條件：新舊兩個 origin 名稱都走 update.sh，其他 repo 不碰。"""
import subprocess
from pathlib import Path

import pytest

BOOTSTRAP = Path(__file__).resolve().parents[4] / "scripts" / "bootstrap.sh"


def _checkout(tmp_path: Path, origin: str) -> Path:
    d = tmp_path / "hub"
    (d / "scripts").mkdir(parents=True)
    (d / "scripts" / "update.sh").write_text(f'#!/bin/bash\ntouch "{tmp_path}/updated"\n')
    subprocess.run(["git", "init", "-q", str(d)], check=True)
    subprocess.run(["git", "-C", str(d), "remote", "add", "origin", origin], check=True)
    return d


def _run(tmp_path: Path, d: Path):
    # start_new_session：沒有控制終端，run_with_tty 直接執行，不讀 /dev/tty
    return subprocess.run(["bash", str(BOOTSTRAP)], env={"PATH": "/usr/bin:/bin", "HOME": str(tmp_path),
                          "XIAOZHI_HUB_DIR": str(d)}, stdin=subprocess.DEVNULL, capture_output=True,
                          text=True, start_new_session=True, timeout=60)


@pytest.mark.parametrize("origin", ["https://github.com/ohimsmart/oh-im-smart-gateway.git",
                                    "https://github.com/justhalfbit/xiaozhi-hub-server.git"])
def test_existing_checkout_is_updated(tmp_path, origin):
    r = _run(tmp_path, _checkout(tmp_path, origin))
    assert r.returncode == 0, r.stderr
    assert (tmp_path / "updated").exists()


def test_other_repository_is_left_alone(tmp_path):
    r = _run(tmp_path, _checkout(tmp_path, "https://github.com/someone/else.git"))
    assert r.returncode != 0
    assert "不是本项目" in r.stderr
    assert not (tmp_path / "updated").exists()
```

先在 Task 1 的 `main` 上跑一次這個測試（把檔案暫時放進去）：新網址那一項必須失敗，證明測試抓得到舊判斷。然後回到這個分支。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/scripts tests/admin`
Expected：全部通過，`tests/admin/test_admin.py::test_missing_packages_real_providers` 除外（基準的環境失敗）。

```bash
git add NOTICE README.md README.en.md hub-docs/guide.md scripts/bootstrap.sh \
  main/xiaozhi-server/core/admin/pipeline.py main/xiaozhi-server/core/admin/static/index.html \
  main/xiaozhi-server/tests/scripts
git commit -m "Point install commands and links at ohimsmart/oh-im-smart-gateway; add NOTICE"
```

---

### Task 3: `runtime.js` 認得英文

**Files:**
- Create: `main/xiaozhi-server/core/admin/static/i18n/en.js`（先建空殼）、`main/xiaozhi-server/tests/admin/i18n_node.py`、`main/xiaozhi-server/tests/admin/test_i18n_runtime.py`
- Modify: `runtime.js`、`admin_handler.py:216`、`index.html:288,335`

**Interfaces:**
- Produces（JavaScript）：`UII18n.t(text) -> string`、`UII18n.msg(obj) -> string | null`（`obj` 有 `msg_key` 時翻譯並填參數，否則 `null`）、`UII18n.text(value) -> string`（字串走 `t()`，`{msg_key}` 物件走 `msg()`，其他轉成字串）、`UII18n.locale`、`UII18n.normalize(tag)`。
- Produces（Python 測試輔助）：`i18n_node.catalogs() -> dict[str, dict]`（鍵為 `UI_ZH_HANT`、`UI_ZH_HANS`、`UI_EN`）、`i18n_node.render(values: list, locale: str) -> list[str]`。

- [ ] **en.js 空殼**

```javascript
// Application copy only; preserve conversation content and user-entered values.
// Keys are the interface's original text (Simplified Chinese, or Traditional where #9 wrote it so).
window.UI_EN = {
};
```

- [ ] **runtime.js**

整個檔案改為：

```javascript
/* Translate application-owned copy only. Conversation text, SSIDs and user input are never converted. */
window.UII18n = (() => {
  const key = 'thinksmart.uiLocale';
  const LOCALES = ['zh-Hans', 'zh-Hant', 'en'];
  // zh-* with Hant/TW/HK/MO → Traditional; other zh → Simplified; everything else (including en-HK) → English
  const normalize = value => !/^zh(?:-|$)/i.test(value || '') ? 'en'
    : /^zh-(?:Hant|TW|HK|MO)(?:-|$)/i.test(value) ? 'zh-Hant' : 'zh-Hans';
  let saved;
  try { saved = localStorage.getItem(key); } catch (_) { /* Private browsing may disable storage. */ }
  const requested = new URLSearchParams(location.search).get('lang');
  // The admin page has no kiosk: remembered value, then ?lang, then the browser (spec §6.2, last paragraph)
  const locale = LOCALES.includes(saved) ? saved
    : LOCALES.includes(requested) ? requested : normalize(navigator.language);
  if (!LOCALES.includes(saved) && requested === locale) {
    try { localStorage.setItem(key, locale); } catch (_) { /* The URL still supplies this visit's locale. */ }
  }
  const catalog = ({ 'zh-Hant': window.UI_ZH_HANT, 'zh-Hans': window.UI_ZH_HANS, en: window.UI_EN })[locale] || {};
  const t = text => Object.prototype.hasOwnProperty.call(catalog, text) ? catalog[text] : text;
  // {msg_key, msg_params}: translate the template, then fill it. Only object parameters are translated;
  // plain strings are names, keywords or third-party text and are shown exactly as given.
  const param = value => (value && typeof value === 'object' ? text(value) : value === null || value === undefined ? '' : String(value));
  const msg = obj => {
    if (!obj || typeof obj !== 'object' || typeof obj.msg_key !== 'string') return null;
    const params = obj.msg_params || {};
    return t(obj.msg_key).replace(/\{(\w+)\}/g, (whole, name) =>
      Object.prototype.hasOwnProperty.call(params, name) ? param(params[name]) : whole);
  };
  const text = value => {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return t(value);
    const m = msg(value);
    return m === null ? String(value) : m;
  };
  function init() {
    document.documentElement.lang = locale;
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
      select.value = locale;
      select.addEventListener('change', () => {
        try { localStorage.setItem(key, select.value); } catch (_) { return; }
        location.reload();
      });
    });
  }
  return { t, msg, text, init, locale, normalize };
})();
```

參數值是普通字串時**不**經 `t()`（Global Constraints）：要翻譯的參數由後端包成 `{msg_key}` 物件（Task 4 的 `label()`）。頂層的普通字串（例如 `stage.title` 這種沒有參數的欄位）仍經 `t()`。

- [ ] **靜態檔允許清單和頁面**

`admin_handler.py` 第 216 行：

```python
        if asset not in ('runtime.js', 'zh-Hant.js', 'en.js'):
```

`index.html` 第 335 行之後（`runtime.js` 之前）加：

```html
<script src="/admin/i18n/en.js"></script>
```

第 288 行的選單加上英文選項，並標上 `data-no-i18n`，否則語言名稱本身會被翻譯：

```html
  <select data-language-picker data-no-i18n aria-label="界面语言"><option value="zh-Hans">简体中文</option><option value="zh-Hant">繁體中文</option><option value="en">English</option></select>
```

`aria-label` 仍會被翻譯（`data-no-i18n` 只擋文字節點）。

- [ ] **Node 測試輔助**

`tests/admin/i18n_node.py`：

```python
"""以 Node 執行後台的 runtime.js 和字典（後台沒有建置步驟，字典是 JavaScript，不是 JSON）。"""
import json
import shutil
import subprocess
from pathlib import Path

I18N = Path(__file__).resolve().parents[2] / "core" / "admin" / "static" / "i18n"
FILES = ["zh-Hant.js", "en.js"]
# 測試裏的「中文」：表意文字、CJK 標點、全形字元（Global Constraints）
CHINESE = "　-〿一-鿿＀-￯"


def has_chinese(s: str) -> bool:
    return any("　" <= ch <= "〿" or "一" <= ch <= "鿿" or "＀" <= ch <= "￯" for ch in s)


_SCRIPT = r"""
const vm = require('vm'), fs = require('fs');
const [dir, mode, locale] = process.argv.slice(1);
const store = {};
// vm contexts have no host globals: runtime.js needs URLSearchParams
const sandbox = { window: {}, URLSearchParams, localStorage: { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = v; } },
  location: { search: '' }, navigator: { language: locale || 'zh-CN' } };
vm.createContext(sandbox);
for (const f of %s) vm.runInContext(fs.readFileSync(dir + '/' + f, 'utf8'), sandbox, { filename: f });
if (mode === 'catalogs') {
  process.stdout.write(JSON.stringify({ UI_ZH_HANT: sandbox.window.UI_ZH_HANT, UI_ZH_HANS: sandbox.window.UI_ZH_HANS,
    UI_EN: sandbox.window.UI_EN }));
} else {
  sandbox.window.localStorage = sandbox.localStorage;
  vm.runInContext('localStorage.setItem("thinksmart.uiLocale", ' + JSON.stringify(locale) + ');', sandbox);
  vm.runInContext(fs.readFileSync(dir + '/runtime.js', 'utf8'), sandbox, { filename: 'runtime.js' });
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  process.stdout.write(JSON.stringify({ locale: sandbox.window.UII18n.locale,
    out: input.map(v => sandbox.window.UII18n.text(v)) }));
}
""" % json.dumps(FILES)


def _node(*args, stdin=""):
    node = shutil.which("node")
    assert node, "這組測試需要 Node 18 以上（後台的翻譯是 JavaScript）"
    r = subprocess.run([node, "-e", _SCRIPT, str(I18N), *args], input=stdin, capture_output=True,
                       text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def catalogs() -> dict:
    return _node("catalogs")


def render(values: list, locale: str) -> list:
    """用 UII18n.text() 翻譯每個值；locale 經已記住的值選定。"""
    result = _node("render", locale, stdin=json.dumps(values, ensure_ascii=False))
    assert result["locale"] == locale
    return result["out"]
```

`runtime.js` 在 `vm` 裏讀的是全域的 `localStorage`、`location`、`navigator`，所以 sandbox 直接提供這三個；`window` 只用來放字典和 `UII18n`。

- [ ] **語言判斷和 `msg()` 的測試**

`tests/admin/test_i18n_runtime.py`：

```python
"""runtime.js：語言判斷、三選一字典、{msg_key, msg_params} 的翻譯。"""
import json
import shutil
import subprocess

import pytest

from tests.admin.i18n_node import I18N

_DETECT = r"""
const vm = require('vm'), fs = require('fs');
const [dir, saved, search, language] = process.argv.slice(1);
const store = saved ? { 'thinksmart.uiLocale': saved } : {};
const sb = { window: {}, URLSearchParams, localStorage: { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = v; } },
  location: { search }, navigator: { language } };
vm.createContext(sb);
vm.runInContext(fs.readFileSync(dir + '/runtime.js', 'utf8'), sb);
process.stdout.write(JSON.stringify({ locale: sb.window.UII18n.locale, stored: store['thinksmart.uiLocale'] ?? null }));
"""


def detect(saved="", search="", language="zh-CN"):
    r = subprocess.run([shutil.which("node"), "-e", _DETECT, str(I18N), saved, search, language],
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


@pytest.mark.parametrize("language,expected", [
    ("en-US", "en"), ("en-HK", "en"), ("fr", "en"), ("", "en"),
    ("zh-CN", "zh-Hans"), ("zh", "zh-Hans"), ("zh-Hans-HK", "zh-Hans"),
    ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-MO", "zh-Hant"), ("zh-Hant-TW", "zh-Hant")])
def test_browser_language(language, expected):
    assert detect(language=language)["locale"] == expected


def test_remembered_value_and_lang_parameter():
    assert detect(saved="en", language="zh-CN")["locale"] == "en"
    assert detect(saved="en", search="?lang=zh-Hant")["locale"] == "en"     # remembered wins on the admin page
    r = detect(search="?lang=en", language="zh-CN")
    assert r == {"locale": "en", "stored": "en"}
    assert detect(saved="xx", search="?lang=xx", language="zh-TW")["locale"] == "zh-Hant"   # invalid values are ignored


def test_msg_translates_nested_parameters(tmp_path, monkeypatch):
    from tests.admin import i18n_node
    for f in ("zh-Hant.js", "en.js", "runtime.js"):
        (tmp_path / f).write_text((I18N / f).read_text(encoding="utf-8"), encoding="utf-8")
    (tmp_path / "en.js").write_text('window.UI_EN = {"已更新到 {version}": "Updated to {version}", '
                                    '"{why}，已退回": "{why}; rolled back", "默认": "default", '
                                    '"说{said}接上": "Say {said} to resume", "接着上次聊": "pick up where we left off"};',
                                    encoding="utf-8")
    monkeypatch.setattr(i18n_node, "I18N", tmp_path)
    out = i18n_node.render([
        {"msg_key": "已更新到 {version}", "msg_params": {"version": "1.0.1"}},
        {"msg_key": "{why}，已退回", "msg_params": {"why": {"msg_key": "已更新到 {version}", "msg_params": {"version": "2"}}}},
        "默认", "不在字典里", None, 3, {"msg_key": "缺参数 {x}"},
        # a keyword the device listens for stays as typed, even though it is also a dictionary key
        {"msg_key": "说{said}接上", "msg_params": {"said": "接着上次聊"}},
        # an app-owned label is passed as an object and is translated
        {"msg_key": "说{said}接上", "msg_params": {"said": {"msg_key": "接着上次聊"}}}], "en")
    assert out == ["Updated to 1.0.1", "Updated to 2; rolled back", "default", "不在字典里", "", "3", "缺参数 {x}",
                   "Say 接着上次聊 to resume", "Say pick up where we left off to resume"]


def test_render_runs_cleanly():
    from tests.admin import i18n_node
    assert i18n_node.render(["保存"], "zh-Hans") == ["保存"]
```

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin/test_i18n_runtime.py tests/admin/test_speech_mcp_settings.py`
Expected：全部通過（`test_speech_mcp_settings.py` 裏 `runtime.js` 200、`unknown.js` 404 那一項仍然通過）。

```bash
git add main/xiaozhi-server/core/admin/static/i18n/runtime.js main/xiaozhi-server/core/admin/static/i18n/en.js \
  main/xiaozhi-server/core/admin/admin_handler.py main/xiaozhi-server/core/admin/static/index.html \
  main/xiaozhi-server/tests/admin/i18n_node.py main/xiaozhi-server/tests/admin/test_i18n_runtime.py
git commit -m "Admin i18n: English locale, normalize() for en, msg()/text() for keyed messages"
```

---

### Task 4: 後端訊息帶 key：基礎、錯誤回應和驗證錯誤

**Files:**
- Create: `main/xiaozhi-server/core/admin/i18n_msg.py`、`main/xiaozhi-server/tests/admin/test_i18n_backend.py`（第一部分）
- Modify: `admin_handler.py`（`_error()` 和所有 `self._error(str(e), …)`）、`speech_settings.py`、`mcp_settings.py`、`index.html`（`api()`）、`zh-Hant.js`

**Interfaces:**
- Consumes: Task 3 的 `UII18n.msg()`、`UII18n.text()`。
- Produces: `msg(key: str, **params) -> dict`、`render(value) -> str`、`class UIError(ValueError)`（屬性 `key`、`params`；`str(e)` 是填好參數的简中句子）、`UIError.payload() -> dict`。

- [ ] **i18n_msg.py**

```python
"""後台訊息的 key：msg_key 是帶 {佔位符} 的简中原文，頁面用它查字典再填參數（spec §6.1）。

參數值是普通字串時，頁面一字不改地顯示（名稱、設備認的口令、第三方錯誤原文）；
我們自己的詞語或 catalog 標籤要翻譯時，用 label() 或 msg() 包成物件傳入（句中嵌句也是這樣）。
"""
import re

_FIELD = re.compile(r"\{(\w+)\}")


def msg(key: str, **params) -> dict:
    return {"msg_key": key, "msg_params": params}


def label(text) -> dict:
    """我們自己的詞語或 catalog 標籤作參數時用：頁面會翻譯它。普通字串參數原樣顯示。"""
    return {"msg_key": str(text), "msg_params": {}}


def render(value) -> str:
    """填好參數的简中句子，給舊欄位（message、error、note）和日誌用。"""
    if isinstance(value, dict) and isinstance(value.get("msg_key"), str):
        params = value.get("msg_params") or {}
        return _FIELD.sub(lambda m: render(params[m.group(1)]) if m.group(1) in params else m.group(0),
                          value["msg_key"])
    return "" if value is None else str(value)


class KeyedError(Exception):
    """帶 key 的例外；str(e) 是填好參數的简中句子。"""

    def __init__(self, key: str, **params):
        self.key, self.params = key, params
        super().__init__(render(msg(key, **params)))

    def payload(self) -> dict:
        return msg(self.key, **self.params)


class UIError(KeyedError, ValueError):
    """顯示給後台用戶的驗證錯誤。是 ValueError 的子類，現有的 except ValueError 照樣接得到。"""
```

`label()` 的參數不是字面值（它包的是 catalog 的值），所以 Task 6 的「鍵必須是字面值」測試只檢查 `msg()` 和 `UIError()`；`label()` 包的值由 Task 7 的原文來源第 6 項（現有字典的鍵）和第 5 項（執行期的值）涵蓋。

- [ ] **錯誤回應帶 key**

`admin_handler.py` 的 `_error()`：

```python
    def _error(self, message, status):
        """message 可以是字串、msg() 物件或例外；KeyedError 和 msg() 物件會多帶 msg_key、msg_params。"""
        if isinstance(message, KeyedError):
            return self._json({"ok": False, "error": str(message), **message.payload()}, status)
        if isinstance(message, dict):
            return self._json({"ok": False, "error": render(message), **message}, status)
        return self._json({"ok": False, "error": str(message)}, status)
```

檔案開頭加 `from core.admin.i18n_msg import KeyedError, UIError, label, msg, render`。把所有 `self._error(str(e), N)` 和 `self._error(str(exc), N)` 換成傳例外本身：

```bash
cd ~/src/oh-im-smart-gateway/main/xiaozhi-server
grep -c -E 'self\._error\(str\((e|exc)\), [0-9]+\)' core/admin/admin_handler.py   # 記下這個數（#9 的 HEAD 上是 18）
sed -i -E 's/self\._error\(str\((e|exc)\), ([0-9]+)\)/self._error(\1, \2)/' core/admin/admin_handler.py
grep -c -E 'self\._error\((e|exc), [0-9]+\)' core/admin/admin_handler.py         # 跟上面的數相同
grep -n 'self._error(str(' core/admin/admin_handler.py                           # 沒有輸出
```

`str(ValueError)` 跟原本一樣，所以不帶 key 的例外行為不變。第 530 行的 `updater.UpdateError`（409）在 Task 6 改為 `KeyedError` 的子類，之後就帶 key。

另外有幾處把錯誤字串放進結果字典再經 `self._error(result[...], N)` 回傳（第 638、670、939、964、1109、1184 行）。這些由 Task 6 處理。

- [ ] **頁面的 `api()`**

`index.html` 的 `api()` 最後兩行改為：

```javascript
  if (!res.ok || data.ok === false) {
    const keyed = UII18n.msg(data);   // 有 msg_key 時用它翻譯，否則用原有的 error 字串
    throw new Error(keyed !== null ? keyed : data.error ? UII18n.t(data.error) : UII18n.t("请求失败：") + res.status);
  }
  return data;
```

`toast()` 會再對訊息做一次 `t()`；已翻譯的句子不是字典的鍵，所以原樣傳回。

**離線判斷不能靠譯文的開頭。** #9 以 `message.startsWith(OFFLINE)` 判斷連不上服務（`index.html:466–468`，`OFFLINE = UII18n.t("连不上服务")`），`api()` 拋出的是另一句較長的話（第 356 行）；這只在每種語言的長句譯文都以短句譯文開頭時成立，而短句也單獨當標籤用。改為在錯誤上做記號，跟現有的 `e.expired` 同樣做法：

```javascript
  try { res = await fetch("/admin/api/" + path, opts); }
  catch (e) { const err = new Error(UII18n.t("连不上服务，请确认服务还在运行")); err.offline = true; throw err; }
```

```javascript
const isOffline = (e) => Boolean(e && e.offline);
```

第 472、546、1826 行的呼叫處不變（它們都經 `isOffline()`）。`OFFLINE` 常數只剩顯示用途。

- [ ] **speech_settings.py 的驗證錯誤**

#9 寫成繁中的錯誤改用简中範本作 key，繁中放進 `UI_ZH_HANT`（spec §6.1）。逐行對照（第 60–106 行）：

| 行 | 原本 | 改為 |
|---|---|---|
| 60 | `ValueError(f"{spec['entry']} 已存在，但不是 OpenAI 相容類型")` | `UIError("{entry} 已存在，但不是 OpenAI 兼容类型", entry=spec['entry'])` |
| 64 | `ValueError('請選擇 OpenAI 或 ZenMux 語音協定')` | `UIError("请选择 OpenAI 或 ZenMux 语音协议")` |
| 69 | `ValueError('Base URL 必須是完整的 HTTP(S) 網址，不可含帳密、查詢參數或空白')` | `UIError("Base URL 必须是完整的 HTTP(S) 网址，不能含账号密码、查询参数或空格")` |
| 72 | `ValueError('請填寫模型名稱（最多 200 字元）')` | `UIError("请填写模型名称（最多 200 个字符）")` |
| 75 | `ValueError('API Key 不可含空白或換行')` | `UIError("API Key 不能含空格或换行")` |
| 77 | `ValueError('請填寫 API Key')` | `UIError("请填写 API Key")` |
| 87 | `ValueError('辨識語言請使用 ISO 639 代碼，例如 zh 或 en；留空則自動偵測')` | `UIError("识别语言请使用 ISO 639 代码，例如 zh 或 en；留空则自动检测")` |
| 90 | `ValueError('轉寫提示最多 4000 字元')` | `UIError("转写提示最多 4000 个字符")` |
| 97 | `ValueError('語速必須介於 0.25 和 4 之間')` | `UIError("语速必须在 0.25 到 4 之间")` |
| 99 | `ValueError('請填寫音色，語速必須介於 0.25 和 4 之間')` | `UIError("请填写音色，语速必须在 0.25 到 4 之间")` |
| 103 | `ValueError('不支援的音訊格式')` | `UIError("不支持的音频格式")` |
| 106 | `ValueError('請選擇有效的 PCM 取樣率')` | `UIError("请选择有效的 PCM 采样率")` |

每一個新鍵在 `zh-Hant.js` 的 `UI_ZH_HANT` 裏加一條，值就是原本的繁中句子（`{entry}` 那一條的值是 `{entry} 已存在，但不是 OpenAI 相容類型`）。

- [ ] **mcp_settings.py 的驗證錯誤**

同樣的做法（第 19–83 行）：

| 行 | 改為 |
|---|---|
| 19 | `UIError("MCP 设置必须包含 mcpServers 对象")` |
| 21 | `UIError("每个 MCP 服务器设置都必须是 JSON 对象")` |
| 40 | `UIError("服务器设置必须是 JSON 对象")` |
| 44 | `UIError("包含不支持的 MCP 设置字段")` |
| 47 | `UIError("请设置 command 或 url，二选一")` |
| 50 | `UIError("command 必须是非空字符串")` |
| 52 | `UIError("args 必须是字符串数组")` |
| 56 | `UIError("url 必须是字符串")` |
| 59 | `UIError("请使用 HTTP(S) 网址；令牌请放在 headers，不要放在网址里")` |
| 61 | `UIError("传输类型必须是 sse 或 streamable-http")` |
| 67 | `UIError("{field} 必须是字符串映射表", field=field)` |
| 75 | `UIError("{field} 必须在 0 到 3600 秒之间", field=field)` |
| 77 | `UIError("terminate_on_close 必须是布尔值")` |
| 83 | `UIError("请填写服务器名称（最多 80 个字符）")` |

繁中值照搬原句，`UI_ZH_HANT` 各加一條。

- [ ] **後端測試（第一部分）**

`tests/admin/test_i18n_backend.py`：

```python
"""後端訊息：UIError 帶 key；錯誤回應帶 msg_key；英文介面顯示英文。"""
import json

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from core.admin import config_store, mcp_settings, speech_settings
from core.admin.admin_handler import COOKIE_NAME, AdminHandler
from core.admin.i18n_msg import UIError, msg, render


def test_render_fills_nested_parameters():
    assert render(msg("{why}，已退回 {old}", why=msg("缺少 {x}", x="a.onnx"), old="1.0")) == "缺少 a.onnx，已退回 1.0"
    assert render(msg("缺参数 {x}")) == "缺参数 {x}"
    e = UIError("{field} 必须是字符串映射表", field="env")
    assert isinstance(e, ValueError) and str(e) == "env 必须是字符串映射表"
    assert e.payload() == {"msg_key": "{field} 必须是字符串映射表", "msg_params": {"field": "env"}}


@pytest.mark.asyncio
async def test_validation_error_response_carries_the_key(tmp_path):
    path = tmp_path / ".config.yaml"; path.write_text("{}\n")
    config = config_store.load_merged(custom_path=path)
    h = AdminHandler(config, ws_server=object(), config_path=path, mcp_config_path=tmp_path / "mcp.json")
    app = web.Application(); h.register(app)
    async with TestClient(TestServer(app)) as c:
        cookie = {COOKIE_NAME: h.sessions.create()}
        r = await c.post("/admin/api/mcp", json={"name": "x", "config": {"url": "ftp://bad"}}, cookies=cookie)
        assert r.status == 400
        d = await r.json()
        assert d["msg_key"] == "请使用 HTTP(S) 网址；令牌请放在 headers，不要放在网址里"
        assert d["error"] == d["msg_key"]          # old pages still get a sentence
```

`AdminHandler` 的建構參數和 `/admin/api/mcp` 的請求格式以 `tests/admin/test_speech_mcp_settings.py` 第 200–230 行的寫法為準；寫這個測試前先讀那一段，按它調整參數名稱（例如 `mcp_config_path`）和請求內容，讓它真的走到 `mcp_settings` 的網址檢查。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin`
Expected：全部通過（基準的 `test_missing_packages_real_providers` 除外）。`test_speech_mcp_settings.py` 裏用 `pytest.raises(ValueError)` 的項目照樣通過，因為 `UIError` 是 `ValueError`。

```bash
git add main/xiaozhi-server/core/admin/i18n_msg.py main/xiaozhi-server/core/admin/admin_handler.py \
  main/xiaozhi-server/core/admin/speech_settings.py main/xiaozhi-server/core/admin/mcp_settings.py \
  main/xiaozhi-server/core/admin/static/index.html main/xiaozhi-server/core/admin/static/i18n/zh-Hant.js \
  main/xiaozhi-server/tests/admin/test_i18n_backend.py
git commit -m "Admin messages carry msg_key/msg_params; speech and MCP validation errors keyed in Simplified Chinese"
```

---

### Task 5: 工作原理頁（pipeline.py）

**Files:**
- Modify: `main/xiaozhi-server/core/admin/pipeline.py`、`index.html`（流程頁的渲染）
- Test: `tests/admin/test_admin_pipeline.py`（現有，更新預期值）

**Interfaces:**
- Consumes: Task 4 的 `msg()`、`render()`；Task 3 的 `UII18n.text()`。
- Produces: `describe()` 的回傳結構不變，但 `stages[].value/hint`、`tips[].say/result`、`segments[].when/note` 和 `warnings[]` 的值可以是 `{msg_key, msg_params}`。

規則：`pipeline.py` 裏每一個含中文的 f-string、`+`／`+=` 拼接和 `"…".join()`，凡是結果會顯示在後台的，都改為 `msg()`。

- **用戶的值**是普通字串參數，原樣顯示：`calls['reply']`、別名、`end_prompt['reply']`、`exit_commands`、`resume_keywords`（包括預設的「接着上次聊」：設備認的是這幾個中文字）、模板檔名、模型名稱；
- **我們的詞語和 catalog 標籤**用 `label()` 或 `msg()` 傳入，讓頁面翻譯：「默认模型」「默认」「未设置」、`_duration()` 的「小时／分钟／秒」、`catalog.EDGE_VOICES` 的 `name`／`group`、`catalog.CLAUDE_MODELS`／`CLAUDE_EFFORTS` 的 `label`、`catalog.VENDOR_BY_ENTRY` 的 `label`、`pages.SHERPA_MODEL_LABELS` 的值；
- `segments[].text` 是提示詞原文，不改。

- [ ] **小工具改為回傳 msg 物件**

```python
def _duration(seconds):
    try:
        seconds = float(seconds)
    except (TypeError, ValueError):
        return str(seconds)
    if seconds >= 60 and seconds % 60 == 0:
        minutes = int(seconds // 60)
        return msg("{n} 小时", n=minutes // 60) if minutes % 60 == 0 else msg("{n} 分钟", n=minutes)
    return msg("{n} 秒", n=int(seconds))


def _quoted(words):
    """“甲”“乙”：全是用户填的词，没有要翻译的字。"""
    return "".join(f"“{w}”" for w in words)


def _either(words):
    """接上次对话的关键词，最多两个：“甲”或“乙”。"""
    words = [str(w) for w in words[:2]]
    return msg("“{a}”或“{b}”", a=words[0], b=words[1]) if len(words) == 2 else _quoted(words)
```

唯一用分隔符的呼叫 `_quoted(keywords[:2], "或")`（第 197 行）改為 `_either(keywords)`。msg 的鍵一律是字面值，不在執行時拼出來，否則 Task 7 的原文擷取抓不到。

其餘小工具：

```python
def _voice_name(voice: str):
    info = next((v for v in catalog.EDGE_VOICES if v["value"] == voice), None)
    return msg("{name}（{group}）", name=label(info["name"]), group=label(info["group"])) if info else voice


def _llm_label(name: str, entry: dict):
    if entry.get("type") == "claude_cli":
        return "Claude Code"
    vendor = catalog.VENDOR_BY_ENTRY.get(name)
    return label(vendor["label"]) if vendor else name


def _asr_label(name: str, entry: dict):
    if entry.get("type") == "doubao_stream":
        return msg("豆包流式识别")
    if entry.get("type") == "sherpa_onnx_local":
        if "x-asr" in str(entry.get("model_dir") or "").lower():
            return msg("本地 X-ASR")
        model_type = entry.get("model_type") or "sense_voice"
        return msg("本地 {model}", model=label(pages.SHERPA_MODEL_LABELS.get(model_type, model_type)))
    return name or msg("未设置")


def _claude_model_label(model):
    option = next((o for o in catalog.CLAUDE_MODELS if o["value"] == model), None)
    return label(option["label"]) if option else (str(model) if model else msg("默认模型"))


def _effort_label(effort):
    option = next((o for o in catalog.CLAUDE_EFFORTS if o["value"] == effort), None)
    return label(option["label"]) if option else msg("默认")
```

`label()` 包住的值若不在字典裏（例如 `SHERPA_MODEL_LABELS` 沒有的 `model_type` 原樣傳回），`t()` 原樣顯示，不會出錯。這些函式在 `describe_prompt()` 裏也用到（`"llm": _llm_label(...)`），頁面以 `UII18n.text(p.llm)` 顯示（見下面「頁面的渲染」）。

- [ ] **describe_stages**

```python
    if llm.get("type") == "claude_cli":
        llm_value = msg("Claude Code · {model}", model=_claude_model_label(llm.get("model")))
        llm_hint = msg("思考力度：{effort}", effort=_effort_label(llm.get("effort")))
    else:
        llm_value = _llm_label(llm_name, llm)
        llm_hint = _raw(str(llm.get("model_name") or ""))
    if tts.get("type") == "edge":
        tts_value = msg("EdgeTTS · {voice}", voice=_voice_name(str(tts.get("voice") or "")))
        tts_hint = "微软在线语音，需要联网"
    else:
        tts_value, tts_hint = _raw(tts_name) if tts_name else msg("未设置"), _raw(str(tts.get("type") or ""))
    local_asr = asr.get("type") == "sherpa_onnx_local"
    return [
        {"id": "listen", "icon": "🎙", "title": "收音", "value": msg("停顿 {ms}ms 算说完", ms=silence),
         "hint": "说话中间停顿太久会被截成两句", "page": "asr"},
        {"id": "asr", "icon": "📝", "title": "识别", "value": _asr_label(asr_name, asr),
         "hint": "在本机识别，不联网" if local_asr else "云端识别，需要联网", "page": "asr"},
        {"id": "llm", "icon": "✦", "title": "大模型", "value": llm_value, "hint": llm_hint, "page": "llm"},
        {"id": "tts", "icon": "🔊", "title": "合成", "value": tts_value, "hint": tts_hint, "page": "tts"},
        {"id": "play", "icon": "📢", "title": "播放", "value": msg("缓冲约 {s} 秒", s=f"{prebuffer * 60 / 1000:.1f}"),
         "hint": "说话断续时，在配置文件里调大", "page": None},
    ]
```

（`f"{prebuffer * 60 / 1000:.1f}"` 是數字格式，沒有中文，守門測試不會擋。）

配置裏的名稱（條目名、`model_name`、`type`）是用戶的值，但頁面對整個欄位呼叫 `UII18n.text()`：普通字串會被當成字典的鍵，名叫「默认」的條目在繁中頁面會變成「預設」。所以用一個只有參數的範本包起來，原樣顯示：

```python
def _raw(value):
    """配置里的名称（条目名、model_name、type）：页面原样显示，不会碰巧被当成字典的键翻译。"""
    return msg("{value}", value=value)
```

`_llm_label`、`_asr_label` 退回條目名時，以及呼名清單裏沒有對應模型的標籤，也用 `_raw()`。

- [ ] **describe_tips、describe_prompt**

按同一規則逐句改寫。每一條 `result`、`say`、`when`、`note` 和 `warnings` 裏的句子都變成一個 `msg()`，條件分支各自是一個完整的範本，不拼接半句（英文詞序不同）。例如「長任務」：

```python
        if not turn:
            wait = msg("设备陪着等，不限时长")
        else:
            wait = msg("设备陪着等，最长 {d}", d=_duration(turn))
        nudge = msg("；{d}没开口就提示一次进度", d=_duration(progress)) if progress else ""
        # 停下、继续是设备认的口令（core/agent/voice_commands.py 只认中文），作为普通字符串参数原样显示
        if _setting(cli, "background_max_seconds", 7200):
            after = msg("。中途打断、结束或等满了，Claude 不停，后台接着做，做完了告诉你；想让它停下就说“{cmd}”", cmd="停下")
        else:
            after = msg("。被停下或打断后，说“{cmd}”接着做", cmd="继续")
        tips.append({"title": "长任务", "say": "让 Claude 做要几分钟的事",
                     "result": msg("{wait}{nudge}{after}", wait=wait, nudge=nudge, after=after)})
```

**設備認的口令一律是參數，不寫進範本**：除了上面的「停下」「继续」，還有喚醒詞（「唤醒」那條 `say` 裏的 `Hi, StackChan`）、`exit_commands`、`resume_keywords`、`calls['reply']`。逐條檢查 `describe_tips()` 的每一句：凡是引號裏是「用戶要對設備說的話」，那幾個字就作為普通字串參數傳入。

**清單**（第 181 行，每個模型一段「標籤：別名、別名」，段與段之間用「；」）：用固定的兩個範本逐項折疊，範本是字面值：

```python
def _join(items, sep):
    """把多项接起来：分隔符是我们的标点，交给 msg 翻译；每项原样（字符串）或可翻译（msg 物件）。

    对半折叠，嵌套深度是 log n：称呼没有数量上限，逐项折叠会让 JSON 和页面递归太深。
    """
    if len(items) <= 1:
        return items[0] if items else ""
    a, b = _join(items[:len(items) // 2], sep), _join(items[len(items) // 2:], sep)
    return msg("{a}；{b}", a=a, b=b) if sep == "；" else msg("{a}、{b}", a=a, b=b)

        aliases = _join([msg("{label}：{aliases}", label=m.get("label_msg") or label(m["label"]),
                             aliases=_join(list(m["aliases"]), "、")) for m in calls["models"]], "；")
```

別名是用戶的值（普通字串）；模型標籤經 Task 6 的 `label_msg`（`pages.call_targets()` 產生，`describe_call_names()` 要一併轉送 `label_msg`，否則這裏只拿得到字串）或 `label()` 翻譯。英文字典裏 `"{a}；{b}": "{a}; {b}"`、`"{a}、{b}": "{a}, {b}"`。

**工具清單段**（第 317 行，`"、".join([...])` 寫進 `segments[].text`）：這是提示詞段落的內容，頁面以 `highlight()` 當提示詞原文顯示，不翻譯（Global Constraints）。Task 6 的守門測試會列出它，在 `i18n-fstring-allow.txt` 寫明「`segments[].text`：頁面當提示詞原文原樣顯示」。

`{wait}{nudge}{after}` 這種純佔位符的範本只負責組合；每一段本身是完整的、可以單獨翻譯的句子，英文字典可以把標點換成英文標點（例如 `"；{d}没开口就提示一次进度": "; a progress note every {d} of silence"`）。

`describe_prompt` 的 `warnings` 那一句：

```python
            warnings.append(msg("提示词在 Claude Code 进程启动时一次性传入，进程存活期间（空闲 {d}才关闭）"
                                "里面的日期、时间不会更新。", d=_duration(idle)))
```

`base` 段的 `note`：

```python
        "note": msg("来自 {template}。高亮的部分是填进去的值：人设来自配置里的 prompt，日期、农历在设备连接时生成，"
                    "当前时间在 Claude 进程启动时取一次。", template=_template_name(merged)) if is_cli else
                msg("来自 {template}。高亮的部分是填进去的值：人设来自配置里的 prompt，日期、农历在设备连接时生成，"
                    "当前时间每轮发送前更新。", template=_template_name(merged)),
```

- [ ] **頁面的渲染**

`index.html` 流程頁裏下列位置把 `esc(x)` 改為 `esc(UII18n.text(x))`：`s.title`、`s.value`、`s.hint`（`stage()`）；`t.title`、`t.say`、`t.result`（tips）；`w`（warnings）；`s.title`、`s.when`、`s.note`（segments）；`s.source` 顯示的那一處（`SOURCE_PILL[s.source]` 的查表仍用原值）；`p.llm`；`highlight()` 裏的 `label`（`p.var_labels`）。`s.text` 和 `p.actual.text` 不改。

CSS 的 `.tip .say::before { content: "你："; }` 無法經字典翻譯：刪掉這條 CSS，在 tips 的模板裏改為 `<div class="say"><span class="muted">${UII18n.t("你：")}</span>${esc(UII18n.text(t.say))}</div>`。

- [ ] **更新現有測試**

`tests/admin/test_admin_pipeline.py` 裏比對 `value`、`result` 等字串的斷言，改為比對 `render(...)` 的結果（例如 `render(stage["value"]) == "停顿 800ms 算说完"`），句子內容不變。先跑一次看哪些斷言失敗，逐一改成 `render()`；不能改斷言的句子內容。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin`
Expected：全部通過（基準的環境失敗除外）。

```bash
git add main/xiaozhi-server/core/admin/pipeline.py main/xiaozhi-server/core/admin/static/index.html \
  main/xiaozhi-server/tests/admin/test_admin_pipeline.py
git commit -m "Pipeline page: keyed messages for every sentence with values; page renders them with UII18n.text()"
```

---

### Task 6: 其餘後台模組的 f-string，加上守門測試

**Files:**
- Create: `main/xiaozhi-server/tests/admin/i18n-fstring-allow.txt`、`tests/admin/test_i18n_page.py`、`tests/admin/i18n-page-allow.txt`
- Modify: `core/admin/` 的 `admin_handler.py`、`pages.py`、`plugin_settings.py`、`status.py`、`updater.py`、`grokbot.py`、`config_store.py`、`speech_probe.py`（守門測試列出時）；`core/providers/asr/doubao_stream.py`（只改 `check_connection()`）；`plugins_func/functions/web_search.py`、`get_weather.py`（錯誤類別）；`index.html`（所有顯示後端欄位的位置）
- Test: `tests/admin/test_i18n_backend.py`（第二部分）

**Interfaces:**
- Consumes: Task 4 的 `msg()`、`UIError`、`render()`。
- Produces: 回傳字典裏顯示用的欄位（`note`、`message`、`detail`、`error`）維持字串（`render()` 的結果），另加同名的 `_msg` 欄位放 msg 物件，例如 `{"note": "切换失败：…", "note_msg": {...}}`。頁面優先用 `_msg` 欄位。

- [ ] **守門測試**

先寫測試，它列出目前所有漏網的句子：

```python
# 加在 tests/admin/test_i18n_backend.py
import ast
from pathlib import Path

from tests.admin.i18n_node import KEY_CONSTRUCTORS, has_chinese, python_sources

ALLOW = Path(__file__).with_name("i18n-fstring-allow.txt")
LOG_METHODS = {"debug", "info", "warning", "error", "exception", "critical", "_log"}


def _str_const(n):
    return isinstance(n, ast.Constant) and isinstance(n.value, str)


def _chinese_literal(n):
    """一個字串字面值或 f-string，裏面的固定文字含中文（包括只有全形標點的）。"""
    if _str_const(n):
        return has_chinese(n.value)
    return isinstance(n, ast.JoinedStr) and any(_str_const(v) and has_chinese(v.value) for v in n.values)


def _chinese_formatting(tree):
    """含中文的 f-string、`中文 + 變數`、`x += 中文`、`"中文".join()`、`"中文{}".format()`、`"中文%s" % x`。

    日誌呼叫的參數除外。
    """
    skip = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in LOG_METHODS:
            for arg in node.args:
                skip.update(id(n) for n in ast.walk(arg))
    for node in ast.walk(tree):
        if id(node) in skip:
            continue
        if isinstance(node, ast.JoinedStr) and _chinese_literal(node):
            yield node
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
            sides = [node.left, node.right]
            if any(_chinese_literal(s) for s in sides) and not all(_str_const(s) for s in sides):
                yield node
        elif isinstance(node, ast.AugAssign) and isinstance(node.op, ast.Add) and _chinese_literal(node.value):
            yield node
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ("format", "join") \
                and _str_const(node.func.value) and has_chinese(node.func.value.value):
            yield node


def _scanned():
    """(檔名, 原始碼各行, 要檢查的節點)：python_sources() 的每一個範圍。"""
    for name, lines, roots in python_sources():
        yield name, lines, [n for root in roots for n in _chinese_formatting(root)]


def _allowed():
    return {"\t".join(line.split("\t", 2)[:2])
            for line in ALLOW.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")}


def test_no_chinese_sentence_is_formatted_outside_msg():
    allowed, found = _allowed(), []
    for name, lines, nodes in _scanned():
        for node in nodes:
            code = lines[node.lineno - 1].strip()
            if f"{name}\t{code}" not in allowed:
                found.append(f"{name}:{node.lineno}: {code}")
    assert not found, "改用 msg()／UIError，或在 i18n-fstring-allow.txt 寫明原因：\n" + "\n".join(found)


def test_allow_list_has_no_stale_entries():
    present = {f"{name}\t{lines[n.lineno - 1].strip()}" for name, lines, nodes in _scanned() for n in nodes}
    for entry in _allowed():
        assert entry in present, f"已不存在：{entry}"


def test_guard_catches_every_shape():
    src = '\n'.join(['a = f"缺少 {x}"', 'b = "前缀：" + x', 'c = "；" + x', 'n += "。后面"', 'd = "、".join(xs)',
                     'e = "第 {} 个".format(x)', 'g = "共 %d 个" % x', 'h = f"{x}（API）"', 'log.info(f"日志 {x}")',
                     'ok = "纯中文" + "常量"'])
    assert sorted({n.lineno for n in _chinese_formatting(ast.parse(src))}) == [1, 2, 3, 4, 5, 6, 7, 8]
```

守門測試、下面的「鍵必須是字面值」測試和 Task 7 的原文擷取，必須看**同一份**原始碼範圍和**同一組**建構函式，否則一邊產生的鍵另一邊收不到。加到 `tests/admin/i18n_node.py`：

```python
import ast

SERVER = Path(__file__).resolve().parents[2]
ADMIN = SERVER / "core" / "admin"
# 後台之外、但錯誤會顯示在後台的範圍：{檔案: {函式名稱}}，None 表示整個檔案
EXTRA = {SERVER / "core" / "providers" / "asr" / "doubao_stream.py": {"check_connection"},
         SERVER / "plugins_func" / "functions" / "web_search.py": None,
         SERVER / "plugins_func" / "functions" / "get_weather.py": None}
# 第一個參數是訊息鍵的呼叫：msg() 和 KeyedError 的每一個子類（新增子類時要加在這裏，
# test_key_constructors_cover_every_keyed_error 會檢查）
KEY_CONSTRUCTORS = {"msg", "UIError", "KeyedError", "UpdateError", "SearchError", "WeatherError"}


def python_sources():
    """(檔名, 原始碼各行, [AST 範圍])：core/admin/*.py（i18n_msg.py 除外，它只是轉送鍵）加上 EXTRA 的函式。"""
    for path in sorted(p for p in ADMIN.glob("*.py") if p.name != "i18n_msg.py"):
        src = path.read_text(encoding="utf-8")
        yield path.name, src.splitlines(), [ast.parse(src)]
    for path, funcs in EXTRA.items():
        src = path.read_text(encoding="utf-8")
        tree = ast.parse(src)
        if funcs is None:
            yield path.name, src.splitlines(), [tree]
            continue
        found = [f for f in ast.walk(tree) if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))
                 and f.name in funcs]
        assert {f.name for f in found} == funcs, f"{path.name}: 找不到 {funcs}"
        yield path.name, src.splitlines(), found


def key_calls(root):
    """root 裏所有 KEY_CONSTRUCTORS 的呼叫。"""
    for node in ast.walk(root):
        if isinstance(node, ast.Call):
            f = node.func
            name = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else ""
            if name in KEY_CONSTRUCTORS:
                yield node
```

再加一條：這些呼叫的第一個參數必須是字串字面值（執行時拼出來的鍵擷取不到）：

```python
from tests.admin.i18n_node import key_calls


def test_key_constructors_cover_every_keyed_error():
    """python_sources() 裏每一個繼承 KeyedError／UIError 的類別都在 KEY_CONSTRUCTORS：漏掉的話它的鍵不會被擷取。"""
    keyed = {"KeyedError", "UIError"}
    found = set()
    for _name, _lines, roots in python_sources():
        for root in roots:
            for node in ast.walk(root):
                if isinstance(node, ast.ClassDef) and any(
                        (b.id if isinstance(b, ast.Name) else getattr(b, "attr", "")) in keyed for b in node.bases):
                    found.add(node.name)
    assert found <= KEY_CONSTRUCTORS, found - KEY_CONSTRUCTORS


def test_message_keys_are_literals():
    bad = [f"{name}:{call.lineno}" for name, _lines, roots in python_sources() for root in roots
           for call in key_calls(root)
           if not (call.args and isinstance(call.args[0], ast.Constant) and isinstance(call.args[0].value, str))]
    assert not bad, bad
```

`updater.py:265` 的 `UpdateError(info['unsupported'])` 會被這一條擋下。`version()` 的三個 `unsupported` 原因（第 116、118、124 行）都是固定句子：改為 `m = msg("…")`，`info["unsupported"], info["unsupported_msg"] = render(m), m`。`i18n_msg.py` 的 `KeyedError` 加一個從現成 msg 物件建立例外的方法：

```python
    @classmethod
    def from_msg(cls, m: dict):
        return cls(m["msg_key"], **(m.get("msg_params") or {}))
```

第 265 行改為 `raise UpdateError.from_msg(info["unsupported_msg"])`。鍵的字面值仍在 `version()` 的 `msg()` 呼叫裏，所以會被擷取；`from_msg` 不是建構函式名稱，不受字面值檢查。第 262、267–268 行改為 `UpdateError("已经在更新了，请等它结束")` 和 `UpdateError("这些文件被改过，更新会和它们冲突：{files}。请先撤销（git checkout -- <文件>）或备份后再更新", files=", ".join(files[:10]))`（檔名是普通字串參數，用 ASCII 的 `, ` 分隔，兩種語言都適用，守門測試也不會擋）。

`i18n-fstring-allow.txt` 的格式：每行 `檔名<TAB>那一行去掉前後空白的原文<TAB>原因`，`#` 開頭是註解。只收兩類：**不會顯示在後台**的句子（送給大模型或設備朗讀的文字、寫進設定檔的內容），和頁面**當作提示詞原文原樣顯示**的 `segments[].text`（例如 `pipeline.py:317` 的工具清單）。

先跑一次：

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin/test_i18n_backend.py::test_no_chinese_sentence_is_formatted_outside_msg`
Expected：FAIL。計劃撰寫時在 #9 上實際執行過這個掃描（Task 4、5 改動之前）：`core/admin` 103 行（`pages.py` 28、`admin_handler.py` 24、`pipeline.py` 22、`status.py` 10、`updater.py` 8、`plugin_settings.py` 6、`grokbot.py` 2、`mcp_settings.py` 2、`speech_settings.py` 1），`web_search.py`、`get_weather.py` 各 18，另加 `doubao_stream.check_connection()`。到這一步時 `pipeline.py`、`speech_settings.py`、`mcp_settings.py` 應已是 0。`config_store.py:186–187` 的 `f"{field}: {e}"` 沒有中文字面值，掃描看不到，按上面的說明另外改。這份清單就是這個 task 的工作範圍。`test_guard_catches_every_shape` 必須通過：它證明守門測試認得每一種寫法。

- [ ] **逐處改寫**

按清單逐處處理，每處屬於下面一種：

1. **`raise ValueError(f"…")`**（`pages.py`、`plugin_settings.py`）：改為 `raise UIError("范本 {x}", x=…)`，範本就是原句把 `{運算式}` 換成具名佔位符。例如 `pages.py:614`：

   ```python
   raise UIError("热词“{word}”不能包含逗号或换行，长度不超过 40 个字", word=w)
   ```

   `', '.join(bad)` 這類名稱清單照原樣作為參數（`UIError("工具名不对：{names}", names=", ".join(bad))`）。

2. **`self._error(f"…", status)`**（`admin_handler.py`）：改為 `self._error(msg("范本", …), status)`。`_error()` 收到 dict 會同時填 `error` 和 `msg_key`。例如第 234 行：

   ```python
   return self._error(msg("密码至少 {n} 位", n=auth.MIN_PASSWORD_LENGTH), 400)
   ```

   參數是第三方例外的原文時（`{e}`、`{e.detail}`），範本保留固定前綴，例外文字作為參數照原樣顯示（spec §6.1「第三方的例外文字」）：`msg("启动更新失败：{error}", error=str(e))`。

3. **放進回傳字典的句子**（`admin_handler.py` 的 `note`、`error`；`status.py` 的 `detail`；`updater.py` 和 `plugin_settings.py` 的 `message`；`grokbot.py` 的 `note`）：建立 msg 物件 `m`，欄位放 `render(m)`，另加 `<欄位>_msg: m`。例如 `admin_handler.py:298`：

   ```python
            m = msg("切换失败：{error}。已恢复为原来的 {old}", error=result["error"], old=old or msg("配置"))
            result["note"], result["note_msg"] = render(m), m
   ```

   `"；热词重新加载失败：…"` 這種追加在 `note` 後面的半句（第 402、464、466、678、680 行，包括 `note += '…'` 和 `'；' + …`），改為整句範本：`msg("{note}；热词重新加载失败：{error}", note=note_msg, error=...)`，其中 `note_msg` 是前一句的 msg 物件（是普通字串時先 `label()` 包起來，讓它仍被翻譯）。追加之後 `note` 和 `note_msg` 一起重設，不能只改其中一個。

   這個約定適用於**每一個**帶句子的顯示欄位，不只 `note`、`message`、`detail`、`error`：`label`（`pages.py:453` 的 `asr_label`、`pages.py:818–826` 的 `call_targets`）改為 `label_msg`（`asr_label` 第 452 行的 `name = "X-ASR 中英混合"` 改為 `name = label("X-ASR 中英混合")`、第 450 行改為 `name = label(SHERPA_MODEL_LABELS.get(model_type, model_type))`：字面值要直接寫在 `label()` 裏，Task 7 才收得到），`updater.version()` 的 `unsupported`（`updater.py:114–126`）改為 `unsupported_msg`。`status._check()` 多一個 `detail_msg` 參數：

   ```python
   def _check(name, ok, detail="", level=None, detail_msg=None):
       return {"name": name, "level": level or ("ok" if ok else "error"), "detail": detail,
               **({"detail_msg": detail_msg} if detail_msg else {})}
   ```

   `status.py:89` 轉送 `asr_model_check()['detail']` 時，一併轉送它的 `detail_msg`。`asr_model_check()` 的另一個讀者 `handle_asr_use`（`admin_handler.py:923–924`）同樣不能把 `detail` 當普通字串：

   ```python
   model = d["local"]["model"] or {}
   return self._error(msg("X-ASR 模型文件不完整（{detail}），请重新运行安装脚本下载",
                          detail=model.get("detail_msg") or model.get("detail", "")), 400)
   ```

   **把兩個結果合成一個的地方**：`handle_intent_save`（`admin_handler.py:1173`、`1185–1186`）只保留 `_apply()` 的 `note`，之後用它蓋掉 `_switch()` 的 `note`，`note_msg` 卻還是 `_switch()` 的「已经在使用」。改為保留整個字典，兩個欄位一起換：

   ```python
                           notes.append(await self._apply("Intent"))
   ...
           if result["note"] == "已经在使用" and notes:
               last = notes[-1]
               result["note"], result["note_msg"] = last["note"], last.get("note_msg") or label(last["note"])
   ```

   Task 8 加一個 HTTP 案例：`function_call` 模式改插件、意圖已在使用時，回應的 `note_msg["msg_key"]` 是 `_apply()` 的句子，不是「已经在使用」。

   **失敗時經 `_error()` 回傳的結果字典**：`admin_handler.py` 第 638（`handle_llm_vendor_test` → `_test_llm`）、670（`_use_llm`）、939（`handle_asr_use`）、964（`handle_doubao_test` → `check_connection`）、1109（`handle_tts_use`）、1184（意圖設定）行，一律改為 `self._error(result.get("<欄位>_msg") or result["<欄位>"], status)`（欄位是那一處原本傳的 `note` 或 `error`）。`_test_llm` 的錯誤（第 609–623 行）和 `doubao_stream.check_connection()`（`core/providers/asr/doubao_stream.py:496–526`）的錯誤都加 `error_msg`，固定前綴進範本，第三方的原文作為普通字串參數，例如：

   ```python
   m = msg("识别服务返回错误 {code}：{detail}", code=code, detail=str(detail)[:200])
   return {"ok": False, "error": render(m), "error_msg": m}
   ```

   **`updater.UpdateError`**（`updater.py:37`，`admin_handler.py:528–530` 以 409 回傳）：改為 `class UpdateError(KeyedError)`，`updater.py:262–268` 拋出它的地方改為 `UpdateError("范本", …)`。`KeyedError` 不是 `ValueError`，所以不會被別處的 `except ValueError` 接走，行為跟原本的 `Exception` 子類一樣。

   **`config_store.py:186–187`** 的 `raise ValueError(f"{field}: {e}")`：f-string 裏沒有中文字面值，但執行時會變成「max_tokens: 数字不能为空」這種不在字典裏的句子。改為：

   ```python
   raise UIError("{field}：{error}", field=field, error=e.payload() if isinstance(e, KeyedError) else str(e))
   ```

   並把 `_convert` 裏拋出的中文錯誤也改為 `UIError`，讓 `error` 參數是可翻譯的物件。

   **插件的「測試」**（`plugin_settings.py:155–203`）：
   - `run_test()` 接到 `ValueError` 後以 `ValueError(_redact(str(e)))` 重新拋出，會丟掉 key。改為：是 `KeyedError` 時 `raise UIError.from_msg({"msg_key": e.key, "msg_params": _redact_params(e.params)}) from e`（字典直接寫出來，不經 `msg()`：`msg` 和 `UIError` 都在 `KEY_CONSTRUCTORS` 裏，第一個參數不是字面值會被「鍵必須是字面值」擋下；鍵的字面值在原本拋出它的地方），否則照原樣；`_redact_params` 對每個普通字串參數做 `_redact()`，對 msg 物件參數遞迴。成功路徑同樣處理 `message_msg`，不能只遮蔽字串欄位。加一個測試：參數裏的 API key 在 `error` 和 `msg_params` 兩處都被遮蔽。
   - `_test_web_search`、`_test_weather` 把 `SearchError`／`WeatherError` 轉成 `ValueError(str(e))`。這些句子（「还没有填写 API Key」「天气服务暂时连不上」「没找到「{name}」这个地方」）是這個 repo 寫的，不是第三方：`plugins_func/functions/web_search.py` 的 `SearchError` 和 `get_weather.py` 的 `WeatherError` 改為 `KeyedError` 的子類，`raise` 處改為帶範本和參數（`str(e)` 仍是填好的简中句子，設備朗讀不受影響）。`SearchError` 原本是 `__init__(self, message, kind=TEMPORARY, spoken="")`，8 個呼叫處以位置參數傳 `kind`、`spoken`（例如第 142、226 行），第 303–306 行朗讀時讀 `e.kind`、`e.spoken`。改為：

```python
class SearchError(KeyedError):
    def __init__(self, key, kind=TEMPORARY, spoken="", **params):
        super().__init__(key, **params)
        self.kind = kind
        self.spoken = spoken or str(self)   # 跟原本的 `spoken or message` 相同：str(self) 就是填好的简中句子
```

`WeatherError` 原本是不帶其他參數的 `Exception` 子類（`get_weather.py:74`），改為 `class WeatherError(KeyedError): pass`。

呼叫處把原本的句子改成範本、數值改成具名參數，`kind`、`spoken` 照原位置傳。`WeatherError` 按它現有的建構參數同樣處理。第 139 行組 `detail` 時的全形 `：` 改為 ASCII 的 `: `（`detail` 是第三方原文的參數，會原樣出現在英文頁面上）。新的鍵加進 `UI_ZH_HANT`（#9 的字典裏沒有：插件測試的錯誤目前連繁中頁面都顯示简中）；`_test_*` 改為 `raise UIError.from_msg(e.payload())`。兩個檔案加進 `i18n_node.EXTRA`（整個檔案：`EXTRA` 的值寫 `None` 表示全檔，`python_sources()` 對 `None` 回傳整棵樹）。守門測試會列出這兩個檔案裏設備朗讀的天氣、搜尋播報 f-string：它們是設備說的話，寫進 `i18n-fstring-allow.txt` 並註明「設備朗讀」。
   - `_test_weather` 的成功訊息裏 `lines[1]` 是 `format_report()` 產生、設備朗讀的天氣播報：跟對話內容同類，作為普通字串參數照原樣顯示，`msg("查到的地点是 {place}。{weather}", place=place, weather=lines[1] if len(lines) > 1 else "")`。

   **我們的標籤不能當普通字串參數**（下面幾處要明確改，守門測試和 Task 8 都看不到）：
   - `pages.call_targets()` 產生的標籤（`"Claude（本机 Claude Code）"`、`f"{vendor['label']}（API）"`、`f"{g['bot_name']}（Grok Bot）"`）：每項多一個 `label_msg`（`msg("{vendor}（API）", vendor=label(vendor["label"]))`、`msg("{bot}（Grok Bot）", bot=g["bot_name"])`，Bot 名稱是用戶的值），`describe_call_names()` 一併轉送，`save_call_names()`／`_clean_aliases()` 的錯誤（`pages.py:865–878`、`891–903`）用 `known_msg[entry]` 而不是 `known[entry]` 作參數；頁面 `labelOf`（`index.html:1593`）改讀 `label_msg`。頁面「加模型」（`index.html:1699`）從 `d.targets` 複製一項時也帶上它：`const m = { entry: t.entry, label: t.label, label_msg: t.label_msg, aliases: [], ready: true };`，否則新加的卡片標題在重新載入前顯示合成的简中標籤。凡是頁面把後端的一項複製成新物件的地方，都連 `_msg` 欄位一起複製（`grep -n "label: [a-z]*\.label" index.html` 列出這類寫法，每一處都檢查）。
   - `plugin_settings._values()` 的區域變數 `label = f["label"]`（第 88 行）會遮住 `label()`：改名為 `field_label`，錯誤的參數寫 `label=label(field_label)`。`pages.py` 同樣檢查有沒有遮住 `label` 的區域變數。
   - `config_store.mask_key()` 對短 key 回傳「已设置」（第 108–109 行），它餵給三種欄位：`key_hint`（`pages.py:60`、`pages.py:507`、`speech_settings.py:43`）、`token_hint`（`pages.py:510`）和 `hint_set`（`plugin_settings.py:66`），頁面在 `index.html:823/935/939/1414` 把它跟其他文字拼在一起。在 `config_store.py` 加一個小函式，所有這些呼叫處都改用它：

     ```python
     def masked_fields(name: str, value) -> dict:
         """{name: 遮住的 key}，短 key 時多一個 name_msg，讓頁面翻譯「已设置」。"""
         hint = mask_key(value)
         return {name: hint, **({f"{name}_msg": msg("已设置")} if hint == "已设置" else {})}
     ```

     例如 `**masked_fields("key_hint", entry.get("api_key"))`。頁面四處改為 `esc(UII18n.text(x.key_hint_msg || x.key_hint))`（`token_hint`、`hint_set` 同理）。頁面守門測試的 `FIELDS` 加上 `key_hint`、`token_hint`、`hint_set`（`.hint` 的規則配對不到它們）。Task 8 加一個案例：短 key 在英文頁面沒有中文，長 key 照原樣遮住。
   - Task 8 加兩個英文顯示的案例：重複稱呼的錯誤（`save_call_names()`）和插件欄位驗證錯誤（`plugin_settings._values()`）。

4. **不顯示在後台的**（送給模型或設備的文字）：寫進 `i18n-fstring-allow.txt` 並寫明原因。這一類在 `core/admin` 裏預期很少；每一條都要能說出它最後去了哪裏。

- [ ] **頁面：後端送來的顯示欄位都經 `UII18n.text()`**

`UII18n.init()` 只在載入時翻譯一次靜態標記，之後由 JavaScript 寫入的內容只有經過 `t()`／`text()` 的才會翻譯。#9 的頁面有約 25 處把後端送來的句子或標籤以 `esc(x.label)` 這類寫法直接顯示（例如狀態頁 `esc(c.name)`／`esc(c.detail)`，插件頁 `esc(f.label)`、`esc(f.hint)`、`esc(d.legacy_note)`，更新頁 `esc(d.unsupported)`，catalog 的 `p.label`、`x.label`、`o.label`），連繁中頁面都顯示简中。全部改為經 `UII18n.text()`，有 `<欄位>_msg` 的優先用它：

- innerHTML 模板裏：`esc(UII18n.text(x.note_msg || x.note))`；
- `toast()` 和 `textContent`：**不加** `esc()`（它們本來就不解析 HTML，`esc()` 會把 `&` 顯示成 `&amp;`），也不能直接傳物件（`toast()` 裏的 `t()` 會顯示 `[object Object]`）：`toast(UII18n.text(r.note_msg || r.note))`；
- `throw new Error(...)`：`throw new Error(UII18n.text(switched.note_msg || switched.note))`（第 1277 行原本是 `switched.note`，會丟掉 key）。

`u.log`（網關更新的輸出，來自 `scripts/update.sh`）照原樣顯示（Global Constraints）。`u.error` 不全是 `update.sh` 的輸出：`updater.status()` 在第 331、333 行自己寫「更新失败，没有输出」和「更新没有正常结束…」。頁面改為 `esc(UII18n.t(u.error || ""))`：這兩句是字典的鍵（Task 7 的顯示欄位常數會收到它們），`update.sh` 的其他行不在字典裏，`t()` 原樣回傳。`updater._fetch_error()` 第 223 行的 `last or '未知错误'` 改為 `last or label("未知错误")`。用戶的值（設備名稱、SSID、模型名稱、`device_id`、用戶填的稱呼和熱詞）也照原樣。

- [ ] **頁面守門測試**

`tests/admin/test_i18n_page.py`：

```python
"""index.html：後端送來的顯示欄位都經 UII18n.text()／t()，用戶的值列在 i18n-page-allow.txt。"""
import re
from pathlib import Path

from tests.admin.i18n_node import has_chinese

INDEX = Path(__file__).resolve().parents[2] / "core" / "admin" / "static" / "index.html"
ALLOW = Path(__file__).with_name("i18n-page-allow.txt")
FIELDS = ("label", "name", "hint", "desc", "title", "note", "detail", "message", "error", "unsupported",
          "legacy_note", "say", "result", "when", "source", "value", "reason", "llm", "gender", "style",
          "model_label", "bots_error", "key_hint", "token_hint", "hint_set")
# 已經翻譯的部分先拿掉：UII18n.text(...)、UII18n.t(...)、UII18n.msg(...)（允許一層巢狀括號）
TRANSLATED = re.compile(r"UII18n\.(?:text|t|msg)\((?:[^()]|\([^()]*\))*\)")
# 會顯示出來的位置：${...}、esc(...)、toast(...)、textContent = ...;（同樣允許一層巢狀括號）
SHOWN = re.compile(r"\$\{((?:[^{}]|\{[^{}]*\})*)\}|esc\(((?:[^()]|\([^()]*\))*)\)|toast\(((?:[^()]|\([^()]*\))*)\)"
                   r"|textContent\s*=\s*([^;]+);")
# x.note、x.note_msg（_msg 物件直接顯示會變成 [object Object]）
FIELD = re.compile(r"([A-Za-z_$][\w$]*(?:\.[\w$]+|\[[^\]]+\])*\.(?:%s)(?:_msg)?)\b(?!\s*\()" % "|".join(FIELDS))
# esc(w)、esc(labelOf(x))：看不出內容是甚麼，一律列出，由 allow 檔逐條說明
OPAQUE = re.compile(r"^\s*([A-Za-z_$][\w$]*(?:\((?:[^()]|\([^()]*\))*\))?)\s*$")
ESC = re.compile(r"esc\(((?:[^()]|\([^()]*\))*)\)")


def untranslated(code: str):
    """code 裏顯示出來、但沒經過 UII18n 的欄位讀取（三元運算和 || 的兩邊都算）。"""
    code = TRANSLATED.sub("''", code)
    for m in SHOWN.finditer(code):
        expr = next(g for g in m.groups() if g is not None)
        yield from (f.group(1) for f in FIELD.finditer(expr))
        # 只看 esc(...) 的內容（${n} 這種數字很常見）；esc 可能就是這一處，也可能在 ${...} 裏面
        inner = ([expr] if m.group(2) is not None else []) + [e.group(1) for e in ESC.finditer(expr)]
        yield from ("esc(" + x.strip() + ")" for x in inner if OPAQUE.match(x))


def _allowed():
    return {line.split("\t", 1)[0] for line in ALLOW.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")}


def test_guard_sees_every_shape():
    assert list(untranslated("esc(c.detail)")) == ["c.detail"]
    assert list(untranslated('toast(r.changed.length ? r.note : UII18n.t("没有改动"))')) == ["r.note"]
    assert list(untranslated("`<b>${o.label}</b>`")) == ["o.label"]
    assert list(untranslated("el.textContent = x.message;")) == ["x.message"]
    assert list(untranslated("esc(x.note_msg || x.note)")) == ["x.note_msg", "x.note"]
    assert list(untranslated("el.textContent = x.note_msg;")) == ["x.note_msg"]
    assert list(untranslated("esc(w)")) == ["esc(w)"]
    assert list(untranslated("`<i>${esc(w)}</i>`")) == ["esc(w)"]
    assert list(untranslated("`${n} ${esc(UII18n.text(w))}`")) == []
    assert list(untranslated("esc(labelOf(d.default))")) == ["esc(labelOf(d.default))"]
    assert list(untranslated("esc(UII18n.text(labelOf(d.default)))")) == []
    assert list(untranslated("esc(UII18n.text(x.note_msg || x.note))")) == []
    assert list(untranslated('toast(UII18n.text(r.note_msg || r.note))')) == []
    assert list(untranslated("`${UII18n.t(\"默认是\")} ${esc(UII18n.text(a.label))}`")) == []


def test_backend_strings_are_translated_on_the_page():
    allowed, found = _allowed(), []
    for no, line in enumerate(INDEX.read_text(encoding="utf-8").splitlines(), 1):
        found += [f"{no}: {e}" for e in untranslated(line) if e not in allowed]
    assert not found, "改為 UII18n.text(...)，或把用戶的值列進 i18n-page-allow.txt：\n" + "\n".join(found)


def test_page_allow_list_has_no_stale_entries():
    present = {e for line in INDEX.read_text(encoding="utf-8").splitlines() for e in untranslated(line)}
    for expr in _allowed():
        assert expr in present, f"已不存在：{expr}"


SCRIPT = re.compile(r"<script>(.*?)</script>", re.S)
T_LITERAL = re.compile(r'UII18n\.t\(\s*(?:"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')\s*\)')
MSG_KEY = re.compile(r'msg_key:\s*(?:"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')')
COMMENT = re.compile(r"(?:^|\s)//.*$")
SCRIPT_ALLOW = Path(__file__).with_name("i18n-script-allow.txt")


def test_no_chinese_in_scripts_outside_translation_calls():
    """<script> 裏的中文（包括模板裏的全形標點）只能在 UII18n.t("…") 或 msg_key 字面值裏，註解除外。"""
    allowed = {line.split("\t", 1)[0] for line in SCRIPT_ALLOW.read_text(encoding="utf-8").splitlines()
               if line and not line.startswith("#")}
    found = []
    html = INDEX.read_text(encoding="utf-8")
    for block in SCRIPT.finditer(html):
        first = html[:block.start(1)].count("\n") + 1
        for i, line in enumerate(block.group(1).splitlines()):
            rest = COMMENT.sub("", MSG_KEY.sub("", T_LITERAL.sub("", line)))
            if has_chinese(rest) and line.strip() not in allowed:
                found.append(f"{first + i}: {line.strip()}")
    assert not found, "把整句放進一個 UII18n.t() 範本或 UII18n.msg({msg_key: …})：\n" + "\n".join(found)
```

`<script src=…>` 不在範圍裏（`SCRIPT` 只配對沒有屬性的 `<script>`）。`i18n-script-allow.txt` 收刻意保留的行（每行 `去掉前後空白的原文<TAB>原因`），例如 `SOURCE_PILL` 這種以後端原值作查表鍵、不會顯示的中文。先跑一次（改頁面之前）：它必須列出約 85 行。

**模板裏的標點**：`（${UII18n.t("默认是")} ${esc(active.label)}）` 這種把譯文和全形標點拼起來的寫法，在英文頁面會顯示 `（Default is X）`。逐句改為一個完整的範本：

```javascript
UII18n.msg({ msg_key: "（默认是 {name}）", msg_params: { name: { msg_key: active.label } } })
```

`{msg_key: active.label}` 讓 catalog 標籤被翻譯（Task 3：只有物件參數會翻譯）；用戶的值直接放字串。`esc()` 包在外面（這是 innerHTML 模板）。`highlight()` 裏的 `（`、`callPill` 的 `、` 連接（改用 `UII18n.msg({msg_key: "{a}、{b}", …})` 逐項折疊，同 Task 5 的 `_join`）也照這樣處理。這些 `msg_key` 字面值由 Task 7 的原文來源第 2 項一併擷取（見 Task 7）。

`i18n-page-allow.txt` 每行 `運算式<TAB>原因`，例如 `d.name\t設備名稱，用戶設定的值`、`esc(name)\t用戶填的稱呼`。只收用戶的值、數字和提示詞、對話原文；我們的句子和 catalog 標籤不能放進來。`esc(變數)` 和 `esc(函式(…))` 一律列出（#9 的頁面約 48 處），逐條看變數的來源：是我們的句子就改成 `esc(UII18n.text(…))`（例如 warnings 的 `esc(w)`、`labelOf` 的結果），是用戶的值才放進 allow 檔。

先跑一次（改頁面之前）：在 #9 的 `index.html` 上它列出 177 處（140 處欄位讀取、37 處 `esc(變數)`／`esc(函式(…))`，已在計劃撰寫時實際執行這組正規表示式確認，自我測試 14 項全過），證明它抓得到。其中一部分是用戶的值（設備名稱、模型名稱、SSID），進 allow 檔；其餘改成經 `UII18n.text()`。改完頁面後再跑必須通過。這個測試是靜態的近似：它找的是「顯示一個名稱像句子的欄位」的寫法，Task 9 的瀏覽器檢查補上它看不到的地方（例如先存進變數再顯示）。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin`
Expected：全部通過，包括後端和頁面的守門測試（基準的環境失敗除外）。再加一個 HTTP 測試（放在 `test_i18n_backend.py`）：讓 `_use_llm` 切換到一個不存在的模型，回應必須帶 `msg_key`，而且 `render_js([回應], "en")` 不含中文（這一項要等 Task 7 的英文字典，先標 `@pytest.mark.xfail(strict=True, reason="en.js in Task 7")`，Task 7 完成時拿掉標記）。原有測試裏比對錯誤句子的斷言（例如 `pytest.raises(ValueError, match=…)`）照樣通過，因為 `str(UIError)` 就是原句；比對回傳字典欄位的斷言也不變，因為欄位仍是原句。

```bash
git add main/xiaozhi-server/core/admin main/xiaozhi-server/core/providers/asr/doubao_stream.py \
  main/xiaozhi-server/plugins_func/functions/web_search.py main/xiaozhi-server/plugins_func/functions/get_weather.py \
  main/xiaozhi-server/tests/admin
git commit -m "Admin: keyed messages for every formatted sentence; page translates every backend field; guard tests"
```

---

### Task 7: 字典完整性和英文字典

**Files:**
- Create: `main/xiaozhi-server/tests/admin/test_i18n_catalog.py`
- Modify: `en.js`（完整內容）、`zh-Hant.js`（補缺的鍵）

**Interfaces:**
- Consumes: Task 3 的 `i18n_node.catalogs()`；Task 4–6 的 `msg()`、`UIError`。

**原文的來源**（spec §6.4，「原文」的定義）：

1. `index.html` 的靜態標記：`<body>` 裏的文字節點（`script`、`style`、`textarea` 和 `[data-no-i18n]` 除外）和 `title`、`aria-label`、`placeholder`、`data-kb-enter` 屬性，以及 `<title>`；
2. `index.html` 的 `<script>` 裏所有 `UII18n.t("…")`、`UII18n.t('…')` 的字面值，和 `msg_key: "…"` 的字面值（Task 6 的模板範本）；
3. `tests/admin/i18n_node.python_sources()` 範圍裏（`core/admin/*.py` 加上 `doubao_stream.check_connection()`）所有 `KEY_CONSTRUCTORS`（`msg`、`UIError`、`KeyedError`、`UpdateError`）呼叫的第一個參數——跟 Task 6 的守門測試是同一份範圍、同一組名稱；
4. 同一範圍裏 `ValueError()` 和 `self._error()` 的字面值參數；
5. 執行期的值：對四份設定（安裝範本、Claude CLI、EdgeTTS 加 API 模型、`test_admin_pipeline.py` 的 `API_YAML`——它開了 `function_call`，走到工具段）呼叫 `pipeline.describe()`，走遍回傳結構裏顯示用的欄位，收集字串和 `msg_key`（包括巢狀參數裏的），再加上 `describe()` 的 `var_labels` 的值（它們在變數名稱底下，不在顯示欄位名稱底下）；
6. catalog 表格：`catalog.EDGE_VOICES` 的 `name`、`group`、`gender`、`style`，`catalog.CLAUDE_MODELS`、`CLAUDE_EFFORTS` 的 `label`，`catalog.VENDOR_BY_ENTRY` 的 `label`，`pages.SHERPA_MODEL_LABELS` 的值，`reply_language.OPTIONS` 的 `label`，插件欄位的 `label`、`hint`（以 import 讀取，不靠字典）。像「女」「男」「日期」這種简繁同形的字，#9 的字典沒有收（繁中頁面不需要），只有這一項會把它們列為英文要翻的原文；
7. `UI_ZH_HANT` 和 `UI_ZH_HANS` 現有的鍵：這兩份字典是 #9 逐一收集的後台句子（包括後端以普通字串傳出、上面幾項抓不到的），所以也算原文，**但**不包括 `NOT_UI`：`reply_language.py` 的 `RULES`（送給大模型的回覆語言指示）和 `PHRASES`（設備說的話），它們不是介面文字，英文字典不收（Global Constraints：提示詞不翻譯）。

**語言名稱的例外**：`reply_language.OPTIONS` 的 `label`（例如「日語 日本語」「韓語 한국어」）的英文值保留語言的本名（`Japanese 日本語`），所以這些鍵的英文值可以含中日文字元；集合由測試從 `OPTIONS` 推出，不是手寫清單。

**規則：**

- 原文裏含中文的條目，都必須在 `UI_ZH_HANT` 或 `UI_ZH_HANS` 其中之一（简中原文在前者，繁中原文在後者）；
- 原文裏含中文的條目，都必須在 `UI_EN`；
- `UI_EN` 的鍵不能有原文以外的（不能有錯字的鍵）；
- 每份字典的值不能是空字串；`UI_EN` 的值不能含中文，例外只有喚醒詞規則要求保留的中文；
- 範本的佔位符：`UI_EN` 和 `UI_ZH_HANT` 裏每個值的 `{名稱}` 集合，必須跟鍵的 `{名稱}` 集合相同；
- 喚醒詞規則（spec §6.3）：鍵含「小麦」的條目，值必須逐字含「小麦」。網關目前沒有這樣的條目，但規則照樣檢查，以免日後加入時漏掉。

- [ ] **完整性測試**

```python
"""字典完整性（spec §6.4）：原文的每一條都有繁中／简中和英文，英文字典沒有多餘的鍵。"""
import ast
import re
from html.parser import HTMLParser
from pathlib import Path

import pytest

from core.admin import config_store, pipeline
from tests.admin.i18n_node import KEY_CONSTRUCTORS, catalogs, has_chinese as _cjk, python_sources   # 中文＝表意文字＋CJK 標點＋全形字元

SERVER = Path(__file__).resolve().parents[2]
ADMIN = SERVER / "core" / "admin"
INDEX = ADMIN / "static" / "index.html"
ATTRS = ("title", "aria-label", "placeholder", "data-kb-enter")
DISPLAY = {"title", "value", "hint", "say", "result", "source", "when", "note", "llm"}
PLACEHOLDER = re.compile(r"\{(\w+)\}")


class _Markup(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.stack, self.in_body = set(), [], False

    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        skip = tag in ("script", "style", "textarea") or "data-no-i18n" in a
        if tag not in self.VOID:   # 沒有結束標籤的元素不入棧，否則之後的 pop 會錯位
            self.stack.append(skip or (self.stack[-1] if self.stack else False))
        if tag == "body":
            self.in_body = True
        if self.in_body and not tag in ("script", "style"):
            self.out.update(v for k, v in a.items() if k in ATTRS and v)

    def handle_endtag(self, tag):
        if self.stack:
            self.stack.pop()

    def handle_data(self, data):
        text = data.strip()
        if text and (self.in_body and not (self.stack and self.stack[-1]) or self.lasttag == "title"):
            self.out.add(text)


def _js_literals(html):
    out = set()
    lit = r'("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')'
    for pattern in (r'UII18n\.t\(\s*' + lit + r'\s*\)', r'msg_key:\s*' + lit):
        for m in re.finditer(pattern, html):
            out.add(ast.literal_eval(m.group(1)))   # JS 和 Python 的簡單字串跳脫寫法相同（\" \' \\ \n）
    return out


DISPLAY_KEYS = {"note", "error", "message", "detail", "label", "name", "hint", "desc", "title", "unsupported"}


def _chinese_constants(expr):
    """expr 裏所有含中文的字串常數（f-string 的片段除外：那些由 Task 6 的守門測試處理）。"""
    inside_fstring = {id(v) for n in ast.walk(expr) if isinstance(n, ast.JoinedStr) for v in n.values}
    return {n.value for n in ast.walk(expr) if isinstance(n, ast.Constant) and isinstance(n.value, str)
            and id(n) not in inside_fstring and _cjk(n.value)}


def _display_key(node):
    return isinstance(node, ast.Constant) and node.value in DISPLAY_KEYS


def _python_literals():
    out = set()
    for _name, _lines, roots in python_sources():
        for root in roots:
            for node in ast.walk(root):
                if isinstance(node, ast.Call) and node.args:
                    f = node.func
                    name = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else ""
                    if name in KEY_CONSTRUCTORS | {"label", "ValueError", "_error"} \
                            and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                        out.add(node.args[0].value)
                # 直接放進顯示欄位的常數：{"note": "已取消"}、result["error"] = "更新失败，没有输出"
                elif isinstance(node, ast.Dict):
                    for k, v in zip(node.keys, node.values):
                        if k is not None and _display_key(k):
                            out |= _chinese_constants(v)
                elif isinstance(node, ast.Assign):
                    if any(isinstance(t, ast.Subscript) and _display_key(t.slice) for t in node.targets):
                        out |= _chinese_constants(node.value)
                # 區域變數再傳進 label()（pages.py:453 的 name = "X-ASR 中英混合"）由上面的 label() 規則收不到：
                # Task 6 改寫時字面值直接寫在 label() 裏，或寫成 label("X-ASR 中英混合") 再賦值
    return out


def test_python_literals_sees_every_shape():
    src = '\n'.join(['a = label("甲")', 'b = {"note": "乙", "at": 1}', 'r["error"] = x if y else "丙"',
                     'c = {"note": f"丁{x}"}', 'd = {"other": "戊"}', 'e = UIError("己")'])
    from unittest import mock
    with mock.patch(__name__ + ".python_sources", lambda: [("t.py", [], [ast.parse(src)])]):
        assert _python_literals() == {"甲", "乙", "丙", "己"}


def _catalog_labels():
    """頁面會顯示的 catalog 表格。必有的鍵直接索引（表格結構改了就報錯），選填的才用 get。"""
    from core.admin import catalog, pages
    from core.agent import reply_language
    out = {v[k] for v in catalog.EDGE_VOICES for k in ("name", "group", "gender", "style")}
    out |= {o["label"] for o in (*catalog.CLAUDE_MODELS, *catalog.CLAUDE_EFFORTS, *catalog.CLAUDE_TOOLS,
                                 *catalog.LLM_VENDORS, *catalog.DOUBAO_RESOURCES)}
    out |= {o[k] for o in (*catalog.CLAUDE_MODELS, *catalog.LLM_VENDORS, *catalog.DOUBAO_RESOURCES)
            for k in ("hint",) if o.get(k)}
    out |= {o[k] for o in catalog.CLAUDE_LEVELS for k in ("label", "desc")}
    out |= {p[k] for p in (*catalog.PLUGINS, *catalog.ALWAYS_ON_PLUGINS) for k in ("label", "desc")}
    for s in catalog.PLUGIN_SETTINGS.values():
        out |= {s[k] for k in ("note", "legacy_note") if s.get(k)}
        out |= {f[k] for f in s["fields"] for k in ("label", "hint") if f.get(k)}
    out |= set(catalog.EMOTION_LABELS.values()) | set(pages.SHERPA_MODEL_LABELS.values())
    out |= {o["label"] for o in reply_language.OPTIONS}
    # 若哪個表格讀空了（改名、搬位置），這裏會失敗，而不是靜靜少收
    assert {"所在地", "大笑", "查日期", "只读", "读文件", "2.0 小时版", "最快，适合语音"} <= out
    return out


def not_ui():
    from core.agent import reply_language
    return set(reply_language.RULES.values()) | {v for p in reply_language.PHRASES.values() for v in p.values()}


def endonym_keys():
    from core.agent import reply_language
    return {o["label"] for o in reply_language.OPTIONS}


def _walk_display(value, out, field=None):
    if isinstance(value, dict):
        if isinstance(value.get("msg_key"), str):
            out.add(value["msg_key"])
            for p in (value.get("msg_params") or {}).values():
                _walk_display(p, out, "param")
            return
        for k, v in value.items():
            _walk_display(v, out, k)
    elif isinstance(value, list):
        for v in value:
            _walk_display(v, out, field)
    elif isinstance(value, str) and field in DISPLAY | {"warnings"}:
        out.add(value)


from tests.admin.test_admin_pipeline import API_YAML, CLI_YAML   # ClaudeCLI（type: claude_cli）；API 模型＋function_call

# load_merged() 把 custom 疊在 config.yaml 之上。config.yaml 裏沒有 ClaudeCLI（它只在安裝範本裏），
# 所以 Claude CLI 那一份要用 CLI_YAML；安裝範本就是用戶的 data/.config.yaml 的起點。
CONFIGS = {
    "template": (SERVER.parents[1] / "scripts" / "config.template.yaml").read_text(encoding="utf-8"),
    "claude_cli": CLI_YAML,
    "edge_api": "selected_module: {TTS: EdgeTTS, LLM: DeepSeekLLM}\n",   # config.yaml:814、:691
    "api_tools": API_YAML,
}
EXPECT_CLI = {"template": None, "claude_cli": True, "edge_api": False, "api_tools": False}


def describe_all(tmp_path):
    """三份設定各自的 pipeline.describe()；確認 Claude CLI 分支真的走到了。"""
    out = {}
    for name, text in CONFIGS.items():
        path = tmp_path / f"{name}.yaml"; path.write_text(text)
        d = pipeline.describe(config_store.load_merged(custom_path=path))
        is_cli = any(s["id"] == "voice_rules" for s in d["prompt"]["segments"])
        if EXPECT_CLI[name] is not None:
            assert is_cli is EXPECT_CLI[name], name
        out[name] = d
    return out


def _runtime_values(tmp_path):
    out = set()
    for d in describe_all(tmp_path).values():
        _walk_display(d, out)
        out |= {v for v in d["prompt"]["var_labels"].values() if isinstance(v, str)}
    return out


@pytest.fixture(scope="module")
def dicts():
    return catalogs()


# 简体和繁体写法完全相同、所以不需要繁中条目的原文。测试列出缺少的条目时，逐条确认后才加进来。
SAME_IN_BOTH = {"女", "男", "日期", "星期", "表情列表"}


def sources(tmp_path, dicts):
    html = INDEX.read_text(encoding="utf-8")
    p = _Markup(); p.feed(html)
    found = p.out | _js_literals(html) | _python_literals() | _runtime_values(tmp_path) | _catalog_labels()
    existing = (set(dicts["UI_ZH_HANT"]) | set(dicts["UI_ZH_HANS"])) - not_ui()
    return {s for s in found | existing if _cjk(s)}


def test_every_source_string_has_chinese_and_english(tmp_path, dicts):
    src = sources(tmp_path, dicts)
    # 简繁同形的（「女」「日期」）不需要中文條目：繁中頁面直接顯示原文。逐條列出，每條都要確認兩種寫法真的相同
    no_zh = sorted(s for s in src if s not in dicts["UI_ZH_HANT"] and s not in dicts["UI_ZH_HANS"]
                   and s not in SAME_IN_BOTH)
    no_en = sorted(s for s in src if s not in dicts["UI_EN"])
    assert not no_zh, "繁中／简中字典缺少：\n" + "\n".join(no_zh)
    assert not no_en, "英文字典缺少：\n" + "\n".join(no_en)


def test_english_has_no_unknown_keys(tmp_path, dicts):
    extra = sorted(set(dicts["UI_EN"]) - sources(tmp_path, dicts))
    assert not extra, "英文字典有原文裏沒有的鍵：\n" + "\n".join(extra)


@pytest.mark.parametrize("name", ["UI_EN", "UI_ZH_HANT", "UI_ZH_HANS"])
def test_values_keep_placeholders_and_wake_word(dicts, name):
    for key, value in dicts[name].items():
        assert value.strip(), key
        assert set(PLACEHOLDER.findall(value)) == set(PLACEHOLDER.findall(key)), key
        if "小麦" in key:
            assert "小麦" in value, key
        if name == "UI_EN" and "小麦" not in key:
            shown = re.sub(r"<[^>]+>", "", value)
            if key in endonym_keys():
                # 只能保留鍵裏本來就有的本名（「日語 日本語」→「Japanese 日本語」），不能整句不翻
                assert all(ch in key for ch in shown if _cjk(ch)) and not _cjk(shown.split()[0]), key
            else:
                assert not _cjk(shown), key


def test_prompts_are_not_in_the_english_dictionary(dicts):
    assert not set(dicts["UI_EN"]) & not_ui()
```

表格名稱已按 #9 的 `catalog.py` 核對（`PLUGIN_SETTINGS` 存插件欄位，`PLUGINS` 只以 `settings` 指向它）。`SAME_IN_BOTH` 先只放已知的五個；測試列出新的简繁同形字（例如「大笑」「思考」「酷」「查日期」「模型」「上一代模型」）時，逐條確認兩種寫法相同再加入。

`describe_all()` 斷言 Claude CLI 分支有走到（`voice_rules` 段只在 CLI 分支出現），所以設定改壞時測試會失敗，不會靜靜少收一半原文。

UI_EN 的值不能含中文，但有些英文值會刻意保留中文名稱：「小麦」由喚醒詞規則處理；其他情況（例如 `韓語 한국어` 的值是 `Korean 한국어`，沒有中文）不應出現。若某一條確實必須保留中文（例如顯示中文語音名稱的範例），在測試裏另列一個明確的集合，不要放寬規則。

- [ ] **跑一次，得到缺少的清單**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin/test_i18n_catalog.py`
Expected：FAIL。`繁中／简中字典缺少` 列出 Task 2–6 新加的鍵和流程頁那些原本沒經過 `t()` 的句子；`英文字典缺少` 列出全部原文（約 1100 條）。

- [ ] **補繁中**

把 `繁中／简中字典缺少` 的每一條加進 `UI_ZH_HANT`，值用繁中書面語（跟現有條目同樣的用字：「設定」「網址」「伺服器」「預設」「支援」）。

- [ ] **寫英文字典**

把 `英文字典缺少` 的每一條加進 `en.js` 的 `UI_EN`。翻譯原則（spec §6.3：Claude 起草，維護者審閱）：

- 簡短、口語、跟現有介面同樣的語氣；按鈕用動詞開頭（「保存」→ `Save`）；
- 片段（以空格開頭或結尾，或只是半句的鍵）保留原有的前後空格，因為頁面把它們拼在數字或名稱旁邊；
- 含 HTML 的鍵保留同樣的標記和屬性，只翻譯文字；
- 中文標點換成英文標點（`，` → `, `、`：` → `: `、`（…）` → ` (…)`），全形引號「“…”」換成 `"…"`；
- 佔位符 `{名稱}` 原樣保留，可以換位置；
- 產品和協定名稱（Claude Code、OpenAI、ZenMux、EdgeTTS、MCP、OTA、Grok、sherpa-onnx）不翻譯；
- 簡繁兩種寫法的同一句（例如 `UI_ZH_HANT` 的简中鍵和 `UI_ZH_HANS` 的繁中鍵說的是同一件事）英文值一致。

條目多，分幾次寫；每寫一批就跑一次完整性測試，看剩下多少。

- [ ] **拿掉 Task 6 的 xfail 標記**

Task 6 那個「切換失敗的回應在英文頁面沒有中文」的 HTTP 測試標了 `@pytest.mark.xfail(strict=True, …)`。英文字典寫完後它會通過，`strict=True` 令它變成失敗：拿掉標記，確認它通過。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider tests/admin`
Expected：全部通過（基準的環境失敗除外）。

```bash
git add main/xiaozhi-server/tests/admin/test_i18n_backend.py main/xiaozhi-server/core/admin/static/i18n/en.js main/xiaozhi-server/core/admin/static/i18n/zh-Hant.js \
  main/xiaozhi-server/tests/admin/test_i18n_catalog.py
git commit -m "Admin English dictionary; dictionary completeness and wake-word tests"
```

en.js 單檔超過 litmus 的大小上限時（單檔加權 2000 行），litmus 會以 exit 2 停下。en.js 是一個不能拆的資料檔：照主 repo 處理大檔的做法，只對這次 commit 設 `LITMUS_MAX_WEIGHTED_LINES_SINGLE_FILE` 和 `LITMUS_MAX_TOTAL_LINES`（兩者都要），或把 `zh-Hant.js` 和測試放在前一個 commit、en.js 單獨一個 commit。

---

### Task 8: 英文介面的顯示測試

**Files:**
- Test: `tests/admin/test_i18n_backend.py`（第三部分）

**Interfaces:**
- Consumes: `i18n_node.render()`、`speech_settings.save()`、`mcp_settings`（儲存函式，名稱以 Task 4 讀到的為準）、`pipeline.describe()`。

spec §6.1 列出的英文顯示項目裏，屬於網關的四項：無效的 ASR 網址、缺少 API key、無效的 MCP 設定、流程頁裏填了數值的欄位。（「連不上更新伺服器」和系統層自檢的回復訊息屬於主 repo 的更新器，在更新器的計劃裏測試。）

- [ ] **測試**

```python
# 加在 tests/admin/test_i18n_backend.py
from tests.admin.i18n_node import has_chinese, render as render_js


def _cjk_free(s):
    return not has_chinese(s)   # 全形標點也算：英文頁面上不該出現（）、：


def _error_of(fn):
    with pytest.raises(UIError) as e:
        fn()
    return e.value.payload()


def test_speech_errors_show_in_english(tmp_path):
    path = tmp_path / "config.yaml"; path.write_text("{}\n")
    merged = config_store.load_merged(custom_path=path)
    bad_url = _error_of(lambda: speech_settings.save("ASR", {"api_key": "k", "api_url": "not a url"}, merged, path))
    no_key = _error_of(lambda: speech_settings.save("ASR", {"api_key": ""}, merged, path))
    out = render_js([bad_url, no_key], "en")
    assert all(_cjk_free(s) and s for s in out), out


def test_mcp_error_shows_in_english(tmp_path):
    bad = _error_of(lambda: mcp_settings.validate_server({"url": "ftp://x"}))
    (out,) = render_js([bad], "en")
    assert _cjk_free(out) and out, out


# 用户的值和设备认的口令：英文页面必须原样保留
USER_VALUES = ("接着上次聊", "好的，我看一下", "停下", "继续")


def test_pipeline_values_show_in_english(tmp_path):
    from tests.admin.test_i18n_catalog import describe_all
    for name, d in describe_all(tmp_path).items():
        values = [s[k] for s in d["flow"]["stages"] for k in ("title", "value", "hint")]
        values += [t[k] for t in d["flow"]["tips"] for k in ("title", "say", "result")]
        values += [s[k] for s in d["prompt"]["segments"] for k in ("title", "when", "note")] + d["prompt"]["warnings"]
        values.append(d["prompt"]["llm"])
        out = render_js(values, "en")
        leftover = []
        for o in out:
            for v in USER_VALUES:
                o = o.replace(v, "")
            if not _cjk_free(o):
                leftover.append(o)
        assert not leftover, (name, leftover)


def test_resume_keyword_stays_chinese_and_voice_name_is_translated(tmp_path):
    from tests.admin.test_i18n_catalog import describe_all
    d = describe_all(tmp_path)
    tip = next(t for t in d["claude_cli"]["flow"]["tips"] if t["title"] == "接着上次聊")
    (result,) = render_js([tip["result"]], "en")
    assert "接着上次聊" in result                       # the device listens for these characters
    tts = next(s for s in d["edge_api"]["flow"]["stages"] if s["id"] == "tts")
    (value,) = render_js([tts["value"]], "en")
    assert value.startswith("EdgeTTS · ") and _cjk_free(value), value
    long_task = next(t for t in d["claude_cli"]["flow"]["tips"] if t["title"] == "长任务")
    (result,) = render_js([long_task["result"]], "en")
    assert "停下" in result or "继续" in result         # spoken commands are kept as the device hears them


def test_update_error_shows_in_english():
    from core.admin import updater
    e = updater.UpdateError("已经在更新了，请等它结束")
    (out,) = render_js([e.payload()], "en")
    assert out and _cjk_free(out), out


@pytest.mark.asyncio
async def test_doubao_connection_error_shows_in_english(monkeypatch):
    from core.providers.asr import doubao_stream

    def refuse(*args, **kwargs):
        raise OSError("refused")

    # check_connection() 的網址寫死在 ASRProvider 裏（wss://openspeech.bytedance.com/…），不能靠設定改，
    # 所以換掉連線函式：測試不連外網、結果固定
    monkeypatch.setattr(doubao_stream.websockets, "connect", refuse)
    result = await doubao_stream.check_connection(DOUBAO_CONFIG, timeout=1)
    m = result["error_msg"]
    assert m["msg_key"].startswith("连不上豆包识别服务")
    detail = str(m["msg_params"].get("detail", ""))
    (out,) = render_js([m], "en")
    assert out and _cjk_free(out.replace(detail, "")), out
```

Task 6 答應的四個案例（守門測試看不到這些路徑）：

```python
def _en(m):
    (out,) = render_js([m], "en")
    return out


def test_plugin_field_error_names_the_field_in_english(tmp_path):
    from core.admin import plugin_settings
    path = tmp_path / "c.yaml"; path.write_text("{}\n")
    merged = config_store.load_merged(custom_path=path)
    out = _en(_error_of(lambda: plugin_settings._values("get_weather", {"location": "a\nb"}, merged)))
    assert _cjk_free(out) and out.lower().startswith("location"), out    # 「所在地」經 label() 翻成英文


def test_duplicate_call_name_error_in_english(tmp_path):
    from core.admin import pages
    path = tmp_path / "c.yaml"; path.write_text(CLI_YAML)
    merged = config_store.load_merged(custom_path=path)
    out = _en(_error_of(lambda: pages.save_call_names(DUPLICATE_ALIAS_PAYLOAD, merged, path)))
    assert _cjk_free(out.replace("小克", "")), out     # 稱呼是用戶的值，其餘（模型標籤）要是英文


def test_plugin_errors_in_english():
    from plugins_func.functions.get_weather import WeatherError
    from plugins_func.functions.web_search import SearchError
    for e in (SearchError("还没有填写 API Key"), WeatherError("没找到「{name}」这个地方", name="Atlantis")):
        out = _en(e.payload())
        assert out and _cjk_free(out), out


def test_short_key_hint_in_english():
    from core.admin.config_store import masked_fields
    short, long = masked_fields("key_hint", "abc"), masked_fields("key_hint", "sk-" + "x" * 30)
    assert _cjk_free(render_js([short["key_hint_msg"]], "en")[0])
    assert "key_hint_msg" not in long and long["key_hint"].startswith("sk-x")
```

`from tests.admin.test_admin_pipeline import CLI_YAML` 加到檔案開頭。`DUPLICATE_ALIAS_PAYLOAD` 是讓兩個模型用同一個稱呼「小克」的 `save_call_names()` 請求內容：寫測試前讀 `pages.py:880–910`，按它讀取的欄位寫，讓它走到「称呼“{alias}”同时给了 {taken} 和 {label}，只能给一个模型」那一句。`plugins_func.functions` 在 import 時需要 `data/.config.yaml`（Task 1 已建立）。

`check_connection` 的簽名是 `async def check_connection(config: dict, timeout: float = 10)`（`doubao_stream.py:496`）。`DOUBAO_CONFIG` 是一份能通過它開頭的設定檢查、走到連線那一步的最小設定（`appid`、`access_token` 填假值）：寫測試前讀第 496–526 行，按它檢查的欄位填。若 `websockets.connect` 是以別的名稱匯入的（例如 `from websockets import connect`），monkeypatch 那個名稱。第三方的錯誤原文（`detail` 參數）斷言前先去掉。

`CLI_YAML` 的 `resume_keywords` 是 `[接着上次聊]`，跟字典裏的「接着上次聊」（tips 的 `title`）是同一個字串：第一項證明它作為參數時沒有被翻譯，作為標題時有。安裝範本和 `edge_api` 若含有其他中文的用戶值（喚醒詞、`exit_commands`），把它們加進 `USER_VALUES`，不要放寬斷言——測試要抓的是**我們的**句子沒翻譯，不是用戶的值。

`speech_settings.save()` 的參數（欄位名稱 `api_url` 或 `base_url`）和 MCP 的驗證函式名稱（`validate_server` 只是暫定）以 Task 4 讀到的程式碼為準，按實際名稱改寫，讓兩個例子分別觸發「Base URL 必须是完整的 HTTP(S) 网址…」「请填写 API Key」和「请使用 HTTP(S) 网址…」。

- [ ] **確認測試抓得到**

暫時把 `en.js` 裏「请填写 API Key」那一條刪掉，跑 `test_speech_errors_show_in_english`：必須失敗。還原後再跑：必須通過。

- [ ] **測試、litmus、commit**

Run: `.venv/bin/python -m pytest -q -p no:cacheprovider`
Expected：`5 failed` 只能是基準那 5 項，其餘全部通過；passed 的數目比基準多（新測試）。

```bash
git add main/xiaozhi-server/tests/admin/test_i18n_backend.py
git commit -m "Tests: speech, MCP and pipeline messages render in English"
```

---

### Task 9: 實機檢查和 merge

- [ ] **在瀏覽器檢查**

```bash
cd ~/src/oh-im-smart-gateway/main/xiaozhi-server && .venv/bin/python app.py
```

用英文瀏覽器（或在後台選 English）打開 `http://127.0.0.1:<admin 埠>/admin`，設定管理密碼後逐頁看一遍：狀態、大模型、語音識別、語音合成、MCP、插件、工作原理、更新。記下仍顯示中文的位置：

- 用戶的名稱和對話內容：正常；
- 「更新输出」裏的 `update.sh` 輸出：正常（不翻譯）；
- 其他：是遺漏。找出來源（HTML、`t()` 呼叫或後端），補上字典或改用 `msg()`，並在 Task 7 的原文來源裏確認為甚麼沒有抓到；若是來源規則的缺口，補上規則再補字典。

再切換到繁體中文，確認 Task 4–6 改成简中 key 的驗證錯誤顯示為繁中。

- [ ] **Merge 回 `main` 並推送**

`main` 受保護、不能 force-push，推錯了只能用 revert commit 補救，所以推送以測試結果為條件：失敗的測試必須正好是 Task 1 記下的那 5 個，不多不少，而且沒有收集錯誤。

```bash
( set -e
  cd ~/src/oh-im-smart-gateway
  git checkout -q main
  git merge --no-ff -m "Merge feat/en-and-urls: English admin, keyed backend messages, ohimsmart URLs" feat/en-and-urls
  cd main/xiaozhi-server
  rc=0; .venv/bin/python -m pytest -q -rfE -p no:cacheprovider > ~/src/gw-final.log 2>&1 || rc=$?
  # pytest：1 = 有測試失敗（預期的 5 個），其他非 0 = 收集錯誤、中斷、內部錯誤
  [ "$rc" -eq 1 ] || { echo "pytest exit $rc"; exit 1; }
  # not `! grep`: set -e ignores a negated command
  if grep -q -E '^ERROR |errors? during collection|Interrupted|INTERNALERROR|KeyboardInterrupt' ~/src/gw-final.log; then
    echo "collection or internal error"; exit 1
  fi
  if tail -1 ~/src/gw-final.log | grep -q -E '[0-9]+ error'; then echo "errors in summary"; exit 1; fi
  grep '^FAILED' ~/src/gw-final.log | sed 's/ - .*//' | sort | diff ~/src/gw-baseline-failures.txt -
  tail -1 ~/src/gw-final.log
  cd ../..
  git push origin main )
```

Expected：`diff` 沒有輸出，最後一行是 `N passed, 5 failed, …`，推送成功。merge 失敗、pytest 的結束碼不是 1、有收集或內部錯誤、或 `diff` 有輸出時，整段在推送之前停下：修好再重跑，不要推送。

- [ ] **主 repo 的記錄**

在主 repo 的 work state 記下網關 `main` 的 commit：主 repo 映像計劃的 Task 8 用這個 commit 準備母機（`git merge-base --is-ancestor`），而且母機現有的 `HEAD` 是上游 `4b6eec4` 的後代，必須是新 `main` 的祖先：

```bash
git -C ~/src/oh-im-smart-gateway merge-base --is-ancestor 4b6eec40 main && echo ancestor-ok
```

同時記下要交給映像計劃 Task 8 的出處行：網關 checkout 裏仍含上游網址的每一行（`README.md`、`README.en.md` 第 10、13、14 行的徽章，`main/xiaozhi-server/plugins_func/functions/get_weather.py:28` 的 User-Agent），以 `git -C ~/src/oh-im-smart-gateway grep -n -E 'github(usercontent)?\.com[/:]justhalfbit' main --` 列出（`--` 不能省：repo 裏同時有 `main` 分支和 `main/` 目錄），原樣記進 work state，映像計劃 Task 8 據此加 `line` 條目。

---

## 實作記錄

已完成：網關 `main` = `2d067d94`（merge `feat/en-and-urls`，Task 2–8 共 9 個 commit），測試 765 passed、5 failed（正是基準的 5 個）、5 skipped。實作時跟上面的計劃不同的地方：

- Task 3：`runtime.js` 不切換到字典是空的語言（退回简中，`UII18n.applied` 是實際用的語言）；語言選單的 English 選項跟 `en.js` 的內容一起在 Task 7 加上。
- Task 5：`_join` 對半折疊；配置裏的名稱經 `_raw()` 原樣顯示（見上）。「嗨」寫在範本裏，英文是 “Hi”（呼名辨識也認 hi/hey）。
- Task 6：分兩個 commit。`asr_label()`、`_claude_version()` 回傳 msg 物件；`core/agent/llm_router.py` 加 `model_label_msg()`；頁面多一個 `joinList()`，跟 `_join` 一樣對半折疊。
- Task 7：`GrokBotError` 也改為 `KeyedError`（`grokbot_client.py` 加進 `EXTRA`），`core/admin/__init__.py` 改為在函式裏 import `AdminHandler` 以避免循環 import；`_python_literals` 也收 `_check(...)` 的常數；刪掉 335 條不再用到的字典鍵；`en.js` 共 938 條。
- Task 8：`USER_VALUES` 只留測試實際碰到的 8 個用戶值。
- Task 9：瀏覽器檢查以 headless Chrome 逐頁讀文字：英文頁面只剩用戶的值和語言自稱，繁中頁面沒有简中介面文字。

## 不在這份計劃裏

- 客戶端（#4 和英文）：另一份計劃。
- 主 repo 的更新器訊息 key、kiosk 語言選擇、bootstrap、README 教學：各自的計劃。
- `scripts/update.sh` 的輸出翻譯：v1 不做（spec §10）。
- 天氣外掛的 User-Agent 和 README 徽章：出處標示，不改。
