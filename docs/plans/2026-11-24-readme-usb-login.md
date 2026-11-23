# 教學：刷完的系統可以用 USB 線登入 Implementation Plan

> **已實作（2026-11-24）**：見文末實作記錄。

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 三語教學裏「刷完的系統不能用 USB 線登入」「電腦看不到 USB 口」的說法已經不成立，改成實測到的現況，並在配網失敗時把 USB 登入列為一個辦法。

**Architecture:** 只改三個 README 的文字（每個檔案七處：原有的六處錯誤說法，加上 3.3 裏跟着要改的一句；三個檔案行號相同），不改映像、不改程式。改寫依據是 v1-polish 計劃 Task 5 的結果 3（`docs/plans/2026-11-19-v1-polish.md` 的實作記錄）加上 2026-11-24 的熱插拔測試：

- `image-20261118`，母機開着、連着 WiFi，USB 線接到 Linux 電腦（UM）：電腦多出 `enx…` 介面並自動拿到 `172.16.42.2/24`；`ping 172.16.42.1` 通；`172.16.42.1` 上的 SSH 主機金鑰和 WiFi 地址的一樣；維護者經 `172.16.42.1` 用密碼登入成功，裝置上 `usb0` 是 `172.16.42.1/16`、UDC 狀態 `configured`。
- 2026-11-24 裝置開着時把線從電腦拔掉、10 秒後插回：電腦的 kernel 記錄重新出現 `cdc_ncm … usb0`，介面自動拿回 `172.16.42.2`，ping 和 SSH 埠都通。
- 裝置經 USB 發的 DHCP 只給地址和子網掩碼（`255.255.255.0`），沒有路由器、沒有 DNS。
- macOS、Windows 沒測；經 USB 開瀏覽器後台沒測。教學照實寫「未實測」，跟現有的「（未實測）」寫法一致。

**Tech Stack:** Markdown；`tools/check-readmes.sh`（三語的 bash 區塊和網址必須一致）。

**Global Constraints:**
- 本 repo 分支 `docs/readme-usb-login`（已從 `main` `89ef7bf` 開好）。merge 到 `main` 一律 `--no-ff`；commit 前跑 Litmus；每個 commit 訊息（包括 merge）結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 標題「刷完後的 USB 網路」「刷完后的 USB 网络」「USB network after flashing」不改，現有連結的錨點才不會斷。
- 三個檔案新加的 bash 區塊內容必須一字不差，`tools/check-readmes.sh` 才會過。
- 教學寫給所有使用者：SSH 埠寫 22 的預設（不寫維護者自己裝置改過的 3722），帳號 `ubuntu`。
- 不碰 bootstrap 階段（A5）的說明，它本來就是對的。

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `README.zh-Hant.md` | 繁中教學：2.3、3.3、3.5、附錄裏的七處 |
| `README.md` | 簡中教學：同樣七處 |
| `README.en.md` | 英文教學：同樣七處 |

---

### Task 1: 改寫三語教學的七處

**Files:**
- Modify: `README.zh-Hant.md`、`README.md`、`README.en.md`（行號三個檔案相同：第 636、780、781、824、986–988、995、1013 行）

