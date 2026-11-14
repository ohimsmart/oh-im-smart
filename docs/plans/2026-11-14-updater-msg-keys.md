# 更新器訊息鍵 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 更新器（`update/thinksmart-update`）交給頁面的每一句話都帶 `msg_key`／`msg_params`，job 帶布林值 `reboot`，`check_error` 旁邊有 `check_error_msg`；客戶端的字典收齊這些鍵，英文介面顯示英文（spec §6.1）。

**Spec:** `docs/specs/2026-11-09-oh-im-smart-v1-design.md` §6.1「翻譯的邊界」、「重新開機提示」、「測試」。

**Architecture:** 更新器加兩個小函式：`msg(key, **params)` 回傳 `{msg_key, msg_params}`，`msg_text(m)` 把它填成中文。`Fail(key, **params)` 帶同樣的訊息，`str(e)` 仍是中文。`set_job` 改收 `msg()`：job 的 `message` 仍是原本的中文（舊頁面照舊顯示，一個字都不變），另外加上 `msg_key`、`msg_params` 和 `reboot`。所有句子拼接改成整句範本；巢狀的原因（`{why}`）本身也是 `msg()`。一個 AST 測試保證更新器裏的每段中文都是 `msg()`／`Fail()` 的字面值鍵、佔位符跟參數一致，並跟 `update/msg_keys.json` 完全相同；客戶端的 `tests/updater_keys.json` 是它的副本。`reboot` 只看這一次的請求：從 `run()` 傳進 `install()`、記在客戶端的 pending 紀錄，不讀 `st['system']['reboot']` 這個不會清掉的舊欄位。

**Tech Stack:** Python 3（只用標準函式庫）、pytest（`uv run --no-project --with pytest`）、node（測試裏執行歡迎頁和客戶端頁面的函式）。

**Global Constraints:**
- 這是 v1 七份計劃中的第 2 份。其餘：映像打包（第 1 份，已完成）、kiosk 語言選擇、客戶端英文（已完成）、網關英文和網址（已完成）、bootstrap `prepare.sh`、教學和映像 Release。
- **舊欄位一字不變：** job 的 `message` 和 `check_error` 的中文跟改動前完全相同。驗收方式：現有測試裏對 `message`、`check_error` 的斷言一行都不改。測試替身（stub）可以改成新的函式簽名或 `msg()`，斷言不能改。
- **舊紀錄要能讀：** 安裝這個新更新器的系統層更新，是由**舊的**更新器執行的；所以新程式碼讀到的 job、`pending.json`、`system-pending.json` 都可能沒有新欄位，一律用 `.get(…, 預設值)`。頁面讀 `job.reboot` 時，沒有這個欄位就退回比對中文訊息（客戶端已經這樣做，歡迎頁在 Task 3 跟上）。
- **鍵是整句的简中範本，結尾不加「。」**：客戶端頁面會在後面接「。可以再试一次」。範本裏的參數值是純文字（版本號、檔名、套件名稱、第三方函式庫的錯誤，照原樣顯示）或另一個 `msg()`（頁面先遞迴翻譯）。
- **英文的巢狀子句用小寫開頭：** 只出現在別的句子裏的鍵（原因、`断电或重启`、`系统层收尾脚本出错` 這類），英文寫成小寫開頭的子句，外層範本把它放在冒號或括號後面。例外：`安装出错：{error}` 和其他 `Fail` 的鍵既是單獨的句子，也可能出現在 `没装成功（{why}）` 裏；它們保留大寫開頭（`installation failed (Installation error: …)`），因為只有一個鍵、中文又不能改。
- **系統層 `VERSION` 不改：** 目前 0.2.1，留給「教學和映像 Release」計劃一次改成 1.0.0（spec §5.2）。
- **`UPDATER_VERSION` 從 2 改成 3：** 客戶端 Release 帶一份本 repo 的更新器（`make-release.py --system` 放進 `deploy/updater/`），客戶端的 `deploy/bootstrap-updater` 只在它的 `UPDATER_VERSION` 比裝置上的大時才換上。改成 3，系統層更新裝不了（缺套件）而只裝客戶端的裝置也會拿到帶鍵的更新器。除了 `selftest` 和 `bootstrap-updater`，沒有程式讀這個數字。
- 主 repo 的改動在分支 `feat/updater-msg-keys`，客戶端的改動在分支 `feat/updater-keys`；merge 到 `main` 只用 merge commit（`git merge --no-ff`），不 rebase、不 force-push。
- 測試指令不接 `| tail`：管線的結束碼是 `tail` 的，會蓋掉失敗。
- 這台機器的全域 git 設定有 `tag.gpgsign=true`，`test_make_release_carries_the_system_layer` 在臨時 repo 打 tag 時會因此失敗（跟本計劃無關）。主 repo 的測試一律以 `GIT_CONFIG_GLOBAL=/dev/null` 執行。

---

## 背景：基準

- 主 repo `main` = `1e1f5ae`。`GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk/test_kiosk_commands.py`：54 passed。
- 客戶端 `ohimsmart/oh-im-smart-client` 的 `main` = `2f1df0e`：`.venv/bin/python -m pytest -q -p no:cacheprovider` 179 passed，`node --test tests/*.cjs` 14 passed。
- 更新器裏的中文字串全部是給頁面的訊息（`ast` 掃描確認過，沒有別的用途），所以「每段中文都必須是 `msg()`／`Fail()` 的鍵」可以當成測試規則。

## 跨計劃的約定

1. **客戶端已經在讀的欄位**（客戶端計劃，`web/v2/app.js`）：`updMsg(job)` 有 `job.msg_key` 時用 `UII18n.text(job)`，否則用 `job.message`；`needsReboot(job)` 先看布林值 `job.reboot`，沒有才比對「重启设备后生效」；檢查錯誤用 `UII18n.text(u.check_error_msg || u.check_error)`。客戶端的 `thinksmart_client/update.py` 把 `status.json` 原樣交給頁面，不需要改。
2. **鍵的清單只有一份：** `update/msg_keys.json`（主 repo），由 `update/test_msg_keys.py` 核對。客戶端 `tests/updater_keys.json` 是它的副本（Task 4），客戶端的字典完整性測試把它算入原文。kiosk 語言選擇計劃的歡迎頁字典也從 `update/msg_keys.json` 取鍵。兩個 repo 的測試各自獨立，看不到對方，所以副本的同步是手動步驟：寫在 `update/README.md`（Task 3），「教學和映像 Release」計劃發佈前用 `diff` 比對兩份。
3. **歡迎頁：** 本計劃把「要不要重新開機」改成讀 `job.reboot`，失敗的結果也會提醒重新開機（Task 3）。歡迎頁還沒有 `t()`，用 `msg_key` 翻譯訊息留給 kiosk 語言選擇計劃。在那之前，歡迎頁照舊顯示中文的 `job.message`。
4. **失敗也要提醒重新開機：** 系統層裝好（要重新開機）、客戶端接着失敗或退回時，job 帶 `reboot: true`，但它的訊息講的是客戶端的錯誤。兩個頁面在失敗的訊息後面接一句「系统层的部分改动重启设备后生效」（客戶端 Task 4、歡迎頁 Task 3）。這一句是頁面自己的文字，不是更新器的鍵。

## 訊息的鍵

共 53 個鍵。標「已有」的 4 個已經在客戶端字典裏（頁面自己的進度文字），不重複加入。英文用彎引號 `’`，跟客戶端現有字典一致；繁中用「重啟裝置」「閘道器」「映像」，跟客戶端現有字典一致。

| 鍵（简中範本） | 繁中 | 英文 |
|---|---|---|
| `更新服务器返回的内容太大` | 更新伺服器回傳的內容太大 | The update server sent back too much data |
| `没有配置更新地址` | 沒有設定更新位址 | No update address is set |
| `更新地址必须是 https` | 更新位址必須是 https | The update address must use https |
| `更新服务器上的版本信息不对，已忽略` | 更新伺服器上的版本資訊不對，已略過 | The version information on the update server is wrong and was ignored |
| `连不上更新服务器` | 連不上更新伺服器 | Can’t reach the update server |
| `下载的文件比清单里写的大` | 下載的檔案比清單裏寫的大 | The downloaded file is larger than the manifest says |
| `下载的文件校验不对（可能被改过或没下完整），没有安装` | 下載的檔案校驗不對（可能被改過或沒下載完整），沒有安裝 | The downloaded file failed its checksum (it may have been altered or be incomplete); nothing was installed |
| `下载失败：网络断了或者更新服务器没有响应，请稍后再试` | 下載失敗：網路斷了或者更新伺服器沒有回應，請稍後再試 | Download failed: the network dropped or the update server did not respond. Try again later |
| `更新服务器上的版本已经变成 {version}，请重新点更新` | 更新伺服器上的版本已經變成 {version}，請重新點更新 | The update server now has version {version}; tap Update again |
| `{version} 不比现在的 {current} 新` | {version} 不比現在的 {current} 新 | {version} is not newer than the current {current} |
| `存储空间不够，没有安装` | 儲存空間不夠，沒有安裝 | Not enough storage space; nothing was installed |
| `系统层更新包里没有文件表` | 系統層更新包裏沒有檔案表 | The system layer package has no file table |
| `系统层文件表有一行看不懂：{line}` | 系統層檔案表有一行看不懂：{line} | The system layer file table has a line that can’t be read: {line} |
| `系统层文件表有一行不对：{line}` | 系統層檔案表有一行不對：{line} | The system layer file table has an invalid line: {line} |
| `系统层文件表是空的` | 系統層檔案表是空的 | The system layer file table is empty |
| `系统层收尾脚本出错` | 系統層收尾指令碼出錯 | the system layer’s finishing script failed |
| `更新服务器上的系统层版本变了，请重新点更新` | 更新伺服器上的系統層版本變了，請重新點更新 | The system layer version on the update server changed; tap Update again |
| `系统层 {version} 不比现在的 {current} 新` | 系統層 {version} 不比現在的 {current} 新 | System layer {version} is not newer than the current {current} |
| `系统层 {version} 需要的软件包没装（{packages}），要重刷镜像才能用` | 系統層 {version} 需要的軟體套件沒裝（{packages}），要重刷映像才能用 | System layer {version} needs packages that are not installed ({packages}); flash a newer image to use it |
| `系统层更新包和清单对不上，没有安装` | 系統層更新包和清單對不上，沒有安裝 | The system layer package does not match the manifest; nothing was installed |
| `正在准备`（已有） | — | — |
| `正在下载`（已有） | — | — |
| `正在安装`（已有） | — | — |
| `正在重启并自检`（已有） | — | — |
| `正在重启相关服务并自检` | 正在重啟相關服務並自檢 | Restarting the affected services and self-testing |
| `上次更新被中断，正在重新自检` | 上次更新被中斷，正在重新自檢 | The last update was interrupted; self-testing again |
| `已更新到 {version}` | 已更新到 {version} | Updated to {version} |
| `系统层已更新到 {version}` | 系統層已更新到 {version} | System layer updated to {version} |
| `系统层已更新到 {version}，部分改动重启设备后生效` | 系統層已更新到 {version}，部分改動重啟裝置後生效 | System layer updated to {version}; some changes take effect after a restart |
| `已更新到 系统层 {system} · 客户端 {client}` | 已更新到 系統層 {system} · 客戶端 {client} | Updated to system layer {system} · client {client} |
| `已更新到 系统层 {system} · 客户端 {client}，部分改动重启设备后生效` | 已更新到 系統層 {system} · 客戶端 {client}，部分改動重啟裝置後生效 | Updated to system layer {system} · client {client}; some changes take effect after a restart |
| `安装出错：{error}` | 安裝出錯：{error} | Installation error: {error} |
| `{why}，也没有可以退回的版本` | {why}，也沒有可以退回的版本 | No earlier version to go back to: {why} |
| `{why}，正在退回 {old}` | {why}，正在退回 {old} | Going back to {old}: {why} |
| `{version} 自检没通过（{why}），已退回 {old}` | {version} 自檢沒通過（{why}），已退回 {old} | {version} failed its self-test ({why}); went back to {old} |
| `{version} 自检没通过（{why}），已退回 {old}，但退回后客户端也没正常启动，请重启设备` | {version} 自檢沒通過（{why}），已退回 {old}，但退回後客戶端也沒正常啟動，請重啟裝置 | {version} failed its self-test ({why}); went back to {old}, but the client did not start properly after that either. Restart the device |
| `系统层 {version} {why}，已退回 {old}` | 系統層 {version} {why}，已退回 {old} | System layer {version}: {why}; went back to {old} |
| `系统层 {version} {why}，已退回 {old}，但退回后还有服务没正常启动，请重启设备` | 系統層 {version} {why}，已退回 {old}，但退回後還有服務沒正常啟動，請重啟裝置 | System layer {version}: {why}; went back to {old}, but some services still did not start properly. Restart the device |
| `没装成功（{why}）` | 沒裝成功（{why}） | installation failed ({why}) |
| `上次系统层更新被中断（{why}）` | 上次系統層更新被中斷（{why}） | the last system layer update was interrupted ({why}) |
| `上次更新被中断（{why}），没有改动` | 上次更新被中斷（{why}），沒有改動 | The last update was interrupted ({why}); nothing was changed |
| `断电或重启` | 斷電或重啟 | power cut or restart |
| `下载太慢超时或出错` | 下載太慢逾時或出錯 | the download was too slow, timed out or failed |
| `检查更新出错` | 檢查更新出錯 | Checking for updates failed |
| `新版本 {seconds} 秒内没有启动起来` | 新版本 {seconds} 秒內沒有啟動起來 | the new version did not start within {seconds} seconds |
| `新版本没有启动起来` | 新版本沒有啟動起來 | the new version did not start |
| `新版本打不开麦克风或扬声器` | 新版本打不開麥克風或揚聲器 | the new version could not open the microphone or speaker |
| `新版本连不上小智网关` | 新版本連不上小智閘道器 | the new version can’t reach the Xiaozhi gateway |
| `屏幕界面没有启动起来` | 螢幕介面沒有啟動起來 | the screen interface did not start |
| `麦克风或扬声器没有恢复` | 麥克風或揚聲器沒有恢復 | the microphone or speaker did not come back |
| `新的更新服务启动不了` | 新的更新服務啟動不了 | the new update service would not start |
| `蓝牙服务没有启动起来` | 藍牙服務沒有啟動起來 | the Bluetooth service did not start |
| `{unit} 没有正常运行` | {unit} 沒有正常執行 | {unit} is not running properly |

範例（Task 1 的黃金測試和 Task 4 的英文測試共用）：系統層 0.2.0 自檢時螢幕介面沒起來、退回 0.1.0，job 是

```json
{"msg_key": "系统层 {version} {why}，已退回 {old}",
 "msg_params": {"version": "0.2.0", "old": "0.1.0",
                "why": {"msg_key": "没装成功（{why}）",
                        "msg_params": {"why": {"msg_key": "屏幕界面没有启动起来", "msg_params": {}}}}}}
```