每一處都是**整行替換**：先確認舊的那一行跟下面寫的一字不差（不一樣就停下回報，不要猜），再換成新的。行號是動手前的；⑤ 會多出幾行，之後的行號往後移，所以一律以舊的那一行文字為準。下面行內的 `\`` 在檔案裏是普通的反引號（`` ` ``），只是這份計劃裏的寫法。

- [ ] **① 2.3 開頭（第 636 行）**
  - 繁中 舊：`後面用瀏覽器和 SSH 都要用到。刷完的系統目前**不能用 USB 線登入**（見[附錄](#刷完後的-usb-網路)），只能連上 WiFi 後用 WiFi 的地址。`
  - 繁中 新：`後面用瀏覽器和 SSH 都要用到。刷完的系統也能用 USB 線 SSH 登入（見[附錄](#刷完後的-usb-網路)），不過經 USB 線開瀏覽器還沒實測過，下面的步驟都用 WiFi 的地址。`
  - 簡中 舊：`后面用浏览器和 SSH 都要用到。刷完的系统目前**不能用 USB 线登录**（见[附录](#刷完后的-usb-网络)），只能连上 WiFi 后用 WiFi 的地址。`
  - 簡中 新：`后面用浏览器和 SSH 都要用到。刷完的系统也能用 USB 线 SSH 登录（见[附录](#刷完后的-usb-网络)），不过经 USB 线开浏览器还没实测过，下面的步骤都用 WiFi 的地址。`
  - 英文 舊：`You need it for the browser and SSH. The flashed system currently **can't be reached over a USB cable** (see the [appendix](#usb-network-after-flashing)); use its Wi-Fi address once it's on Wi-Fi.`
  - 英文 新：`You need it for the browser and SSH. You can also SSH into the flashed system over a USB cable (see the [appendix](#usb-network-after-flashing)), but using the browser over USB hasn't been tested, so the steps below all use the Wi-Fi address.`

- [ ] **② 3.3 配網不成功（第 780 行）**
  - 繁中 舊：`- 刷完的系統目前不能用 USB 線登入（見[附錄](#刷完後的-usb-網路)）。螢幕配網一直不成功：重啟裝置再試；還不行就重刷（A8 / B3）後重新配網。`
  - 繁中 新：`- 螢幕配網一直不成功：重啟裝置再試；還不行，可以試試用 USB 線 SSH 登入（見[附錄](#刷完後的-usb-網路)；裝置沒連上 WiFi 時能不能這樣登入還沒實測），再用下一條的 \`nmcli\` 命令連 WiFi；都不行就重刷（A8 / B3）後重新配網。`
  - 簡中 舊：`- 刷完的系统目前不能用 USB 线登录（见[附录](#刷完后的-usb-网络)）。屏幕配网一直不成功：重启设备再试；还不行就重刷（A8 / B3）后重新配网。`
  - 簡中 新：`- 屏幕配网一直不成功：重启设备再试；还不行，可以试试用 USB 线 SSH 登录（见[附录](#刷完后的-usb-网络)；设备没连上 WiFi 时能不能这样登录还没实测），再用下一条的 \`nmcli\` 命令连 WiFi；都不行就重刷（A8 / B3）后重新配网。`
  - 英文 舊：`- The flashed system currently can't be reached over a USB cable (see the [appendix](#usb-network-after-flashing)). If Wi-Fi setup on the screen keeps failing: reboot the device and try again; if that doesn't help, reflash (A8 / B3) and set up Wi-Fi again.`
  - 英文 新：`- If Wi-Fi setup on the screen keeps failing: reboot the device and try again; if that doesn't help, try SSH over a USB cable (see the [appendix](#usb-network-after-flashing); whether this works while the device isn't on Wi-Fi hasn't been tested) and connect with the \`nmcli\` commands in the next item; if nothing works, reflash (A8 / B3) and set up Wi-Fi again.`
- [ ] **③ 3.3 下一條的開頭（第 781 行）**：原句只說「經 WiFi 登入」，改成兩種登入都適用。
  - 繁中 舊：`- 已經能透過 WiFi SSH 登入、想換到另一個網路時，可以用命令連：`
  - 繁中 新：`- 已經能 SSH 登入（WiFi 或 USB 線）、想連 WiFi 或換到另一個網路時，可以用命令連：`
  - 簡中 舊：`- 已经能通过 WiFi SSH 登录、想换到另一个网络时，可以用命令连：`
  - 簡中 新：`- 已经能 SSH 登录（WiFi 或 USB 线）、想连 WiFi 或换到另一个网络时，可以用命令连：`
  - 英文 舊：`- When you can already SSH in over Wi-Fi and want to switch to another network, connect from the command line:`
  - 英文 新：`- When you can already SSH in (over Wi-Fi or a USB cable) and want to connect to Wi-Fi or switch networks, connect from the command line:`

- [ ] **④ 3.5 SSH 也連不上（第 824 行）**
  - 繁中 舊：`- SSH 也連不上：刷完的系統不能用 USB 線登入，先確認裝置連上了 WiFi（3.3）、IP 找對了（2.3）；macOS 上報 \`No route to host\` 見 3.8；都不行就重刷（A8 / B3）。`
  - 繁中 新：`- SSH 也連不上：先確認裝置連上了 WiFi（3.3）、IP 找對了（2.3）；macOS 上報 \`No route to host\` 見 3.8；WiFi 那邊不行就用 USB 線登入看看（見[附錄](#刷完後的-usb-網路)）；都不行就重刷（A8 / B3）。`
  - 簡中 舊：`- SSH 也连不上：刷完的系统不能用 USB 线登录，先确认设备连上了 WiFi（3.3）、IP 找对了（2.3）；macOS 上报 \`No route to host\` 见 3.8；都不行就重刷（A8 / B3）。`
  - 簡中 新：`- SSH 也连不上：先确认设备连上了 WiFi（3.3）、IP 找对了（2.3）；macOS 上报 \`No route to host\` 见 3.8；WiFi 那边不行就用 USB 线登录看看（见[附录](#刷完后的-usb-网络)）；都不行就重刷（A8 / B3）。`
  - 英文 舊：`- SSH doesn't work either: the flashed system can't be reached over USB, so check that the device is on Wi-Fi (3.3) and that you have the right IP (2.3); for \`No route to host\` on macOS see 3.8; if nothing helps, reflash (A8 / B3).`
  - 英文 新：`- SSH doesn't work either: check that the device is on Wi-Fi (3.3) and that you have the right IP (2.3); for \`No route to host\` on macOS see 3.8; if Wi-Fi still doesn't work, try logging in over a USB cable (see the [appendix](#usb-network-after-flashing)); if nothing helps, reflash (A8 / B3).`

- [ ] **⑤ 附錄「刷完後的 USB 網路」本文（第 986–988 行）**：標題（第 984 行）不動，把標題下面「已知問題」那一段和「所以刷完後只能…」那一段（中間的空行一起）換成下面的內容。三個檔案的 bash 區塊一字不差。
  - 繁中：

    ````markdown
    刷完的系統也能用 USB 線 SSH 登入。裝置開著時，用能傳資料的 USB 線接到電腦：裝置是 `172.16.42.1`，電腦通常會自動拿到 `172.16.42.2`；沒有的話，在電腦上把這個介面手動設成 IP `172.16.42.2`、子網掩碼 `255.255.255.0`、路由器留空。映像裡的 USB 網路是 NCM（上游裝置包預設是 macOS 不支援的 RNDIS）。

    帳號是 `ubuntu`，密碼見 [2.5](#25-改預設密碼為了安全刷完馬上改)。以前 SSH 過 bootstrap 階段的 `172.16.42.1`，會提示主機金鑰變了，先照 [3.6](#36-ssh-提示主機金鑰變了) 清掉舊記錄。

    ```bash
    ping -c 3 172.16.42.1
    ssh ubuntu@172.16.42.1
    ```

    實測過的情況：`image-20261118`、Linux 電腦、裝置連著 WiFi；裝置開著時插上線能連，拔掉再插回也能連。macOS 和 Windows 未實測，裝置沒連 WiFi 時也未實測；經 USB 線開瀏覽器後臺也未實測，後臺請用 WiFi 的地址。
    ````

  - 簡中：

    ````markdown
    刷完的系统也能用 USB 线 SSH 登录。设备开着时，用能传数据的 USB 线接到电脑：设备是 `172.16.42.1`，电脑通常会自动拿到 `172.16.42.2`；没有的话，在电脑上把这个接口手动设成 IP `172.16.42.2`、子网掩码 `255.255.255.0`、路由器留空。镜像里的 USB 网络是 NCM（上游设备包默认是 macOS 不支持的 RNDIS）。

    账号是 `ubuntu`，密码见 [2.5](#25-改默认密码为了安全刷完马上改)。以前 SSH 过 bootstrap 阶段的 `172.16.42.1`，会提示主机密钥变了，先照 [3.6](#36-ssh-提示主机密钥变了) 清掉旧记录。

    ```bash
    ping -c 3 172.16.42.1
    ssh ubuntu@172.16.42.1
    ```

    实测过的情况：`image-20261118`、Linux 电脑、设备连着 WiFi；设备开着时插上线能连，拔掉再插回也能连。macOS 和 Windows 未实测，设备没连 WiFi 时也未实测；经 USB 线开浏览器后台也未实测，后台请用 WiFi 的地址。
    ````

  - 英文：

    ````markdown
    You can also SSH into the flashed system over a USB cable. With the device running, connect it to the computer with a USB cable that carries data: the device is `172.16.42.1`, and the computer normally gets `172.16.42.2` automatically; if it doesn't, set that interface manually on the computer: IP `172.16.42.2`, subnet mask `255.255.255.0`, router empty. The image's USB network is NCM (upstream's device package defaults to RNDIS, which macOS doesn't support).

    The account is `ubuntu`; for the password see [2.5](#25-change-the-default-passwords-do-it-right-after-flashing). If you SSH'd to `172.16.42.1` during the bootstrap, SSH will say the host key changed: clear the old entry first as in [3.6](#36-ssh-says-the-host-key-changed).

    ```bash
    ping -c 3 172.16.42.1
    ssh ubuntu@172.16.42.1
    ```

    Tested: `image-20261118`, a Linux computer, the device on Wi-Fi; plugging the cable in while the device runs works, and so does unplugging and plugging it back in. macOS and Windows are untested, so is a device that isn't on Wi-Fi, and so is opening the admin page in a browser over USB; use the Wi-Fi address for that.
    ````

- [ ] **⑥ 「映像裡的系統調整」的 NCM 那條（第 995 行）**
  - 繁中 舊：`- USB 網路設成 NCM 而不是上游的 RNDIS（不過目前刷完後的系統 USB 口不被電腦識別，見上一節）。`
  - 繁中 新：`- USB 網路設成 NCM 而不是上游的 RNDIS（用法見上一節）。`
  - 簡中 舊：`- USB 网络设成 NCM 而不是上游的 RNDIS（不过目前刷完后的系统 USB 口不被电脑识别，见上一节）。`
  - 簡中 新：`- USB 网络设成 NCM 而不是上游的 RNDIS（用法见上一节）。`
  - 英文 舊：`- The USB network is set to NCM instead of upstream's RNDIS (though for now the flashed system's USB port isn't recognized by computers, see the previous section).`
  - 英文 新：`- The USB network is set to NCM instead of upstream's RNDIS (see the previous section for how to use it).`

- [ ] **⑦ 「已知限制」的 USB 那條（第 1013 行）**：整行刪掉（連同行尾換行），前後兩條保持相鄰，不留空行。
  - 繁中：`- 刷完後的系統不能用 USB 線登入，只能走 WiFi（見[刷完後的 USB 網路](#刷完後的-usb-網路)）。`
  - 簡中：`- 刷完后的系统不能用 USB 线登录，只能走 WiFi（见[刷完后的 USB 网络](#刷完后的-usb-网络)）。`
  - 英文：`- The flashed system can't be reached over a USB cable, only over Wi-Fi (see [USB network after flashing](#usb-network-after-flashing)).`

- [ ] **檢查**

Run：

```bash
cd /home/chris/Projects/ohimsmart
tools/check-readmes.sh
grep -cE '不能用 USB 線|不能用 USB 线|can.t be reached over (a )?USB|不被電腦識別|不被电脑识别|recognized by computers' README.md README.zh-Hant.md README.en.md
grep -c 'ssh ubuntu@172.16.42.1' README.md README.zh-Hant.md README.en.md
git diff --stat
```

Expected：`check-readmes: the three tutorials agree`（exit 0）；第一個 grep 印出三行，每行結尾都是 `:0`（讀不到檔案會印錯誤訊息，也算失敗）；第二個 grep 三個檔案各 `1`；`git diff --stat` 只有三個 README，每個檔案的增刪行數相同。

- [ ] **Litmus 後 commit**

```bash
cd /home/chris/Projects/ohimsmart
git add README.md README.zh-Hant.md README.en.md
git commit -m "docs(readme): the flashed system can be reached over a USB cable" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 1b: 附錄的手動設定改成 /24（審查後追加）

921ad2e 的附錄請讀者照 A5 第 3 點手動設定，那裏的子網掩碼是 `255.255.0.0`，會讓電腦把整個 `172.16.0.0/16` 導到 USB 線，也跟裝置 DHCP 給的 `/24` 不一致。這一步把附錄那一句改成直接寫 `/24`（⑤ 的文字已經是改好的版本）。

**Files:**
- Modify: `README.zh-Hant.md`、`README.md`、`README.en.md`（附錄「刷完後的 USB 網路」標題下的第一段，三個檔案都在第 986 行）

- [ ] 先看 `grep -c '255\.255\.255\.0' README.md README.zh-Hant.md README.en.md`：每個檔案已經是 `:1`（照現在的 ⑤ 從頭做的情況），Task 1b 整個跳過（不改、不檢查 diff、不 commit），直接做 Task 2。每個檔案都是 `:0`，才在那一行裏把舊的片段換成新的片段（片段恰好出現一次，不是就停下回報）：
  - 繁中 舊片段：`沒有的話，照 [A5](#a5-ssh-登入-bootstrap)「先等 USB 網路」的第 3 點手動設定。`
  - 繁中 新片段：`沒有的話，在電腦上把這個介面手動設成 IP \`172.16.42.2\`、子網掩碼 \`255.255.255.0\`、路由器留空。`
  - 簡中 舊片段：`没有的话，照 [A5](#a5-ssh-登录-bootstrap)「先等 USB 网络」的第 3 点手动设置。`
  - 簡中 新片段：`没有的话，在电脑上把这个接口手动设成 IP \`172.16.42.2\`、子网掩码 \`255.255.255.0\`、路由器留空。`
  - 英文 舊片段：`if it doesn't, set it manually as in point 3 of "Wait for the USB network" in [A5](#a5-log-in-to-the-bootstrap-over-ssh).`
  - 英文 新片段：`if it doesn't, set that interface manually on the computer: IP \`172.16.42.2\`, subnet mask \`255.255.255.0\`, router empty.`
- [ ] **檢查**

Run：

```bash
cd /home/chris/Projects/ohimsmart
tools/check-readmes.sh
grep -c '255\.255\.255\.0' README.md README.zh-Hant.md README.en.md
grep -cE '不能用 USB 線|不能用 USB 线|can.t be reached over (a )?USB|不被電腦識別|不被电脑识别|recognized by computers' README.md README.zh-Hant.md README.en.md
git diff --stat
```

Expected：`check-readmes: the three tutorials agree`；第一個 grep 每個檔案 `:1`；第二個 grep 每個檔案 `:0`；`git diff --stat` 只有三個 README，各 1 行增 1 行刪。

- [ ] **Litmus 後 commit**：`git add README.md README.zh-Hant.md README.en.md && git commit -m "docs(readme): manual USB address uses a /24 mask" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`

### Task 2: 記錄、合併、推送

- [ ] 在本計劃末尾加「實作記錄」：README commit 的 hash、`tools/check-readmes.sh` 的結果、偏離計劃的地方（沒有就寫「無」）。在本文件頂端（標題下面）加一行 `> **已實作（<日期>）**：見文末實作記錄。`
- [ ] Litmus 後 commit 計劃文件：`git add docs/plans/2026-11-24-readme-usb-login.md && git commit -m "docs(plan): readme USB login plan with implementation record" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`
- [ ] 合併並推送（三條分開跑：這個環境的 hook 不讓 merge 跟 `git switch`、`git pull` 等其他 git 命令寫在同一次呼叫裏；開頭的 `cd … &&` 可以）：

```bash
cd /home/chris/Projects/ohimsmart && git switch main
cd /home/chris/Projects/ohimsmart && git merge --no-ff docs/readme-usb-login -m "Merge branch 'docs/readme-usb-login': the flashed system can be reached over USB" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
cd /home/chris/Projects/ohimsmart && test "$(git branch --show-current)" = main && git merge-base --is-ancestor docs/readme-usb-login main && test -z "$(git status --porcelain)" && tools/check-readmes.sh && git push origin main
```

Expected：merge 成功；第三行只在目前就在 `main`、分支已經整個併進 `main`、工作目錄乾淨、`check-readmes` exit 0 時才 push，push 成功。前兩行任何一行失敗（切不到 `main`、merge 被拒或出錯），就不跑第三行。merge 停在衝突時第三行不會 push：先解決衝突或 `git merge --abort`，回報。

---

## 不在這份計劃裏

- macOS、Windows 上實測 USB 登入；經 USB 開瀏覽器後台。實測後若有不同，另寫計劃改教學。
- 映像本身的任何改動。
- 維護者自己那台裝置的 SSH 埠（3722）：只改在那台裝置上，不進 repo。
- `docs/` 裏規格文件第 360 行附近同樣的舊說法（設計審查時找到）：另外處理。

---

## 實作記錄

- README：commit `921ad2e`（三個檔案各 +14 −8）。七處照計劃逐字替換，替換用的文字由腳本直接從本計劃讀出，每一處的舊行都先確認恰好出現一次。
- 檢查：`tools/check-readmes.sh` → `check-readmes: the three tutorials agree`；舊說法的 grep → `no-old-claims`；`ssh ubuntu@172.16.42.1` 三個檔案各 `1`；`git diff --stat` 只有三個 README。
- Litmus：README commit 一次通過（0 個問題）。開始前，上一份計劃文件留下的 Litmus 狀態（6/5、FAIL）由維護者用 `init-review-loop.sh --force 10` 清掉。
- 附錄裏手動設定的子網掩碼：原本請讀者照 A5 的第 3 點設（那裏是 `255.255.0.0`），計劃文件的 Litmus 指出這會讓電腦把整個 `172.16.0.0/16` 都導到 USB 線，跟裝置 DHCP 給的 `/24` 也不一致。改成在附錄直接寫 `255.255.255.0`（⑤ 已更新），由 Task 1b 另做一個 commit（在 `921ad2e` 之後、本計劃文件的 commit 之前，見 `git log`）。檢查改成 `grep -c` 逐檔看到 `0`。
- 偏離計劃：上面那一條是審查後追加的修改，其餘無。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