`message` 是 `系统层 0.2.0 没装成功（屏幕界面没有启动起来），已退回 0.1.0`（跟現在相同），繁中是 `系統層 0.2.0 沒裝成功（螢幕介面沒有啟動起來），已退回 0.1.0`，英文是 `System layer 0.2.0: installation failed (the screen interface did not start); went back to 0.1.0`。

## File Structure

| 檔案 | 改動 |
|---|---|
| `update/thinksmart-update` | `msg()`、`msg_text()`、`Fail(key, **params)`；`set_job` 收 `msg()`、帶 `reboot`；所有訊息改成整句範本；`check_error_msg`；`reboot` 的傳遞和寫入次序 |
| `update/test_msg_keys.py` | 新檔：AST 收集器和它的自我測試；鍵跟 `msg_keys.json` 一致 |
| `update/msg_keys.json` | 新檔：53 個鍵，排序過的 JSON 陣列（不裝到裝置上：`image/system-files.txt` 沒列它） |
| `update/test_system_layer.py` | 黃金測試、`reboot` 的四種情況和兩個反例；測試替身跟上新簽名 |
| `update/test_thinksmart_update.py` | `check_error_msg`；客戶端 job 帶 `reboot` |
| `update/README.md` | 一行：job 和 `check_error_msg` 的欄位 |
| `kiosk/welcome.html` | `needsReboot(job)` 讀 `job.reboot`，舊更新器退回比對訊息；`updFail(job)` 在失敗的結果後面提醒重新開機 |
| `kiosk/test_welcome_update.py` | 新檔：用 node 執行 `needsReboot`、`updFail`，並檢查整個頁面腳本能解析 |
| 客戶端 `tests/updater_keys.json` | `update/msg_keys.json` 的副本 |
| 客戶端 `web/v2/app.js` | `updFail(job)`：失敗的結果後面提醒重新開機 |
| 客戶端 `web/zh-Hant.js`、`web/en.js` | 50 個新條目（49 個更新器的鍵、1 句頁面的提醒） |
| 客戶端 `tests/test_i18n_page.cjs` | 黃金 job 和「连不上更新服务器」以英文、繁中顯示 |

---

### Task 1: 訊息鍵、`Fail(key, **params)`、`check_error_msg`

**Files:**
- Modify: `update/thinksmart-update`
- Create: `update/test_msg_keys.py`、`update/msg_keys.json`
- Modify: `update/test_system_layer.py`、`update/test_thinksmart_update.py`

**Interfaces:**
- Produces: `msg(key, **params) -> {'msg_key', 'msg_params'}`；`msg_text(m) -> str`；`Fail(key, **params)`，`e.msg` 是它的 `msg()`；`set_job(st, state, version, message, progress=None, component='client')`，`message` 是 `msg()`；job 多了 `msg_key`、`msg_params`；status 多了 `check_error_msg`；`self_test`、`system_self_test` 失敗時回傳 `(False, msg())`；`system_rollback(st, pending, why, seconds)` 和 `recover(conf, seconds, why)` 的 `why` 是 `msg()`。

- [ ] **分支**

```bash
cd /home/chris/Projects/ohimsmart && git switch -c feat/updater-msg-keys main
```

- [ ] **新的函式，取代 `class Fail`**（第 106–107 行）

```python
def msg(key, **params):
    """A message for the pages (spec §6.1): its Simplified Chinese template, which is also the key the
    pages translate, and the values of its {placeholders}: plain text (a version, a file name, a
    library's error, shown as it is) or another msg()."""
    return {'msg_key': key, 'msg_params': params}


def msg_text(m):
    """A msg() in Chinese: the job's `message`, which older pages show."""
    return m['msg_key'].format_map({k: msg_text(v) if isinstance(v, dict) else v
                                    for k, v in m['msg_params'].items()})


class Fail(Exception):
    """An error to show on the page, keyed like msg(): Fail(key, **params). str() is its Chinese."""

    def __init__(self, key, **params):
        self.msg = {'msg_key': key, 'msg_params': params}
        super().__init__(msg_text(self.msg))
```

- [ ] **`set_job`**（第 158–162 行）

```python
def set_job(st, state, version, message, progress=None, component='client'):
    """message: a msg(). The job keeps it as Chinese text in `message` (older pages show that) and as
    msg_key/msg_params (the pages translate those)."""
    st['job'] = {'state': state, 'version': version, 'message': msg_text(message), **message,
                 'progress': progress, 'time': int(time.time()), 'component': component}
    save_status(st)
    log(f'[{component} {state}] {version} {st["job"]["message"]}')
```

- [ ] **其餘的訊息**：每一處照下表改；表上沒有的 `raise Fail('…')`（單一字面值、沒有參數）不用改。

| 位置 | 改成 |
|---|---|
| `download()` 進度（第 309 行） | `job = st.get('job') or {}` 之後 `set_job(st, 'downloading', version, msg('正在下载'), (done_before + got) / total, job.get('component', 'client'))` |
| `self_test()` 四個失敗原因 | `msg('新版本 {seconds} 秒内没有启动起来', seconds=seconds)`、`msg('新版本没有启动起来')`、`msg('新版本打不开麦克风或扬声器')`、`msg('新版本连不上小智网关')`；docstring 寫明 why 是 `msg()` |
| `install()` 四個進度 | `msg('正在准备')`、`msg('正在下载')`（進度 0）、`msg('正在安装')`、`msg('正在重启并自检')` |
| `install()` 版本變了 | `raise Fail('更新服务器上的版本已经变成 {version}，请重新点更新', version=m['version'])` |
| `install()` 不比現在新 | `raise Fail('{version} 不比现在的 {current} 新', version=version, current=cur)` |
| `install()` 兩個 `except` | `set_job(st, 'failed', version, e.msg)`；`set_job(st, 'failed', version, msg('安装出错：{error}', error=str(e)))` |
| `read_table()` 兩行 | `raise Fail('系统层文件表有一行看不懂：{line}', line=line)`；`raise Fail('系统层文件表有一行不对：{line}', line=line)` |
| `SYS_CHECK_WHY` | 四個值各包一層 `msg('…')` |
| `system_self_test()` 最後一行 | `return False, SYS_CHECK_WHY.get(k) or msg('{unit} 没有正常运行', unit=k.partition(':')[2] or k)` |
| `install_system()` 進度 | `msg('正在准备')`、`msg('正在下载')`、`msg('正在安装')`、`msg('正在重启相关服务并自检')`，`component='system'` 不變 |
| `install_system()` 兩個 Fail | `raise Fail('系统层 {version} 不比现在的 {current} 新', version=version, current=cur)`；`raise Fail('系统层 {version} 需要的软件包没装（{packages}），要重刷镜像才能用', version=version, packages=' '.join(missing))` |
| `install_system()` 安裝前的兩個 `except` | `set_job(st, 'failed', version, e.msg, component='system')`；`… msg('安装出错：{error}', error=str(e)), component='system')` |
| `install_system()` 安裝後的兩個 `except` | `ok, why = False, e.msg`；`ok, why = False, msg('安装出错：{error}', error=str(e))` |
| `install_system()` 退回 | `return system_rollback(st, pending, msg('没装成功（{why}）', why=why), TEST_SECONDS)` |
| `recover()` 已裝好 | `set_job(st, 'done', spending['to'], msg('系统层已更新到 {version}', version=spending['to']), component='system')` |
| `recover()` 系統層中斷 | `system_rollback(st, spending, msg('上次系统层更新被中断（{why}）', why=why), seconds)` |
| `recover()` 重新自檢 | `set_job(st, 'testing', pending['to'], msg('上次更新被中断，正在重新自检'))` |
| `recover()` 標成失敗 | `set_job(st, 'failed', job.get('version'), msg('上次更新被中断（{why}），没有改动', why=why), component=job.get('component', 'client'))` |
| `boot()` | `return recover(conf, BOOT_TEST_SECONDS, msg('断电或重启'))` |
| `main()` | `recover(conf, TEST_SECONDS, msg('下载太慢超时或出错'))` |

`log('self-test failed:', why)` 和 `log('system self-test failed:', why)` 不改：記錄檔印出 dict 也沒關係。

docstring 是 AST 裏的字串常數，所以新加或改動的 docstring 不能有中文（`#` 註解可以），否則鍵的測試會報錯。

- [ ] **`UPDATER_VERSION`**（第 87 行）

```python
UPDATER_VERSION = 3        # 1: client only (the 20261101 image); 2: also the system layer; 3: keyed messages and job.reboot (spec §6.1).
```

第 88 行起的註解（`bootstrap-updater` 用這個數字決定要不要換上客戶端帶來的更新器）不改。

- [ ] **`finish()` 的三個結果**

```python
    if ok:
        PENDING.unlink(missing_ok=True)
        st['current'] = version
        st['available'] = None
        st.pop('failed', None)
        set_job(st, 'done', version, msg('已更新到 {version}', version=version))
        cleanup()
        return 0
    log('self-test failed:', why)
    if not old:
        set_job(st, 'failed', version, msg('{why}，也没有可以退回的版本', why=why))
        return 1
    set_job(st, 'rolling_back', version, msg('{why}，正在退回 {old}', why=why, old=old))
```

最後一段（`msg = f'{version} 自检没通过…'` 到 `set_job(st, 'rolled_back', …)`）改成：

```python
    if ok_old:
        done = msg('{version} 自检没通过（{why}），已退回 {old}', version=version, why=why, old=old)
    else:
        done = msg('{version} 自检没通过（{why}），已退回 {old}，但退回后客户端也没正常启动，请重启设备',
                   version=version, why=why, old=old)
    set_job(st, 'rolled_back', version, done)
    return 1
```

- [ ] **`system_rollback()`**

```python
def system_rollback(st, pending, why, seconds):
    """why: a msg(), a clause saying what went wrong (installation failed, or the last update was cut off)."""
    version, old = pending['to'], pending['from']
    set_job(st, 'rolling_back', version, msg('{why}，正在退回 {old}', why=why, old=old), component='system')
```

函式最後（`msg = f'系统层 {version} {why}…'` 到 `set_job(st, 'rolled_back', …)`）：

```python
    if ok:
        done = msg('系统层 {version} {why}，已退回 {old}', version=version, why=why, old=old)
    else:
        done = msg('系统层 {version} {why}，已退回 {old}，但退回后还有服务没正常启动，请重启设备',
                   version=version, why=why, old=old)
    set_job(st, 'rolled_back', version, done, component='system')
    return 1
```

- [ ] **`install_system()` 成功的結果**（`msg = f'系统层已更新到 {version}'` 到 `set_job(st, 'done', …)`）

```python
    if 'boot' in actions:
        done = msg('系统层已更新到 {version}，部分改动重启设备后生效', version=version)
    else:
        done = msg('系统层已更新到 {version}', version=version)
    set_job(st, 'done', version, done, component='system')
    return 0
```

- [ ] **`check()`**

```python
    try:
        m = fetch_manifest(conf, st)
        note_available(st, m, st['current'])
        note_system(st, m)
        st['check_error'] = st['check_error_msg'] = None
    except Fail as e:
        st['check_error'], st['check_error_msg'] = str(e), e.msg
    except Exception as e:  # noqa: BLE001
        log('check failed:', repr(e))
        st['check_error_msg'] = msg('检查更新出错')
        st['check_error'] = msg_text(st['check_error_msg'])
```

- [ ] **`run()` 兩者一起裝好**（`msg = f'已更新到 系统层 …'` 到 `set_job(st, 'done', client_v, msg)`；Task 2 再改成只看這次的 `reboot`）

```python
                st = load_status()
                if (st.get('system') or {}).get('reboot'):
                    done = msg('已更新到 系统层 {system} · 客户端 {client}，部分改动重启设备后生效',
                               system=system_v, client=client_v)
                else:
                    done = msg('已更新到 系统层 {system} · 客户端 {client}', system=system_v, client=client_v)
                set_job(st, 'done', client_v, done)
```

- [ ] **鍵的測試**：`update/test_msg_keys.py`

```python
"""Every message the updater gives the pages is a msg() key with its parameters (spec §6.1), and
msg_keys.json lists them all: the client's dictionaries (tests/updater_keys.json there is a copy) and
the welcome page's take their entries from it.

  GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q update
"""
import ast
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / 'thinksmart-update'
KEYS = HERE / 'msg_keys.json'
CJK = re.compile(r'[一-鿿]')
PLACEHOLDER = re.compile(r'\{(\w+)\}')


def collect(src):
    """(keys, problems): every msg()/Fail() key; a problem for each Chinese text that isn't one, each
    key that isn't a plain literal or whose {placeholders} differ from its parameters, and each
    set_job() given text instead of a message."""
    tree = ast.parse(src)
    keys, problems, key_nodes = set(), [], set()
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call) or not isinstance(n.func, ast.Name):
            continue
        if n.func.id in ('msg', 'Fail'):
            a = n.args[0] if n.args else None
            if len(n.args) != 1 or not (isinstance(a, ast.Constant) and isinstance(a.value, str)):
                problems.append(f'line {n.lineno}: {n.func.id}() needs one literal key')
                continue
            key_nodes.add(id(a))
            params = {k.arg for k in n.keywords}
            if params != set(PLACEHOLDER.findall(a.value)):
                problems.append(f'line {n.lineno}: {a.value!r} has params {sorted(map(str, params))}')
            keys.add(a.value)
        elif n.func.id == 'set_job':
            m = n.args[3] if len(n.args) > 3 else next((k.value for k in n.keywords if k.arg == 'message'), None)
            if m is None or isinstance(m, (ast.Constant, ast.JoinedStr, ast.BinOp)):
                problems.append(f'line {n.lineno}: set_job() needs a message, not text')
    for n in ast.walk(tree):
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and CJK.search(n.value) and id(n) not in key_nodes:
            problems.append(f'line {n.lineno}: Chinese text outside msg()/Fail(): {n.value!r}')
    return keys, problems


def test_every_message_is_a_literal_key_with_its_parameters():
    keys, problems = collect(SCRIPT.read_text(encoding='utf-8'))
    assert problems == []
    assert keys == set(json.loads(KEYS.read_text(encoding='utf-8')))


def test_the_key_list_is_sorted_and_no_key_ends_a_sentence():
    keys = json.loads(KEYS.read_text(encoding='utf-8'))
    assert keys == sorted(set(keys))
    assert [k for k in keys if k.endswith('。')] == []     # the client page adds 。可以再试一次


def test_the_collector_catches_what_it_must():
    good = '''
SYS = {'kiosk': msg('屏幕界面没有启动起来')}
def f(st, v, e):
    raise Fail('{version} 不比现在的 {current} 新', version=v, current='1')
    set_job(st, 'failed', v, msg('安装出错：{error}', error=str(e)))
    set_job(st, 'failed', v, e.msg)
'''
    bad = '''
def f(st, v, e, k):
    raise Fail(f'{v} 不比现在的新')
    set_job(st, 'failed', v, '安装出错：' + str(e))
    x = msg('已更新到 {version}', ver=v)
    y = msg(k)
'''
    assert collect(good) == ({'屏幕界面没有启动起来', '{version} 不比现在的 {current} 新', '安装出错：{error}'}, [])
    keys, problems = collect(bad)
    assert keys == {'已更新到 {version}'}
    assert [p.split(':')[0] for p in problems] == ['line 3', 'line 4', 'line 5', 'line 6', 'line 3', 'line 4']
```

- [ ] **產生 `update/msg_keys.json`**（之後改了訊息就重跑，測試會提醒）

```bash
cd /home/chris/Projects/ohimsmart/update && python3 -c "
import json, test_msg_keys as t
keys, problems = t.collect(t.SCRIPT.read_text(encoding='utf-8'))
assert not problems, problems
t.KEYS.write_text(json.dumps(sorted(keys), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print(len(keys))"
```

Expected：印出 `53`，清單跟上面「訊息的鍵」那張表相同。

- [ ] **測試替身和新的斷言**

`update/test_system_layer.py`：

```python
# test_failed_self_test_puts_every_file_back：失敗的自檢回傳真正的原因
    sysu.system_self_test = lambda actions, need_hub, seconds, need_audio=True: (len(sysu.effects) > 1, sysu.SYS_CHECK_WHY['kiosk'])
# 同一個測試，在現有的斷言之後加上：
    assert {k: st['job'][k] for k in ('msg_key', 'msg_params')} == {
        'msg_key': '系统层 {version} {why}，已退回 {old}',
        'msg_params': {'version': '0.2.0', 'old': '0.1.0',
                       'why': {'msg_key': '没装成功（{why}）',
                               'msg_params': {'why': {'msg_key': '屏幕界面没有启动起来', 'msg_params': {}}}}}}
    assert st['job']['message'] == '系统层 0.2.0 没装成功（屏幕界面没有启动起来），已退回 0.1.0'

# test_one_tap_for_both_reports_both：替身用 msg()
    sysu.install_system = lambda conf, v: (sysu.set_job(sysu.load_status(), 'done', v,
                                                        sysu.msg('系统层已更新到 {version}', version=v),
                                                        component='system'), 0)[1]
    sysu.install = lambda conf, v: (sysu.set_job(sysu.load_status(), 'done', v,
                                                 sysu.msg('已更新到 {version}', version=v)), 0)[1]
```

`test_a_damaged_backup_copy_is_not_restored` 的替身同樣改成回傳 `sysu.SYS_CHECK_WHY['kiosk']`。

`update/test_thinksmart_update.py`：

```python
# test_killed_during_self_test_rolls_back_if_it_fails：替身回傳 msg()
    tu.self_test = lambda version, need_hub, s: (version == '1.1.0', tu.msg('新版本没有启动起来'))
# test_check_clears_a_download_that_was_killed，在 check_error 的斷言之後
    assert st['check_error_msg'] == {'msg_key': '没有配置更新地址', 'msg_params': {}}
# test_check_finds_an_unsigned_release
    assert st['check_error_msg'] is None
# test_an_older_manifest_is_not_taken
    assert tu.load_status()['check_error_msg'] == {'msg_key': '连不上更新服务器', 'msg_params': {}}
```

- [ ] **跑測試**

Run: `cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk/test_kiosk_commands.py`
Expected：57 passed（54＋`test_msg_keys.py` 的 3 個），沒有 failed。`git diff update/test_*.py` 裏沒有刪改任何對 `message`、`check_error` 的斷言。

- [ ] **Litmus，然後 commit**

```bash
cd /home/chris/Projects/ohimsmart && git add update/thinksmart-update update/test_msg_keys.py update/msg_keys.json update/test_system_layer.py update/test_thinksmart_update.py
git commit -m "feat(update): keyed messages for the pages (msg_key, msg_params, check_error_msg)"
```

### Task 2: `job.reboot`

**Files:**
- Modify: `update/thinksmart-update`、`update/test_system_layer.py`、`update/test_thinksmart_update.py`

**Interfaces:**
- Consumes: Task 1 的 `msg()`、`set_job`。
- Produces: `set_job(…, reboot=False)`，job 多了布林值 `reboot`；`install(conf, version, reboot=False)`；客戶端 `pending.json` 多了 `reboot`。

`reboot` 的意思：**這一次的更新**有沒有裝到只在開機時讀的檔案（系統層的動作含 `boot`）。`st['system']['reboot']` 會一直留着，所以只有在同一次請求裏、系統層剛裝好時才讀它；之後的客戶端更新不能沿用。

- [ ] **`set_job` 加上 `reboot`**

```python
def set_job(st, state, version, message, progress=None, component='client', reboot=False):
    """message: a msg(). The job keeps it as Chinese text in `message` (older pages show that) and as
    msg_key/msg_params (the pages translate those); reboot: this update needs a restart to finish."""
    st['job'] = {'state': state, 'version': version, 'message': msg_text(message), **message,
                 'progress': progress, 'time': int(time.time()), 'component': component, 'reboot': reboot}
```

`download()` 的進度也帶上：`set_job(st, 'downloading', version, msg('正在下载'), (done_before + got) / total, job.get('component', 'client'), job.get('reboot', False))`。

- [ ] **客戶端：`install()` 和 `finish()`**
  - `def install(conf, version, reboot=False):`；`install()` 裏每一個 `set_job(...)` 加上 `reboot=reboot`（四個進度、兩個 `except`）。
  - `pending = {'from': cur, 'to': version, 'previous': previous_version(), 'need_hub': need_hub, 'reboot': reboot}`。
  - `finish()` 開頭：`reboot = pending.get('reboot', False)   # an older updater's record has none`；`finish()` 裏每一個 `set_job(...)` 加上 `reboot=reboot`。

- [ ] **系統層：完成的 job（連同 `reboot`）先寫入，再刪 `SYS_PENDING`**。如果先刪 `SYS_PENDING`、後寫 job，在兩者之間斷電，下次 `recover()` 看不到 pending 紀錄，只看到還在 `testing` 的 job，就會把它標成「上次更新被中断，没有改动」、`reboot` 是 false，但系統層其實已經裝好了。`install_system()` 從 `write_record(...)` 到結尾改成：

```python
    write_record(version, tree, entries)
    reboot = 'boot' in actions
    sysst = st.setdefault('system', {})
    sysst.update(current=version, available=None, reboot=reboot)
    sysst.pop('failed', None)
    if reboot:
        done = msg('系统层已更新到 {version}，部分改动重启设备后生效', version=version)
    else:
        done = msg('系统层已更新到 {version}', version=version)
    set_job(st, 'done', version, done, component='system', reboot=reboot)
    os.sync()            # the finished job on disk before the pending record goes (spec §6.1)
    SYS_PENDING.unlink(missing_ok=True)
    os.sync()
    shutil.rmtree(tree, ignore_errors=True)
    shutil.rmtree(DOWNLOAD, ignore_errors=True)
    return 0
```

在 `set_job` 之後、刪 `SYS_PENDING` 之前斷電：`recover()` 看到 pending 紀錄而且已經記錄了新版本，走「已裝好」的分支；job 已經是 `done`，只更新 `system` 欄位。

- [ ] **`run()`：只看這一次**

```python
        if client_v or system_v:
            reboot = False
            if system_v:
                rc = install_system(conf, system_v)
                if rc or not client_v:
                    return rc          # a failed system layer stops here: the client waits
                # install_system just wrote it for this run; an older run's value never reaches here
                reboot = bool((load_status().get('system') or {}).get('reboot'))
            rc = install(conf, client_v, reboot)
            if rc == 0 and system_v:
                # both went in with one tap: say so in the one result the pages show (the client's
                # own 已更新到 would hide the system layer's)
                st = load_status()
                if reboot:
                    done = msg('已更新到 系统层 {system} · 客户端 {client}，部分改动重启设备后生效',
                               system=system_v, client=client_v)
                else:
                    done = msg('已更新到 系统层 {system} · 客户端 {client}', system=system_v, client=client_v)
                set_job(st, 'done', client_v, done, reboot=reboot)
            return rc
```

- [ ] **`recover()`**
  - 已裝好的分支同樣先寫狀態、再刪 pending 紀錄（現在的程式碼先刪後寫，有同樣的空檔）：

```python
    if spending and system_record().get('version') == spending['to']:
        # it passed its self-test and was recorded; only dropping the pending record didn't reach
        # the disk. Rolling back now would run the old files under the new version's record.
        log('recover: system layer', spending['to'], 'was already installed, keeping it')
        reboot = 'boot' in (spending.get('actions') or [])
        sysst = st.setdefault('system', {})
        sysst.update(current=spending['to'], available=None, reboot=reboot)
        sysst.pop('failed', None)
        if (st.get('job') or {}).get('state') in ACTIVE_JOBS:
            if reboot:
                done = msg('系统层已更新到 {version}，部分改动重启设备后生效', version=spending['to'])
            else:
                done = msg('系统层已更新到 {version}', version=spending['to'])
            set_job(st, 'done', spending['to'], done, component='system', reboot=reboot)
        else:
            save_status(st)
        os.sync()
        SYS_PENDING.unlink(missing_ok=True)
        os.sync()
        spending = None
```
  - 重新自檢：`set_job(st, 'testing', pending['to'], msg('上次更新被中断，正在重新自检'), reboot=pending.get('reboot', False))`。
  - 標成失敗：`set_job(..., component=job.get('component', 'client'), reboot=job.get('reboot', False))`（被中斷的 job 原本要重啟，失敗之後仍然要）。

- [ ] **測試替身跟上簽名**（`update/test_system_layer.py`）：`test_one_request_system_first_then_client` 的 `sysu.install = lambda conf, v, reboot=False: order.append(('client', v)) or 0`；`test_one_tap_for_both_reports_both` 的 `sysu.install = lambda conf, v, reboot=False: …`。

- [ ] **測試：spec 的四種情況和兩個反例**（`update/test_system_layer.py`）

```python
BOOT_LINE = 'kiosk/welcome.html /etc/thinksmart-boot-test.conf 644 root boot\n'   # read only at boot


def test_a_system_layer_read_at_boot_says_restart(sysu, release):
    """Only the system layer, and it changed a file read only at boot: job.reboot (spec §6.1)."""
    old_device(sysu)
    release(tree_kw={'extra': BOOT_LINE})
    sysu.run_main('check')
    (sysu.REQUESTS / 'install').write_text(json.dumps({'action': 'install', 'version': '', 'system': '0.2.0'}))
    assert sysu.run_main('run') == 0
    st = sysu.load_status()
    assert st['job']['state'] == 'done' and st['job']['reboot'] is True and st['system']['reboot'] is True
    assert st['job']['message'] == '系统层已更新到 0.2.0，部分改动重启设备后生效'


def test_one_tap_carries_this_runs_reboot_to_the_client(sysu, release):
    """Both with one tap: the client's job (the one the pages show) carries the system layer's
    reboot, whether the client then goes in or not; a later client-only update doesn't."""
    release(client='1.2.0')
    sysu.run_main('check')

    def install_system(conf, v):
        st = sysu.load_status()
        st.setdefault('system', {})['reboot'] = True
        sysu.save_status(st)
        return 0
    seen = []
    sysu.install_system = install_system
    sysu.install = lambda conf, v, reboot=False: seen.append(reboot) or 0
    (sysu.REQUESTS / 'install').write_text(json.dumps({'action': 'install', 'version': '1.2.0', 'system': '0.2.0'}))
    assert sysu.run_main('run') == 0
    job = sysu.load_status()['job']
    assert seen == [True] and job['reboot'] is True
    assert job['message'] == '已更新到 系统层 0.2.0 · 客户端 1.2.0，部分改动重启设备后生效'
    # system.reboot is still in the status file from that run: a client-only update must not take it
    (sysu.REQUESTS / 'install').write_text(json.dumps({'action': 'install', 'version': '1.2.0'}))
    sysu.run_main('run')
    assert seen == [True, False]


def test_power_cut_after_a_passed_install_keeps_its_reboot(sysu, release, monkeypatch):
    """Recorded, then the power went before the pending record was dropped: the finished job and its
    reboot are in the status file first, and boot works them out again from the pending record."""
    old_device(sysu)
    release(tree_kw={'extra': BOOT_LINE})
    sysu.run_main('check')
    real_unlink = Path.unlink

    def unlink(self, *a, **k):
        if self == sysu.SYS_PENDING:
            raise KeyboardInterrupt
        return real_unlink(self, *a, **k)
    monkeypatch.setattr(Path, 'unlink', unlink)
    with pytest.raises(KeyboardInterrupt):
        sysu.install_system(sysu.read_conf(), '0.2.0')
    monkeypatch.setattr(Path, 'unlink', real_unlink)
    st = sysu.load_status()
    # written before the pending record goes
    assert st['job']['state'] == 'done' and st['job']['reboot'] is True and st['system']['reboot'] is True
    # as if that write hadn't reached the disk: the job still testing, no reboot anywhere
    st['job'].update(state='testing', reboot=False)
    del st['system']['reboot']
    sysu.save_status(st)
    sysu.run_main('boot')
    st = sysu.load_status()
    assert st['job']['state'] == 'done' and st['job']['reboot'] is True and st['system']['reboot'] is True
```

`test_install_system_layer`（沒有 `boot` 動作）在現有的斷言之後加上 `assert st['job']['reboot'] is False and st['system']['reboot'] is False`。

`update/test_thinksmart_update.py`：

```python
def test_the_client_job_after_a_restart_needing_system_layer_keeps_reboot(tu, source):
    """System layer then client with one tap: whatever happens to the client, its job still says the
    restart is needed (spec §6.1: system layer done, client failed or went back)."""
    tu.run_main('check')
    tu.self_test = lambda version, need_hub, s: (version == '1.1.0', tu.msg('新版本没有启动起来'))
    assert tu.install(tu.read_conf(), '1.2.0', True) == 1
    job = tu.load_status()['job']
    assert job['state'] == 'rolled_back' and job['reboot'] is True
    good = source['code'].read_bytes()
    source['code'].write_bytes(good[:-1] + bytes([good[-1] ^ 1]))
    assert tu.install(tu.read_conf(), '1.2.0', True) == 1
    job = tu.load_status()['job']
    assert job['state'] == 'failed' and job['reboot'] is True
    source['code'].write_bytes(good)
    tu.self_test = lambda version, need_hub, s: (True, '')
    assert tu.install(tu.read_conf(), '1.2.0', True) == 0
    job = tu.load_status()['job']
    assert job['state'] == 'done' and job['reboot'] is True
```

`test_install_from_a_test_source` 在現有的斷言之後加上 `assert tu.load_status()['job']['reboot'] is False`。

（第四種情況「中斷後重新自檢」由 `pending.get('reboot')` 處理；`test_killed_during_self_test_tests_again_and_keeps_it` 的 pending 沒有 `reboot`，正好測到舊紀錄：在現有的斷言之後加上 `assert tu.load_status()['job']['reboot'] is False`。）

- [ ] **跑測試**

Run: `cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk/test_kiosk_commands.py`
Expected：61 passed，沒有 failed。

- [ ] **Litmus，然後 commit**

```bash
cd /home/chris/Projects/ohimsmart && git add update/thinksmart-update update/test_system_layer.py update/test_thinksmart_update.py
git commit -m "feat(update): job.reboot for this run, written before the pending record goes"
```

### Task 3: 歡迎頁讀 `job.reboot`；README；merge

**Files:**
- Modify: `kiosk/welcome.html`、`update/README.md`
- Create: `kiosk/test_welcome_update.py`

- [ ] **`kiosk/welcome.html`**：`const UPD_STAGE = { …` 佔兩行（第 527–528 行），在它結尾的 `};` **那一行之後**加入下面兩行（加在物件裏面會讓整個頁面的腳本失效，連 WiFi 設定也不能用）：

```js
// job.reboot from the updater; an older updater only says it in its Chinese message
const needsReboot = job => (typeof job.reboot === 'boolean' ? job.reboot : /重启设备后生效/.test(job.message || ''));
// a failed or rolled-back result; the system layer before it may still need a restart (spec §6.1)
const updFail = job => (job.message || '') + (needsReboot(job) ? '。系统层的部分改动重启设备后生效' : '');
```

`renderUpdate()` 裏：
- `(/重启设备后生效/.test(job.message || '') ? '，部分改动重启设备后生效' : '')` 改成 `(needsReboot(job) ? '，部分改动重启设备后生效' : '')`；
- 有新版本的分支 `text = bad ? job.message : …` 改成 `text = bad ? updFail(job) : …`；
- 最後一個分支的 `: job.message || '';` 改成 `: updFail(job);`。

- [ ] **`kiosk/test_welcome_update.py`**

```python
"""The welcome page asks job.reboot whether an update needs a restart; an older updater's job only
says it in its message (spec §6.1). Needs node.

  uv run --no-project --with pytest python -m pytest -q kiosk/test_welcome_update.py
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

WELCOME = Path(__file__).with_name('welcome.html')


def run_helpers(expr):
    """Evaluate expr (JSON out) next to the page's needsReboot and updFail."""
    page = WELCOME.read_text(encoding='utf-8')
    lines = [re.search(rf'^const {name} = .*$', page, re.M) for name in ('needsReboot', 'updFail')]
    assert all(lines), 'needsReboot or updFail not found in welcome.html'
    code = '\n'.join(m[0] for m in lines) + f'\nprocess.stdout.write(JSON.stringify({expr}))'
    out = subprocess.run([shutil.which('node') or 'node', '-e', code],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_needs_reboot_reads_the_flag_first():
    cases = [({'reboot': True}, True),
             ({'reboot': False, 'message': '系统层已更新到 1.0.1，部分改动重启设备后生效'}, False),
             ({'message': '系统层已更新到 1.0.1，部分改动重启设备后生效'}, True),
             ({'message': '已更新到 1.0.1'}, False)]
    jobs = json.dumps([job for job, _ in cases], ensure_ascii=False)
    assert run_helpers(f'{jobs}.map(needsReboot)') == [want for _, want in cases]
    page = WELCOME.read_text(encoding='utf-8')
    assert page.count('/重启设备后生效/.test') == 1        # only inside needsReboot


def test_a_failed_client_after_a_restart_needing_system_layer_still_says_restart():
    jobs = json.dumps([{'state': 'failed', 'message': '连不上更新服务器', 'reboot': True},
                       {'state': 'failed', 'message': '连不上更新服务器', 'reboot': False}], ensure_ascii=False)
    assert run_helpers(f'{jobs}.map(updFail)') == ['连不上更新服务器。系统层的部分改动重启设备后生效', '连不上更新服务器']


def test_the_page_script_still_parses(tmp_path):
    """The helpers sit between statements, not inside UPD_STAGE: node must parse the whole script."""
    page = WELCOME.read_text(encoding='utf-8')
    scripts = re.findall(r'<script>(.*?)</script>', page, re.S)
    assert scripts
    for i, js in enumerate(scripts):
        f = tmp_path / f'welcome-{i}.js'
        f.write_text(js, encoding='utf-8')
        r = subprocess.run([shutil.which('node') or 'node', '--check', str(f)], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
```

實作時先確認這個測試會失敗：把 `needsReboot` 那行暫時放進 `UPD_STAGE` 物件裏，測試要報錯，再放回原處。

- [ ] **`update/README.md`**：在「設備上的目錄」那一段的最後加一句：

```markdown
任务状态 `job` 有中文的 `message`（旧页面显示）、`msg_key`/`msg_params`（页面按语言翻译；所有键列在 `msg_keys.json`，由 `test_msg_keys.py` 核对）和 `reboot`（这次更新要重启设备才完全生效）；`check_error` 旁边有同样格式的 `check_error_msg`。改了更新器的文字：重新产生 `msg_keys.json`，复制到客户端仓库的 `tests/updater_keys.json`，再补客户端的繁中和英文字典（两个仓库的测试互相看不到，这一步要手动做）。
```

- [ ] **跑測試**

Run: `cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk/test_kiosk_commands.py kiosk/test_welcome_update.py`
Expected：64 passed（61＋`kiosk/test_welcome_update.py` 的 3 個）。

- [ ] **Litmus，commit，merge，push**

```bash
cd /home/chris/Projects/ohimsmart && git add kiosk/welcome.html kiosk/test_welcome_update.py update/README.md
git commit -m "feat(kiosk): the welcome page reads job.reboot; README: the job's keyed fields"
git switch main && git merge --no-ff feat/updater-msg-keys -m "Merge branch 'feat/updater-msg-keys': updater message keys and job.reboot (plan 2 of 7)"
git push origin main
```

### Task 4: 客戶端的字典和英文測試

**Files:**
- Modify: 客戶端 `tests/updater_keys.json`、`web/zh-Hant.js`、`web/en.js`、`web/v2/app.js`、`tests/test_i18n_page.cjs`

**Interfaces:**
- Consumes: 主 repo 的 `update/msg_keys.json`（Task 1）、「訊息的鍵」那張表。

- [ ] **分支和鍵的副本**

```bash
cd /home/chris/src/oh-im-smart-client && git switch -c feat/updater-keys main
cp /home/chris/Projects/ohimsmart/update/msg_keys.json tests/updater_keys.json
```

- [ ] **失敗也提醒重新開機**（「跨計劃的約定」第 4 點）：`web/v2/app.js` 在 `const needsReboot = …` 的下一行加入

```js
// a failed or rolled-back result; the system layer before it may still need a restart (spec §6.1)
const updFail = job => updMsg(job) + (needsReboot(job) ? UII18n.t("。") + UII18n.t("系统层的部分改动重启设备后生效") : '');
```

`renderUpdate()` 的 `text = failed ? updMsg(job) + UII18n.t("。可以再试一次")` 和 `: failed ? updMsg(job)`，以及 `updateFinished()` 的 `toast(job.state === 'done' ? updDoneText(ui.update, job) : updMsg(job), …)`，三處的 `updMsg(job)` 都改成 `updFail(job)`。`tests/test_i18n_page.cjs` 的 `HELPERS` 加上 `piece(/^const updFail = .*$/m)`，`this.page` 加上 `updFail`。

- [ ] **加入字典**：寫一個一次性的腳本（放在 scratchpad，不 commit），內容是「訊息的鍵」那張表的 49 個新鍵，再加上頁面自己的 `系统层的部分改动重启设备后生效`（繁中 `系統層的部分改動重啟裝置後生效`，英文 `Some system layer changes take effect after a restart`），共 50 個（`ENTRIES = {鍵: (繁中, 英文)}`），照下面的方式合併。兩份字典現在都是一行一個條目、按 code point 排序、沒有重複；合併後保持這樣。

```python
import json
import re
from pathlib import Path

R = Path('/home/chris/src/oh-im-smart-client')
ENTRIES = {}   # the 49 new keys from the plan's table and the page's restart sentence: key -> (zh-Hant, English)


def merge(path, name, values):
    s = path.read_text(encoding='utf-8')
    m = re.search(r'window\.%s = \{\n(.*?)\n\};' % re.escape(name), s, re.S)
    items = dict(next(iter(json.loads('{' + line.rstrip(',') + '}').items())) for line in m.group(1).split('\n'))
    clash = {k for k in values if k in items and items[k] != values[k]}
    assert not clash, clash                      # an existing entry is never changed
    items.update(values)
    body = ',\n'.join(f'  {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)}'
                      for k, v in sorted(items.items()))
    path.write_text(s[:m.start(1)] + body + s[m.end(1):], encoding='utf-8')


assert len(ENTRIES) == 50
merge(R / 'web/zh-Hant.js', 'UI_ZH_HANT', {k: v[0] for k, v in ENTRIES.items()})
merge(R / 'web/en.js', 'UI_EN', {k: v[1] for k, v in ENTRIES.items()})
```

Expected：兩份字典各 +50 行；`git diff web/*.js` 裏沒有被刪除或改動的現有條目。

- [ ] **英文和繁中的顯示**：`tests/test_i18n_page.cjs` 最後加上

```js
test("the updater's messages in English and Traditional Chinese, nested reasons too", () => {
  const en = page('en'), hant = page('zh-Hant');
  const rollback = {state: 'rolled_back', message: '系统层 0.2.0 没装成功（屏幕界面没有启动起来），已退回 0.1.0',
    msg_key: '系统层 {version} {why}，已退回 {old}',
    msg_params: {version: '0.2.0', old: '0.1.0',
      why: {msg_key: '没装成功（{why}）', msg_params: {why: {msg_key: '屏幕界面没有启动起来', msg_params: {}}}}}};
  assert.equal(en.updMsg(rollback), 'System layer 0.2.0: installation failed (the screen interface did not start); went back to 0.1.0');
  assert.equal(hant.updMsg(rollback), '系統層 0.2.0 沒裝成功（螢幕介面沒有啟動起來），已退回 0.1.0');
  const offline = {msg_key: '连不上更新服务器', msg_params: {}};   // the page shows check_error_msg the same way
  assert.equal(en.updMsg(offline), 'Can’t reach the update server');
  assert.equal(hant.updMsg(offline), '連不上更新伺服器');
});

test('a failed client after a system layer that needs a restart still says restart', () => {
  const en = page('en');
  const failed = {state: 'failed', message: '连不上更新服务器', msg_key: '连不上更新服务器', msg_params: {}};
  const withRestart = en.updFail({...failed, reboot: true});
  assert.ok(withRestart.startsWith('Can’t reach the update server'), withRestart);
  assert.ok(withRestart.endsWith('Some system layer changes take effect after a restart'), withRestart);
  assert.equal(en.updFail({...failed, reboot: false}), 'Can’t reach the update server');
  assert.equal(en.updFail({state: 'failed', message: '下载失败'}), en.updMsg({message: '下载失败'}));   // an older updater
});
```

- [ ] **跑測試**

Run: `cd /home/chris/src/oh-im-smart-client && .venv/bin/python -m pytest -q -p no:cacheprovider` → 179 passed（字典完整性測試現在包含更新器的 53 個鍵和頁面的新句子）；`node --test tests/*.cjs` → 16 passed。

- [ ] **Litmus，commit，merge，push**

```bash
cd /home/chris/src/oh-im-smart-client && git add tests/updater_keys.json web/zh-Hant.js web/en.js web/v2/app.js tests/test_i18n_page.cjs
git commit -m "i18n: the updater's message keys; a failed update after a system layer that needs a restart says so"
git switch main && git merge --no-ff feat/updater-keys -m "Merge branch 'feat/updater-keys': the updater's message keys"
git push origin main
```

### Task 5: 實作記錄

- [ ] 在本計劃最後加「實作記錄」：兩個 repo 的 commit、測試數目、跟計劃不同的地方。Litmus 之後 commit 並 push 主 repo。

## 實作記錄

**完成（2026-11-14）。** 主 repo `main` = `3f3dee4`（`61d2ef2`、`32e08b8`、`e750c0c`），66 passed。客戶端 `main` = `1282847`（`0b49e47`），pytest 179 passed、node 16 passed。設計審查第 2 輪 PASS；該輪剩下的 1 個中等問題和 6 個低問題都在實作時處理了，以 commit 為準。跟上面的計劃不同的地方：

- **`UPDATER_VERSION = 3` 放在 Task 2 的 commit**（計劃寫在 Task 1）：程式碼審查指出版本 3 的註解寫着 `job.reboot`，Task 1 還沒有這個欄位。`test_selftest_does_not_wait_for_the_lock` 改成斷言 `thinksmart-update 3`（設計審查第 2 輪的中等問題）。
- **鍵的測試認得全形標點：** `CHINESE` 包括 `　-〿`、`＀-￯`，跟客戶端一致；收集器的自我測試多一個只有「，」的字串，比較問題清單時不看次序（`ast.walk` 的次序跟巢狀深度有關）。
- **`recover()` 已裝好的分支：** 訊息仍是 `系统层已更新到 {version}`（跟改動前一字不差），要不要重新開機只放在 `reboot`；沒有 job（`status.json` 遺失或損壞）時也寫入完成的 job；先寫狀態，再刪 `SYS_PENDING`。
- **歡迎頁的 `updFail` 只在 `state` 不是 `done` 時加提醒**，完成的訊息本身已經寫了，不會重複。客戶端的 `updFail` 也一樣。
- **多了兩個測試：** `test_a_lost_status_file_still_gets_the_finished_job`、`test_an_interrupted_self_test_keeps_the_reboot_it_was_given`（設計審查第 2 輪的低問題），所以 Task 2 之後是 63 個，Task 3 之後是 66 個。
- **`test_the_client_job_after_a_restart_needing_system_layer_keeps_reboot` 改了次序：** 先 sha256 失敗、再自檢退回、最後成功；退回時 `cleanup()` 會刪掉測試事先放好的依賴環境，所以成功那一步前重新建立。
- **兩個測試替身改回傳 `msg()`：** `test_a_damaged_backup_copy_is_not_restored`、`test_killed_during_self_test_rolls_back_if_it_fails`。現有對 `message`、`check_error` 的斷言一行都沒改。
- **spec §6.1 寫「请重启设备」是一個鍵；** 本計劃用整句範本（含「请重启设备」的句子各是一個鍵），英文的詞序比較自然。

## 不在這份計劃裏

- 歡迎頁用 `msg_key` 翻譯訊息、歡迎頁的三份字典（kiosk 語言選擇計劃，從 `update/msg_keys.json` 取鍵）。
- 網關後台的更新紀錄（`scripts/update.sh` 的中文輸出，spec §6.1 寫明 v1 不翻譯）。
- 系統層 `VERSION` 改成 1.0.0、發佈線上更新 Release（教學和映像 Release 計劃）。
- 客戶端 `web/zh-Hant.js` 現有的「自檢沒透過」（應為「沒通過」，OpenCC 的誤譯）：不屬於本計劃，另外回報。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
