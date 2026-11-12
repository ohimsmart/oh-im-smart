# 映像打包與清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 映像帶出去的更新來源、網關 remote 和使用者資料由打包流程本身保證，並以可重跑的測試證明（spec §5.3、§5.4、§5.5）。

**Spec:** `docs/specs/2026-11-09-oh-im-smart-v1-design.md`（commit 81c2859）。

**Architecture:** `sanitize-rootfs.sh` 多做帳號、家目錄、主機名稱、時區、設定檔覆寫和網關服務檔重寫；新的 `clean-hub-git.sh` 把網關的 git 整理成新裝置該有的樣子（固定的 `.git/config`、只有 `main` 和 `origin/main`、沒有其他物件和 hook）。兩個新的檢查腳本：`check-rootfs.sh` 在 `mke2fs` 之前檢查檔案樹，包括逐檔比對系統層跟 repo 是否相同；`check-image-privacy.sh` 在 `mke2fs` 之前掃描檔案樹，之後再掃描映像的原始位元組。sanitize 和檢查共用 `allowlist.sh` 和一份家目錄允許清單。兩個 sh 測試腳本在 `fakeroot` 下用合成的根檔案系統跑 sanitize 和檢查，不需要 Docker 或裝置。

**Tech Stack:** POSIX sh、awk、GNU grep（`-P`）、git、fakeroot、openssl、ssh-keygen（只用於測試）、shellcheck 0.9。

**Global Constraints:**
- 這是 v1 七份計劃中的第 1 份。其餘六份：更新器訊息 key、kiosk 語言選擇、客戶端英文、網關英文和網址、bootstrap `prepare.sh`、教學和映像 Release。本計劃不碰 README、kiosk 的翻譯和更新器的程式碼。
- 容器（`image/Dockerfile`，Ubuntu 24.04）沒有 Python。sanitize 和檢查只能用 sh、awk、grep、git 和 coreutils。
- 新增或修改的 sh 腳本必須通過 `shellcheck -x -s sh`（`-x` 讓 shellcheck 跟進 `allowlist.sh`）；`build-image.sh` 是 bash，用 `shellcheck` 檢查，不能比改動前多出新的警告。
- 所有改動放在分支 `feat/image-packaging`。merge 到 `main` 時只用 merge commit。
- **實作紀錄（2026-11-11）：** Task 7b（設計審查第 2、3 輪的修正）待做，要在 Task 8 之前完成。Task 0–7 已完成，在分支 `feat/image-packaging` 的 commit `e62ccd5`、`9b0025e`、`fb615c8`、`4e7ee07`、`d489db0`、`8849833`（Task 5 和 7 合成一個 commit）和 `e110fc1`（設計審查後的修正）。程式碼審查期間的修正都在這些 commit 裏，**以 commit 為準**：Task 1–7 的程式碼區塊和預期的測試數目是第一版的紀錄，不要照抄，也不要拿來覆蓋現在的檔案。驗收標準是兩個測試腳本 `exit 0`、沒有 `not ok`（現在 `test-sanitize.sh` 200 項、`test-image-privacy.sh` 38 項）。跟第一版不同、Task 8 會碰到的地方：
  - `build-image.sh` 的順序是 sanitize → `clean-hub-git.sh` → `check-rootfs.sh` → 檔案樹的私人資料掃描 → `mke2fs` → 映像的掃描；
  - 母機的主機名稱不是 `thinksmart`、`ubuntu`、`localhost` 時，會被當作秘密掃描（測試映像也一樣），也會列入 check-rootfs 檢查檔名的識別字串；
  - sanitize 刪除已刪帳號的 sudoers 檔，但同一個檔案也有 ubuntu 的規則時會停下；
  - ubuntu 的 shadow 行換成固定雜湊，不留密碼期限和帳號到期日；
  - check-rootfs 檢查每個檔案的擁有者和群組 id 都在 `/etc/passwd`、`/etc/group` 裏（已刪帳號留在家目錄以外的檔案）；
  - `build-image.sh` 另外掃描 boot 分割區的檔案和解開的 initramfs；`ALLOW_UNRELEASED=1` 的映像一律命名為 `-TEST-DO-NOT-PUBLISH`；正式版本拒絕未 commit 的改動；每一步的 `==` 紀錄行後面附上時間；
  - `check-image-privacy.sh` 的 `sk-` 樣式前面加了 lookbehind（`(?<![A-Za-z0-9_-])`），因為 base64url 雜湊（例如 wheel 的 `RECORD`）裏會出現 `sk-`；spec §5.3 第 5 點已同步；
  - spec §5.3 第 7 點原本寫的是把兩個設定檔複製進容器；實作改為把整個 repo 唯讀掛載為 `/repo`，因為 check-rootfs 要逐檔比對系統層。§5.4 的清理項目之外，本計劃另外處理 ubuntu 的 passwd 名稱欄、AccountsService 的頭像和資料、整個 `/etc/hosts`、`/etc/machine-info`、`machine-id` 的檢查和指向根目錄以外的連結，§5.5 加上空的 `NTP=` 和 drop-in 目錄的檢查（Task 7b）。這些都已寫進 spec 的 §5.3 第 7 點、§5.4 和 §5.5，spec 跟本計劃一起審查；
  - check-rootfs 對 sudo 設定用允許清單：`/etc/sudoers` 只能有 Ubuntu 原本的 Defaults（`env_reset`、`mail_badpass`、`use_pty`、Ubuntu 的 `secure_path`）和 `root`、`%admin`、`%sudo` 的規則，最後一行是第一欄開始的 `@includedir`（或 `#includedir`）`/etc/sudoers.d`；sudo 會讀的 `sudoers.d` 檔案只能有 `ubuntu ALL=(ALL) NOPASSWD:ALL`；檔案和目錄要屬於 root、其他人不能寫。
- 測試指令不接 `| tail`：管線的結束碼是 `tail` 的，會蓋掉失敗。
- 固定字串：
  - 更新來源 `SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"`
  - 網關 `https://github.com/ohimsmart/oh-im-smart-gateway.git`
  - 主 repo 的 Releases `https://github.com/ohimsmart/oh-im-smart/releases`
  - NTP `NTP=ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org pool.ntp.org ntp.ubuntu.com`

---

## File Structure

| 檔案 | 責任 |
|---|---|
| `image/allowlist.sh`（新） | `home_allowed`、`provenance_uncovered` 兩個函式，sanitize 和檢查共用 |
| `image/home-allowlist.txt`（新） | `~/.config/systemd`、`~/.config/pipewire`、`~/.config/wireplumber`、`~/.local` 裏允許留下的路徑 |
| `image/hub-git-config`（新） | 映像裏網關的 `.git/config`，整個檔案固定 |
| `image/hub-ignored.txt`（新） | 網關 checkout 裏允許存在、但被 git 忽略的路徑 |
| `image/clean-hub-git.sh`（新） | 網關 git 的整理：先刪 hook，再換設定、指定 commit 作 `main`、刪除其他 ref、物件，以及 `.git` 裏 git 不需要的檔案 |
| `image/xiaozhi-hub.service`（新） | 網關的用戶服務檔，內容跟網關 `scripts/autostart.sh` 寫出的相同，路徑固定為映像的路徑 |
| `image/ubuntu-password.hash`（新） | `thinksmart` 的固定 SHA-512 雜湊 |
| `image/upstream-provenance.txt`（新） | 上游網址和維護者識別字串的「路徑＋整行」允許清單 |
| `image/owner-identifiers.txt`（新） | 維護者識別字串（不含秘密） |
| `image/check-rootfs.sh`（新） | `mke2fs` 之前的檔案樹檢查 |
| `image/check-image-privacy.sh`（新） | 檔案樹和 `disk.img` 原始位元組的私人資料掃描 |
| `image/sanitize-rootfs.sh` | 新增的清理 |
| `image/build-image.sh` | 必填 `SECRETS_FILE`／`--test-image`、網關 origin、掛載 repo、呼叫 `clean-hub-git.sh` 和兩個檢查 |
| `image/tests/make-fake-root.sh`（新） | 建立合成的母機擷取結果 |
| `image/tests/test-sanitize.sh`（新） | sanitize 和 `check-rootfs.sh` 的正反測試 |
| `image/tests/test-image-privacy.sh`（新） | `check-image-privacy.sh` 的正反測試 |
| `image/tests/test-build-image.sh`（新，Task 7b） | `build-image.sh` 在 Docker 之前停下的檢查：`HUB_MAIN` 和 GitHub 的 `main` |
| `screen/vcnl4200-proximity-daemon.service`（新，Task 8） | 母機上的接近感應服務檔，收進 repo |
| `kiosk/timesyncd.conf`（由 `timesyncd-cn.conf` 改名） | NTP 伺服器 |
| `image/system-files.txt`、`image/device-setup.sh`、`update/thinksmart-update.conf`、`update/make-release.py`、`update/test_system_layer.py`、`kiosk/thinksmart-kiosk.conf`、`kiosk/welcome.html` | 網址、NTP 和時區 |

---

### Task 0: 分支

> **已完成（分支已存在）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

- [x] **建立分支**

```bash
cd /home/chris/Projects/ohimsmart
git switch feat/image-packaging   # 分支已建立（第一版是 git switch -c）
```

---

### Task 1: 主 repo 裏指向上游的網址、NTP 和時區

> **已完成（`e62ccd5`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Modify: `update/thinksmart-update.conf`、`kiosk/thinksmart-kiosk.conf`、`kiosk/welcome.html`、`update/make-release.py`、`update/test_system_layer.py`、`image/system-files.txt`、`image/device-setup.sh`
- Rename: `kiosk/timesyncd-cn.conf` → `kiosk/timesyncd.conf`

**Interfaces:**
- Produces: `kiosk/timesyncd.conf`，其中有一行跟 Global Constraints 的 NTP 字串完全相同；`system-files.txt` 把它裝到 `/etc/systemd/timesyncd.conf.d/thinksmart.conf`。Task 4 會比對這兩處。

- [x] **套用改動**

```bash
git mv kiosk/timesyncd-cn.conf kiosk/timesyncd.conf
```

`kiosk/timesyncd.conf` 整個檔案換成：

```
[Time]
# No RTC battery: the clock comes from the network on every boot, and TLS fails until it is set.
# Every server is in NTP=: once NTP= is set, timesyncd never uses FallbackNTP=. Tried in order:
# the ones reachable from China first (ntp.ubuntu.com took ~20 s there), the global ones after.
NTP=ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org pool.ntp.org ntp.ubuntu.com
```

其餘檔案照下面的 diff 修改（可以存成檔案後用 `git apply` 套用）：

```diff
--- a/update/thinksmart-update.conf
+++ b/update/thinksmart-update.conf
@@ -6,7 +6,7 @@
 #   Whoever serves these addresses decides what gets installed (as root): list only addresses you
 #   control or trust, never a public GitHub download mirror or proxy site.
 # Client releases are published on the client repository's GitHub Releases.
-SOURCES="https://github.com/justhalfbit/xiaozhi-thinksmart-client/releases/"
+SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"
 # HTTP proxy for the checks and downloads, e.g. http://proxy.example:8080 (empty: direct)
 PROXY=""
 # Group that may drop requests (the client and the kiosk run as ubuntu)
--- a/kiosk/thinksmart-kiosk.conf
+++ b/kiosk/thinksmart-kiosk.conf
@@ -13,5 +13,5 @@
 # inside freedreno together and the page freezes (seen with the v2 client UI)
 WEBKIT_ENV="FD_MESA_DEBUG=sysmem WEBKIT_FORCE_VBLANK_TIMER=1 WEBKIT_SKIA_ENABLE_CPU_RENDERING=1"
 # Where the welcome page's QR code points (install guide)
-#HELP_URL="https://github.com/justhalfbit/xiaozhi-hub-server"
+#HELP_URL="https://github.com/ohimsmart/oh-im-smart-gateway"
 #WEBKIT_FEATURES="-UnifyDamagedRegions"   # switch WebKit feature flags (names: WebKit2.Settings.get_all_features())
--- a/kiosk/welcome.html
+++ b/kiosk/welcome.html
@@ -300,7 +300,7 @@
     $('statusText').textContent = '还没有设置展示页面';
     $('statusSub').textContent = '按右侧的方法装上小智客户端，或设置你自己的地址';
   }
-  drawQr(st.help || 'https://github.com/justhalfbit/xiaozhi-hub-server');
+  drawQr(st.help || 'https://github.com/ohimsmart/oh-im-smart-gateway');
 };
 
 /* ---- talking to thinksmart-kiosk.py ---- */
--- a/update/make-release.py
+++ b/update/make-release.py
@@ -203,7 +203,7 @@
     # what to paste into the release: people who land on this page should know it isn't for them
     title = f'在线更新：客户端 {version}' + (f' · 系统层 {system[0]}' if system else '')
     body = ['这些文件是设备在线更新时自动下载的，**不需要手动下载**：在设备的设置页「软件更新」里点「更新」就行。',
-            '要刷机请到 [thinksmart-ubuntu-image 的 Releases](https://github.com/justhalfbit/thinksmart-ubuntu-image/releases) 下载镜像。',
+            '要刷机请到 [oh-im-smart 的 Releases](https://github.com/ohimsmart/oh-im-smart/releases) 下载镜像。',
             '', f'### 客户端 {version}', *[f'- {n}' for n in args.note or ['（没有说明）']]]
     if system:
         body += ['', f'### 系统层 {system[0]}', *[f'- {n}' for n in args.system_note or ['（没有说明）']]]
--- a/update/test_system_layer.py
+++ b/update/test_system_layer.py
@@ -370,7 +370,7 @@
         names = t.getnames()
         assert 'image/system-files.txt' in names and 'kiosk/thinksmart-kiosk.py' in names
     text = (out / f'release-{tag}.txt').read_text()
-    assert '不需要手动下载' in text and 'thinksmart-ubuntu-image' in text
+    assert '不需要手动下载' in text and 'ohimsmart/oh-im-smart/releases' in text
     # the same files again: fine; a changed file with the same VERSION: refused
     assert subprocess.run(mk, capture_output=True).returncode == 0
     (img / 'kiosk' / 'welcome.html').write_text('changed')
--- a/image/system-files.txt
+++ b/image/system-files.txt
@@ -59,7 +59,7 @@
 # memory, time, network, crash dumps, SSH host keys
 zram/thinksmart-zram.service        /etc/systemd/system/thinksmart-zram.service     644 root boot
 zram/99-zram.conf                   /etc/sysctl.d/99-zram.conf                      644 root boot
-kiosk/timesyncd-cn.conf             /etc/systemd/timesyncd.conf.d/thinksmart.conf   644 root system:systemd-timesyncd.service
+kiosk/timesyncd.conf                /etc/systemd/timesyncd.conf.d/thinksmart.conf   644 root system:systemd-timesyncd.service
 kiosk/wifi-powersave-off.conf       /etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf 644 root boot
 kiosk/coredump-off.conf             /etc/systemd/coredump.conf.d/90-thinksmart-kiosk.conf 644 root none
 image/thinksmart-ssh-hostkeys.service /etc/systemd/system/thinksmart-ssh-hostkeys.service 644 root none
--- a/image/device-setup.sh
+++ b/image/device-setup.sh
@@ -94,11 +94,9 @@
         > /etc/systemd/journald.conf.d/thinksmart.conf
     install -d -g systemd-journal -m 2755 /var/log/journal
     systemctl restart systemd-journald
-    timedatectl set-timezone Asia/Shanghai
     # rsyslog wrote every journal line again into /var/log, outside the journal's cap (169 MB there)
     systemctl disable --now rsyslog.service 2>/dev/null || true
     rm -f /var/log/syslog* /var/log/auth.log* /var/log/kern.log* /var/log/user.log* /var/log/messages*
-    echo Asia/Shanghai > /etc/timezone
     # Earlier experiments: py-xiaozhi and the first chat page (replaced by thinksmart-client), Plasma-era helpers
     systemctl disable --now py-xiaozhi.service 2>/dev/null || true
     rm -f /etc/systemd/system/py-xiaozhi.service /usr/local/bin/thinksmart-chat.py /usr/local/bin/screen-wake-daemon.py.july
```

`test_system_layer.py` 原本斷言發佈說明含 `thinksmart-ubuntu-image`，那是 `make-release.py` 改掉的那一行，所以斷言跟着改。`device-setup.sh` 刪掉兩行寫死 `Asia/Shanghai` 的設定：新映像的時區由 sanitize 設為 `Etc/UTC`（Task 5），用戶按教學用 `timedatectl` 設定。

- [x] **確認主 repo 裏除 README 外只剩 build-image.sh 還指向上游**

Run: `git grep -n justhalfbit -- . ':!README*' ':!docs' ':!kiosk/qrcode.js'`
Expected: 只剩 `image/build-image.sh` 的兩行（第 14 行註解和第 148 行 remote，Task 7 改）。

- [x] **跑現有測試**

Run: `GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q update kiosk screen`
Expected: 全部 PASS。`GIT_CONFIG_GLOBAL=/dev/null` 是必要的：UM 的全域設定 `tag.gpgsign=true` 會令 `test_make_release_carries_the_system_layer` 的 `git tag` 失敗。`screen/test_idle_blanker.py` 有幾項會隨當時的時刻而失敗（改動前的 `main` 也一樣）。如果只有它們失敗，單獨重跑 `screen` 確認。

- [x] **Commit**

```bash
git add -A update kiosk image/system-files.txt image/device-setup.sh
git commit -m "Point sources at ohimsmart; NTP= holds every server; no hard-coded time zone"
```

---

### Task 2: 允許清單、網關服務檔和固定雜湊

> **已完成（`9b0025e`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Create: `image/allowlist.sh`、`image/home-allowlist.txt`、`image/xiaozhi-hub.service`、`image/hub-git-config`、`image/hub-ignored.txt`、`image/ubuntu-password.hash`、`image/upstream-provenance.txt`、`image/owner-identifiers.txt`

**Interfaces:**
- Produces: `home_allowed REL_PATH`（sh 函式，需要先設定 `HOME_ALLOW`）：`REL_PATH` 相對於 `/home/ubuntu`，在清單上時回傳 0。清單裏以 `/` 結尾的條目代表整個目錄。
- Produces: `provenance_uncovered ROOT LIST`（sh 函式）：stdin 讀 `grep -rn` 的命中行（`ROOT/path:行號:內容`），印出 `LIST` 沒有涵蓋的命中（`/path:內容`）。`file` 條目只涵蓋 `/` 數目跟樣式相同的路徑，因為 `case` 的 `*` 也會比對到 `/`（`LICENSE*` 不能涵蓋 `LICENSES/install.sh`）。
- Produces: `image/hub-git-config`。`clean-hub-git.sh` 把它複製成網關的 `.git/config`，check-rootfs 逐位元組比對。
- Produces: `image/hub-ignored.txt`。check-rootfs 要求網關 checkout 裏被忽略的路徑（`git ls-files --others --ignored --exclude-standard --directory` 的輸出）都在這份清單上。
- Produces: `image/xiaozhi-hub.service`。sanitize 用它覆寫母機的網關服務檔，check-rootfs 逐位元組比對。

- [x] **image/allowlist.sh**

```sh
# shellcheck shell=sh
# Shared by sanitize-rootfs.sh and check-rootfs.sh (sourced, not run).

# home_allowed REL: is /home/ubuntu/REL on home-allowlist.txt ($HOME_ALLOW)? An entry ending in /
# covers everything under it.
home_allowed() {
    while IFS= read -r e; do
        case $e in
            ''|'#'*) ;;
            */) case $1 in "$e"*) return 0 ;; esac ;;
            *) [ "$1" = "$e" ] && return 0 ;;
        esac
    done < "$HOME_ALLOW"
    return 1
}

# provenance_uncovered ROOT LIST: reads grep -rn hits (ROOT/path:line:content) on stdin and prints
# "/path:content" for each one LIST does not allow. LIST lines (tab separated):
#   file<TAB>PATTERN        the whole file (shell pattern on the path)
#   line<TAB>PATH<TAB>LINE  that exact line of that file
# A file pattern covers only paths with as many / as itself (in case, * also matches /).
# A path that itself holds ":<digits>:" is split wrongly and so reported: fail closed.
provenance_uncovered() {
    tab=$(printf '\t')
    while IFS= read -r hit; do
        rest=${hit#"$1"}
        path=${rest%%:*}; rest=${rest#*:}; content=${rest#*:}
        ok=1
        while IFS=$tab read -r kind a b; do
            case $kind in
                file)
                    # shellcheck disable=SC2254 # $a is a shell pattern on purpose
                    case $path in $a)
                        [ "$(printf %s "$path" | tr -cd /)" = "$(printf %s "$a" | tr -cd /)" ] && ok=0 ;;
                    esac ;;
                line) [ "$path" = "$a" ] && [ "$content" = "$b" ] && ok=0 ;;
            esac
            [ $ok = 0 ] && break
        done < "$2"
        [ $ok = 0 ] || printf '%s:%s\n' "$path" "$content"
    done
}
```

- [x] **image/home-allowlist.txt**

`vcnl4200-proximity-daemon.service` 在清單上，因為 `kiosk/thinksmart-kiosk-app` 會啟動它，但這個服務檔目前只存在於母機。Task 8 會把它收進 repo。

```
# What may stay under /home/ubuntu/.config/systemd/user, .config/pipewire, .config/wireplumber and
# .local in a release image (spec §5.4). sanitize-rootfs.sh deletes every other file and link
# there (and prints each one); check-rootfs.sh requires exactly these. An entry ending in / is a
# whole directory. Entries under a *.wants/ directory must be links to a unit on this list, the
# others regular files.
# system-files.txt and system-post.sh: user units and their links, audio settings
.config/systemd/user/idle-blanker.service
.config/systemd/user/thinksmart-mic.service
.config/systemd/user/vcnl4200-proximity-daemon.service
.config/systemd/user/default.target.wants/idle-blanker.service
.config/systemd/user/default.target.wants/thinksmart-mic.service
.config/systemd/user/pipewire-pulse.service.wants/thinksmart-mic.service
.config/pipewire/pipewire.conf.d/10-thinksmart-rate.conf
.config/wireplumber/main.lua.d/99-cd18781y-alsa.lua
# the gateway's unit (sanitize writes it from image/xiaozhi-hub.service): without it and its link
# the gateway does not start at boot
.config/systemd/user/xiaozhi-hub.service
.config/systemd/user/default.target.wants/xiaozhi-hub.service
# the Python the gateway's .venv runs on, and uv, which the gateway's scripts/install.sh needs
.local/share/uv/
.local/bin/uv
.local/bin/uvx
```

- [x] **image/xiaozhi-hub.service**

內容跟網關 `scripts/autostart.sh` 的 `linux_enable` 寫出的服務檔相同，`ROOT`、`SERVER` 和 `PATH` 固定為映像的值。母機上那份可能被加了 `Environment=` 和 key，所以不保留。

```
[Unit]
Description=xiaozhi-hub-server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server
Environment="PATH=/home/ubuntu/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" SKIP_DOCTOR=1 HUB_AUTOSTART=1 PYTHONUTF8=1
ExecStart=/bin/bash "/home/ubuntu/xiaozhi-hub-server/scripts/start.sh"
Restart=on-failure
RestartSec=30
StandardOutput=null

[Install]
WantedBy=default.target
```

- [x] **image/hub-git-config**

整個檔案固定，所以母機設定裏的 `url.*.insteadOf`、`http.proxy`、`http.extraHeader` 和 `include` 都不會帶進映像。檔案裏的縮排是 Tab。

```
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
[remote "origin"]
	url = https://github.com/ohimsmart/oh-im-smart-gateway.git
	fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
	remote = origin
	merge = refs/heads/main
```

- [x] **image/hub-ignored.txt**

`git status` 不列出被忽略的檔案，所以母機上的 `.env`、日誌或本機資料庫會無聲無息地跟着映像出去。這份清單先只有 sanitize 自己寫的兩個目錄；網關的 `.venv` 等實際路徑在 Task 8 第一次真正擷取時看見後才加入，每一條都要說得出是甚麼。（實作時已加入網關的 `main/xiaozhi-server/.venv/`：`scripts/start.sh` 用它的 Python，check-rootfs 也要求它在。）

```
# Paths in the gateway checkout that git ignores and the image may carry, as
# `git ls-files --others --ignored --exclude-standard --directory` prints them (spec §5.3 point 3).
# check-rootfs.sh fails on any other ignored path: a .env, logs or a local database would otherwise
# ship unseen, since git status does not list ignored files. sanitize-rootfs.sh writes these two.
main/xiaozhi-server/data/
main/xiaozhi-server/tmp/
```

- [x] **image/upstream-provenance.txt**

`file` 那四行的欄位之間是一個 Tab，不是空格。

```
# Lines of the image's file tree that may name the upstream author or the maintainer
# (spec §5.3 point 5); check-rootfs.sh fails on any other hit. Paths are relative to the image
# root and start with /. Fields are tab separated:
#   file<TAB>PATTERN        whole file, only for LICENSE*/NOTICE* (a README holds install commands)
#   line<TAB>PATH<TAB>LINE  that exact line, e.g. a README badge or the weather plugin's User-Agent
file	/home/ubuntu/xiaozhi-hub-server/LICENSE*
file	/home/ubuntu/xiaozhi-hub-server/NOTICE*
file	/opt/thinksmart/client/*/LICENSE*
file	/opt/thinksmart/client/*/NOTICE*
```

- [x] **image/owner-identifiers.txt**

```
# Strings that identify the maintainer or the mother device, one per line, searched for as whole
# words (grep -wF) in the image's file tree (spec §5.3 point 5). No secrets here: e-mail addresses,
# Wi-Fi names and keys go in SECRETS_FILE. build-image.sh adds the mother device's hostname itself.
chris-yyau
```

- [x] **image/ubuntu-password.hash**

```bash
openssl passwd -6 -salt ohimsmartv1 thinksmart > image/ubuntu-password.hash
cat image/ubuntu-password.hash
```

Expected:

```
$6$ohimsmartv1$.n.mLoVGnDvvdm/pR9FBCZ98pd5JR9rVyGeZlFfhh2zbcWIVWb5qLGJkYiTK/bkejIj3mvan.eb2oIHW8xbRi.
```

- [x] **檢查**

Run: `shellcheck -x -s sh image/allowlist.sh && grep -c "$(printf '\t')" image/upstream-provenance.txt`
Expected: shellcheck 沒有輸出；計數是 `4`。

- [x] **Commit**

```bash
git add image/allowlist.sh image/home-allowlist.txt image/xiaozhi-hub.service image/hub-git-config image/hub-ignored.txt image/ubuntu-password.hash image/upstream-provenance.txt image/owner-identifiers.txt
git commit -m "Image allowlists, the gateway unit and the published ubuntu hash"
```

---

### Task 3: 合成的母機擷取結果

> **已完成（`fb615c8`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Create: `image/tests/make-fake-root.sh`

**Interfaces:**
- Produces: `make-fake-root.sh DIR`（在 `fakeroot` 下執行）：在 `DIR` 建立一個像母機擷取結果的根檔案系統，並寫入 `DIR/../template.yaml`。內容如下：
  - 按 `system-files.txt` 裝好的系統層；
  - 舊的兩個 keep 檔；
  - 多一個 `alice` 帳號，帶群組成員資格、crontab、mail、`sudoers.d` 檔和 AccountsService 記錄；
  - `/home/retired`：沒有帳號擁有的家目錄（`userdel` 沒加 `-r` 時留下的）；
  - locate 資料庫；
  - 一個沒有帳號的私人群組 `carol`；
  - 系統帳號 `www-data`，以及一個同名、GID 在 1000–59999 之間的私人群組；
  - `~/.config/systemd/user.conf`，帶 `DefaultEnvironment=` 和 key；
  - 家目錄裏的多餘檔案；
  - 帶 key 的網關服務檔，以及 `systemctl --user enable` 寫出的絕對路徑連結；
  - 舊的主機名稱 `mother-host`；
  - 上一版客戶端和系統層備份；
  - origin 已指向 ohimsmart 的網關 clone，帶一個已發佈的 commit，以及一個只靠 tag 保留的未發佈 commit（它的 `COMMIT_EDITMSG` 留在 `.git`）、一條 `insteadOf`、`MERGE_MSG`、會被 `.gitignore` 忽略的 `.env` 規則，和三個 hook。其中 `post-checkout` 和 `reference-transaction` 一旦執行就會在 `data/` 留下記號檔，用來證明整理時沒有執行任何 hook；
  - 帶 `insteadOf` 的 `/etc/gitconfig`；
  - kiosk 語言狀態檔。

接近感應服務檔只在系統層沒有裝它時才放一份替代內容，所以 Task 8 把它加進 `system-files.txt` 之後，這個腳本不用改。

- [x] **image/tests/make-fake-root.sh**

```sh
#!/bin/sh
# A root filesystem shaped like a capture of the mother device, carrying this repository's system
# layer and everything sanitize must remove. Run under fakeroot:
#   fakeroot sh image/tests/make-fake-root.sh DIR
# Also writes DIR/../template.yaml (the gateway's config template).
set -eu
R=${1:?dir}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$R"
cd "$R"
mkdir -p etc/skel etc/sudoers.d etc/NetworkManager/system-connections etc/ssh lib/modules root/.aws \
    var/log var/lib/dbus var/lib/systemd var/lib/thinksmart-update var/spool/cron/crontabs var/mail \
    tmp var/tmp usr/share/zoneinfo/Etc usr/local home/alice home/ubuntu/xiaozhi-workspace \
    opt/thinksmart/system/backup opt/thinksmart/client/1.0.0 opt/thinksmart/client/0.1.6 \
    opt/thinksmart/envs/new opt/thinksmart/envs/old

# the system layer, as image/device-setup.sh files puts it there
grep -v -e '^#' -e '^[[:space:]]*$' -e '^require ' "$REPO/image/system-files.txt" | while read -r src dst _; do
    [ "$src" = - ] && continue
    mkdir -p "$R${dst%/*}"
    cp "$REPO/$src" "$R$dst"
done
# the mother device's keep files differ from the repository's: sanitize must replace them
echo 'SOURCES="https://github.com/justhalfbit/xiaozhi-thinksmart-client/releases/"' > etc/thinksmart-update.conf
echo '#HELP_URL="https://github.com/justhalfbit/xiaozhi-hub-server"' > etc/thinksmart-kiosk.conf

cat > etc/passwd <<'E'
root:x:0:0:root:/root:/bin/bash
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
alice:x:1001:1001:Alice:/home/alice:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
E
cat > etc/shadow <<'E'
root:$6$old$roothash:19000:0:99999:7:::
www-data:*:19000:0:99999:7:::
ubuntu:$6$old$ubuntuhash:19000:0:99999:7:::
alice:$6$old$alicehash:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
E
cat > etc/group <<'E'
root:x:0:
sudo:x:27:ubuntu,alice
audio:x:29:alice,ubuntu
ubuntu:x:1000:
alice:x:1001:
carol:x:1003:
www-data:x:1005:
E
cat > etc/gshadow <<'E'
root:*::
sudo:*:alice:ubuntu,alice
audio:*::alice,ubuntu
ubuntu:!::
alice:!::
carol:!::
www-data:!::
E
printf 'ubuntu:100000:65536\nalice:165536:65536\n' > etc/subuid
cp etc/subuid etc/subgid
for f in passwd shadow group gshadow subuid subgid; do cp "etc/$f" "etc/$f-"; done
chmod 640 etc/shadow etc/gshadow

echo 'alice ALL=(ALL) NOPASSWD:ALL' > etc/sudoers.d/alice
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > etc/sudoers.d/90-ubuntu
echo '* * * * * curl example.com' > var/spool/cron/crontabs/alice
echo 'mail' > var/mail/alice

printf '# skel bashrc\n' > etc/skel/.bashrc
printf '# skel profile\n' > etc/skel/.profile
printf '# skel logout\n' > etc/skel/.bash_logout
echo mother-host > etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\tmother-host\n' > etc/hosts
echo Asia/Shanghai > etc/timezone
: > usr/share/zoneinfo/Etc/UTC
ln -s /usr/share/zoneinfo/Asia/Shanghai etc/localtime

echo 'export TOKEN=root-token' > root/.bashrc
echo 'export TOKEN=root-token' > root/.profile
echo '[default]' > root/.aws/credentials
echo 'alice' > home/alice/notes
# left by userdel without -r: no account owns it
mkdir -p home/retired; echo 'diary' > home/retired/diary.txt
mkdir -p var/lib/AccountsService/users var/lib/plocate
echo '[User]' > var/lib/AccountsService/users/alice
echo 'every file name' > var/lib/plocate/plocate.db

H=home/ubuntu
echo 'export TOKEN=user-token' > $H/.bashrc
echo 'export TOKEN=user-token' > $H/.profile
echo 'clear' > $H/.bash_logout
U=$H/.config/systemd/user
mkdir -p $U/default.target.wants $U/pipewire-pulse.service.wants $H/.config/thinksmart-kiosk \
    $H/.local/share/uv/python/bin $H/.local/bin $H/.local/state/wireplumber
# a stand-in until the system layer carries this unit (plan Task 8)
[ -e $U/vcnl4200-proximity-daemon.service ] || printf '[Unit]\n' > $U/vcnl4200-proximity-daemon.service
# systemd's per-user manager settings: DefaultEnvironment= can hold a key
echo 'DefaultEnvironment=API_KEY=sk-user-conf' > $H/.config/systemd/user.conf
printf '[Service]\nEnvironment=API_KEY=sk-from-the-mother\n' > $U/xiaozhi-hub.service
echo 'Environment=API_KEY=sk-leak' > $U/leak.service
ln -s ../idle-blanker.service $U/default.target.wants/idle-blanker.service
ln -s ../thinksmart-mic.service $U/default.target.wants/thinksmart-mic.service
# systemctl --user enable writes absolute links
ln -s /home/ubuntu/.config/systemd/user/xiaozhi-hub.service $U/default.target.wants/xiaozhi-hub.service
ln -s ../leak.service $U/default.target.wants/leak.service
ln -s ../thinksmart-mic.service $U/pipewire-pulse.service.wants/thinksmart-mic.service
echo old > $H/.config/pipewire/pipewire.conf.d/20-experiment.conf
echo en > $H/.config/thinksmart-kiosk/lang
echo py > $H/.local/share/uv/python/bin/python3
echo uv > $H/.local/bin/uv
echo uvx > $H/.local/bin/uvx
echo 'token' > $H/.local/bin/my-script
echo state > $H/.local/state/wireplumber/default-routes

HUB=$H/xiaozhi-hub-server
mkdir -p $HUB/main/xiaozhi-server/data $HUB/scripts
echo 'secret: 1' > $HUB/main/xiaozhi-server/data/.config.yaml
echo 'MIT License, Copyright (c) justhalfbit, https://github.com/justhalfbit/xiaozhi-hub-server' > $HUB/LICENSE
echo 'echo install' > $HUB/scripts/bootstrap.sh
echo 'print(1)' > $HUB/main/xiaozhi-server/app.py
# the gateway checkout as the mother device has it: the published commit, plus an unpublished one
# kept only by a tag, a mirror insteadOf, a hook; and a system-wide insteadOf
printf 'main/xiaozhi-server/data/\nmain/xiaozhi-server/tmp/\n.env\n' > $HUB/.gitignore
FG() { git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false -C $HUB "$@"; }
FG init -q -b main
FG remote add origin https://github.com/ohimsmart/oh-im-smart-gateway.git
FG add -A
FG commit -q -m published
echo 'private notes' > $HUB/notes.txt
FG add notes.txt
FG commit -q -m private
FG tag private-work
FG reset -q --hard HEAD~1
FG config url.https://mirror.example/.insteadOf https://github.com/
printf '#!/bin/sh\n' > $HUB/.git/hooks/post-merge
# hooks that would fire during the cleanup's checkout and ref updates: each leaves a marker
for h in post-checkout reference-transaction; do
    # shellcheck disable=SC2016 # $(...) is for the hook to run, not for now
    printf '#!/bin/sh\ntouch "$(git rev-parse --show-toplevel)/main/xiaozhi-server/data/%s-ran"\n' $h > $HUB/.git/hooks/$h
    chmod +x $HUB/.git/hooks/$h
done
echo 'merge msg' > $HUB/.git/MERGE_MSG
printf '[url "https://mirror.example/"]\n\tinsteadOf = https://github.com/\n' > etc/gitconfig

ln -s 1.0.0 opt/thinksmart/client/current
ln -s 0.1.6 opt/thinksmart/client/previous
ln -s ../../envs/new opt/thinksmart/client/1.0.0/.venv
ln -s ../../envs/old opt/thinksmart/client/0.1.6/.venv
echo 'https://github.com/justhalfbit/xiaozhi-thinksmart-client' > opt/thinksmart/client/0.1.6/README.md
echo 'https://github.com/justhalfbit/thinksmart-ubuntu-image' > opt/thinksmart/system/backup/conf

chown -R 1000:1000 home/ubuntu
chown -R 1001:1001 home/alice
printf '  LLM: ClaudeCLI\n' > ../template.yaml
```

- [x] **檢查**

Run: `shellcheck -x -s sh image/tests/make-fake-root.sh && t=$(mktemp -d) && fakeroot sh image/tests/make-fake-root.sh "$t/root" && ls "$t/root/home"; rm -rf "$t"`
Expected: 印出 `alice  ubuntu`。

- [x] **Commit**

```bash
git add image/tests/make-fake-root.sh
git commit -m "Image tests: synthetic capture of the mother device"
```

---

### Task 4: check-rootfs.sh

> **已完成（`4e7ee07`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Create: `image/check-rootfs.sh`

**Interfaces:**
- Consumes: `image/allowlist.sh` 和 Task 2 的清單檔。
- Produces: `check-rootfs.sh ROOT IDENTIFIERS_FILE REPO`。每一項不符合都印一行 `check-rootfs: …`；全部通過時印 `check-rootfs: ok`、結束碼 0；有任何不符合時結束碼 1；參數或工具錯誤時結束碼 2。
  - `IDENTIFIERS_FILE`：`owner-identifiers.txt` 加上母機主機名稱，由 build-image.sh 組成。
  - `REPO`：本 repo。系統層的每一個檔案都要跟 repo 裏的版本相同；母機如果還帶着舊的系統層（例如舊的 NTP 設定或舊的 `welcome.html`），這一步會擋下來。

整個腳本以 `LC_ALL=C` 執行：在 UTF-8 locale 下，GNU grep `-I` 會把含有不合法 UTF-8 位元組的文字檔當成二進位檔跳過，測試（UM，UTF-8）和容器（POSIX）掃描的範圍就會不同。

各項檢查：

| 項目 | 規則 |
|---|---|
| 更新來源 | 完整的 `SOURCES=` 一行 |
| 網關的 git | `.git/config` 跟 `image/hub-git-config` 相同；沒有 `/etc/gitconfig`；ref 只有 `refs/heads/main` 和 `refs/remotes/origin/main`；`git fsck --unreachable` 沒有結果；`.git` 第一層只有 `HEAD config index objects refs packed-refs shallow hooks`；`hooks/` 裏只有 `*.sample`。檢查本身也以 `core.hooksPath=/dev/null` 執行 git |
| 網關被忽略的檔案 | 都在 `image/hub-ignored.txt` 上 |
| 網關的 `data/` | 只有 `.config.yaml` 和 `.install-complete`（build-image.sh 原有的檢查在整理 git 之前，這裏再查一次） |
| 系統層 | 逐檔跟 repo 相同 |
| 網關服務檔 | 跟 `image/xiaozhi-hub.service` 相同 |
| 上游網址、維護者識別字串（以整個字詞比對） | 只能出現在允許清單的位置 |
| `ubuntu` | 雜湊等於已公開的固定雜湊 |
| `root` | 已鎖定 |
| 其他帳號和群組 | UID／GID 1000–59999 之間不能有 `ubuntu` 以外的 |
| `sudo` 群組 | 包含 `ubuntu`：`root` 已鎖定，這是唯一的管理途徑 |
| `/home` | 只有 `ubuntu` |
| `shadow`、`subuid`、`subgid`、`gshadow` 和群組成員 | 不能指向已不存在的帳號或群組 |
| `-` 備份檔 | 不存在 |
| `/root` | 只有 `.bashrc`、`.profile` |
| shell 啟動檔 | 跟 skel 相同 |
| 家目錄的第一層和 `~/.config` 的第一層 | 只有 sanitize 保留的名字（包括 `..name` 這種 `.[!.]*` 比對不到的名字） |
| 家目錄的四個目錄 | 恰好是允許清單上的路徑：服務檔必須是一般檔案；`*.wants/` 裏的必須是指向同名服務檔的連結，而且該服務檔存在於映像內 |
| kiosk 語言狀態檔 | 不存在 |
| 主機名稱、`hosts`、時區 | 符合公開預設值 |
| NTP | 完整的 `NTP=` 一行 |
| 更新器 | 沒有未完成的更新（`pending.json`、`system-pending.json`）、沒有系統層備份；客戶端目錄只有現行版本和 `current`；現行版本的 `.venv` 指向 `../../envs/<id>`，`envs/` 裏只有那一個 |

- [x] **image/check-rootfs.sh**

```sh
#!/bin/sh
# File-tree checks on a sanitized root filesystem, run before mke2fs (spec §5.3, §5.4, §5.5):
#   check-rootfs.sh ROOT IDENTIFIERS_FILE REPO
# REPO is this repository (its system layer is compared file by file). Prints every failure;
# exits 1 if any, 2 on a usage or tool error.
set -eu
# grep -I and the patterns behave the same in the container (POSIX locale) and in the tests
export LC_ALL=C
R=${1:?root}; IDS=${2:?identifiers file}; REPO=${3:?repository}
S=$(cd "$(dirname "$0")" && pwd)
HOME_ALLOW=$S/home-allowlist.txt
PROV=$S/upstream-provenance.txt
# shellcheck source=image/allowlist.sh
. "$S/allowlist.sh"
[ -d "$R/etc" ] || { echo "check-rootfs: $R is not a root filesystem"; exit 2; }
H=$R/home/ubuntu
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
bad() { echo "check-rootfs: $*"; fail=1; }
# grep that tells "no match" (1) from an error (2+)
search() { rc=0; grep "$@" || rc=$?; [ "$rc" -le 1 ] || { echo "check-rootfs: grep failed: $*"; exit 2; }; }
# the names in a directory, sorted, on one line
names() { find "$1" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' '; }

# --- update source and gateway remote (§5.3 points 1, 3, 5)
grep -qxF 'SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"' "$R/etc/thinksmart-update.conf" \
    || bad "thinksmart-update.conf does not carry the ohimsmart SOURCES line"
# the gateway checkout as clean-hub-git.sh leaves it: our config only, main and origin/main only,
# nothing unreachable (a deleted tag's commits), nothing else in .git, no hooks, no ignored file
# outside image/hub-ignored.txt, data/ as sanitize wrote it
HUB=$H/xiaozhi-hub-server
G() { git -c safe.directory='*' -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$HUB" "$@"; }
cmp -s "$S/hub-git-config" "$HUB/.git/config" || bad "the gateway's .git/config is not image/hub-git-config"
[ ! -e "$R/etc/gitconfig" ] || bad "/etc/gitconfig is there (it can redirect the gateway's fetches)"
refs=$(G for-each-ref --format='%(refname)' | tr '\n' ' ') || bad "git for-each-ref failed in the gateway"
[ "$refs" = "refs/heads/main refs/remotes/origin/main " ] || bad "gateway refs besides main and origin/main: $refs"
if out=$(G fsck --unreachable --no-reflogs --no-progress 2>&1); then
    case $out in *unreachable*) bad "the gateway holds unreachable objects (run clean-hub-git.sh)" ;; esac
else
    bad "git fsck failed in the gateway"
fi
[ -z "$(find "$HUB/.git/hooks" ! -type d ! -name '*.sample' 2>/dev/null)" ] || bad "the gateway has git hooks"
for f in "$HUB"/.git/* "$HUB"/.git/.[!.]* "$HUB"/.git/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in HEAD|config|index|objects|refs|packed-refs|shallow|hooks) ;; *) bad "the gateway's .git holds ${f##*/}" ;; esac
    fi
done
G ls-files --others --ignored --exclude-standard --directory > "$T/ignored" || bad "git ls-files failed in the gateway"
grep -v -e '^#' -e '^$' "$S/hub-ignored.txt" | sort > "$T/ignored.ok"
sort "$T/ignored" | comm -23 - "$T/ignored.ok" > "$T/x"
[ ! -s "$T/x" ] || bad "ignored files in the gateway not on hub-ignored.txt: $(tr '\n' ' ' < "$T/x")"
[ "$(names "$HUB/main/xiaozhi-server/data")" = ".config.yaml .install-complete " ] \
    || bad "the gateway's data/ is not fresh: $(names "$HUB/main/xiaozhi-server/data")"

# --- the system layer is this repository's, file for file (an older one still names upstream)
grep -v -e '^#' -e '^[[:space:]]*$' -e '^require ' "$REPO/image/system-files.txt" | while read -r src dst _; do
    [ "$src" = - ] && continue
    cmp -s "$REPO/$src" "$R$dst" || echo "$dst is not this repository's $src"
done > "$T/layer"
[ ! -s "$T/layer" ] || { bad "system layer differs (install this branch's layer on the device first):"; cat "$T/layer"; }
cmp -s "$S/xiaozhi-hub.service" "$H/.config/systemd/user/xiaozhi-hub.service" \
    || bad "the gateway unit is not image/xiaozhi-hub.service"

# --- upstream URLs and owner identifiers in the file tree (§5.3 point 5)
search -rInE '(github(usercontent)?\.com[/:]|githubusercontent\.com/)justhalfbit' "$R" > "$T/up"
grep -v -e '^#' -e '^[[:space:]]*$' "$IDS" > "$T/ids" || { echo "check-rootfs: $IDS lists nothing"; exit 2; }
search -rInwF -f "$T/ids" "$R" > "$T/own"
provenance_uncovered "$R" "$PROV" < "$T/up" > "$T/up.bad"
provenance_uncovered "$R" "$PROV" < "$T/own" > "$T/own.bad"
[ ! -s "$T/up.bad" ] || { bad "upstream URLs:"; head -20 "$T/up.bad"; }
[ ! -s "$T/own.bad" ] || { bad "owner identifiers:"; head -20 "$T/own.bad"; }

# --- accounts (§5.4)
hash=$(cat "$S/ubuntu-password.hash")
awk -F: -v h="$hash" '$1 == "ubuntu" && $2 == h {f = 1} END {exit !f}' "$R/etc/shadow" \
    || bad "ubuntu's password hash is not ubuntu-password.hash"
awk -F: '$1 == "root" && $2 == "!" {f = 1} END {exit !f}' "$R/etc/shadow" || bad "root is not locked"
others=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/passwd" "$R/etc/group" | sort -u | tr '\n' ' ')
[ -z "$others" ] || bad "people or their groups besides ubuntu: $others"
cut -d: -f1 "$R/etc/passwd" | sort > "$T/users"
cut -d: -f1 "$R/etc/group" | sort > "$T/groups"
for f in shadow subuid subgid; do
    if [ -e "$R/etc/$f" ]; then
        cut -d: -f1 "$R/etc/$f" | sort | comm -23 - "$T/users" | sed "s|^|$f names a removed account: |"
    fi
done > "$T/x"
[ ! -s "$T/x" ] || bad "$(cat "$T/x")"
if [ -e "$R/etc/gshadow" ]; then
    cut -d: -f1 "$R/etc/gshadow" | sort | comm -23 - "$T/groups" > "$T/x"
    [ ! -s "$T/x" ] || bad "gshadow names a removed group: $(tr '\n' ' ' < "$T/x")"
fi
{ cut -d: -f4 "$R/etc/group"; if [ -e "$R/etc/gshadow" ]; then cut -d: -f3,4 "$R/etc/gshadow" | tr : ,; fi; } \
    | tr , '\n' | sed '/^$/d' | sort -u | comm -23 - "$T/users" > "$T/x"
[ ! -s "$T/x" ] || bad "group members without an account: $(tr '\n' ' ' < "$T/x")"
awk -F: '$1 == "sudo" {n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] == "ubuntu") f = 1} END {exit !f}' "$R/etc/group" \
    || bad "ubuntu is not in the sudo group (root is locked: no way to administer the device)"
[ "$(names "$R/home")" = "ubuntu " ] || bad "/home holds more than ubuntu: $(names "$R/home")"
for f in shadow- passwd- group- gshadow- subuid- subgid-; do
    [ ! -e "$R/etc/$f" ] || bad "/etc/$f is still there"
done

# --- /root and shell startup files (§5.4)
[ "$(names "$R/root")" = ".bashrc .profile " ] || bad "/root holds: $(names "$R/root")"
for f in root/.bashrc root/.profile home/ubuntu/.bashrc home/ubuntu/.profile home/ubuntu/.bash_logout; do
    cmp -s "$R/$f" "$R/etc/skel/${f##*/}" || bad "/$f is not /etc/skel/${f##*/}"
done

# --- home: what sanitize keeps at the top, exactly the allowlist below (§5.4)
for f in "$H"/* "$H"/.[!.]* "$H"/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in
            .bashrc|.profile|.bash_logout|.config|.local|.ssh|xiaozhi-hub-server|xiaozhi-workspace) ;;
            Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos) ;;
            *) bad "/home/ubuntu holds ${f##*/}" ;;
        esac
    fi
done
for f in "$H"/.config/* "$H"/.config/.[!.]* "$H"/.config/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in
            pipewire|wireplumber|systemd|user-dirs.dirs|user-dirs.locale) ;;
            *) bad "/home/ubuntu/.config holds ${f##*/}" ;;
        esac
    fi
done
for d in .config/systemd .config/pipewire .config/wireplumber .local; do
    if [ -d "$H/$d" ]; then (cd "$H" && find "$d" -mindepth 1 \( -type f -o -type l \)); fi
done | sort > "$T/home"
while IFS= read -r p; do home_allowed "$p" || bad "not on home-allowlist.txt: /home/ubuntu/$p"; done < "$T/home"
grep -v -e '^#' -e '^$' "$HOME_ALLOW" | while IFS= read -r e; do
    case $e in
        */) [ -d "$H/$e" ] || echo "missing from the image: /home/ubuntu/$e" ;;
        */*.wants/*)
            # an enable link: to the unit of the same name, a regular file inside the image
            if [ -L "$H/$e" ]; then
                t=$(readlink "$H/$e")
                case $t in /*) u=$R$t ;; *) u=$(dirname "$H/$e")/$t ;; esac
                { [ "${t##*/}" = "${e##*/}" ] && [ -f "$u" ] && [ ! -L "$u" ]; } \
                    || echo "link /home/ubuntu/$e points at $t, not at its unit"
            else
                echo "not a link: /home/ubuntu/$e"
            fi ;;
        *) { [ -f "$H/$e" ] && [ ! -L "$H/$e" ]; } || echo "missing or not a regular file: /home/ubuntu/$e" ;;
    esac
done > "$T/x"
[ ! -s "$T/x" ] || bad "$(cat "$T/x")"
[ ! -e "$H/.config/thinksmart-kiosk/lang" ] || bad "the kiosk language choice is still there"

# --- host name, time zone, NTP (§5.4, §5.5)
[ "$(cat "$R/etc/hostname")" = thinksmart ] || bad "hostname is '$(cat "$R/etc/hostname")'"
if [ "$(grep -c '^127\.0\.1\.1[[:space:]]' "$R/etc/hosts")" != 1 ] || ! grep -qx '127\.0\.1\.1[[:space:]]*thinksmart' "$R/etc/hosts"; then
    bad "/etc/hosts has no single 127.0.1.1 thinksmart line"
fi
[ "$(cat "$R/etc/timezone")" = Etc/UTC ] || bad "timezone is '$(cat "$R/etc/timezone")'"
[ "$(readlink "$R/etc/localtime")" = /usr/share/zoneinfo/Etc/UTC ] || bad "/etc/localtime is not Etc/UTC"
grep -qxF 'NTP=ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org pool.ntp.org ntp.ubuntu.com' \
    "$R/etc/systemd/timesyncd.conf.d/thinksmart.conf" || bad "timesyncd: not the NTP= line of kiosk/timesyncd.conf"

# --- updater: nothing half done, no backup, no previous client (§5.3 point 4a)
for f in pending.json system-pending.json; do
    [ ! -e "$R/var/lib/thinksmart-update/$f" ] || bad "an update is half done ($f): let the device finish it, then capture again"
done
[ ! -e "$R/opt/thinksmart/system/backup" ] || bad "/opt/thinksmart/system/backup is still there"
cur=$(readlink "$R/opt/thinksmart/client/current" || true)
[ -n "$cur" ] || bad "no current client"
[ "$(names "$R/opt/thinksmart/client")" = "$(printf '%s\n' "$cur" current | sort | tr '\n' ' ')" ] \
    || bad "/opt/thinksmart/client holds more than $cur: $(names "$R/opt/thinksmart/client")"
env=$(readlink "$R/opt/thinksmart/client/$cur/.venv" || true)
case $env in
    ../../envs/?*) [ "$(names "$R/opt/thinksmart/envs")" = "${env##*/} " ] \
        || bad "/opt/thinksmart/envs is not exactly ${env##*/}: $(names "$R/opt/thinksmart/envs")" ;;
    *) bad "client $cur has no .venv link into envs/ ('$env')" ;;
esac

[ "$fail" = 0 ] && echo "check-rootfs: ok"
exit "$fail"
```

- [x] **檢查**

Run: `shellcheck -x -s sh image/check-rootfs.sh`
Expected: 沒有輸出。

- [x] **Commit**

```bash
git add image/check-rootfs.sh
git commit -m "check-rootfs.sh: sources, system layer, upstream URLs, accounts, home, host name, NTP before mke2fs"
```

---

### Task 5: sanitize-rootfs.sh 的新增清理和測試

> **已完成（`8849833`、`e110fc1`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Modify: `image/sanitize-rootfs.sh`
- Create: `image/clean-hub-git.sh`、`image/tests/test-sanitize.sh`

**Interfaces:**
- Consumes: `make-fake-root.sh DIR`、`check-rootfs.sh ROOT IDS REPO`、`allowlist.sh`、`image/xiaozhi-hub.service`、`image/hub-git-config`、`image/ubuntu-password.hash`。
- Produces: `sanitize-rootfs.sh ROOT HUB_TEMPLATE REPO`。第三個參數是本 repo，用來取得 `update/thinksmart-update.conf` 和 `kiosk/thinksmart-kiosk.conf`。
- Produces: `clean-hub-git.sh HUB_DIR COMMIT`。以 checkout 的擁有者身分執行（build-image.sh 用 uid 1000），失敗時結束碼非 0。最後把被忽略的路徑逐行印成 `clean-hub-git: ignored: …`，讓 Task 8 在紀錄裏看得見。

新增的行為：

| 範圍 | 做法 |
|---|---|
| 兩個 keep 檔 | 用 repo 版本覆寫 |
| 其他帳號 | 移除 UID 1000–59999 之間的其他帳號，以及 GID 1000–59999 之間的其他群組。帳號只從 `passwd`、`shadow`、`subuid`、`subgid` 移除，群組只從 `group`、`gshadow` 移除，因為系統帳號可以跟被移除的群組同名 |
| 帳號的家目錄 | 只接受 `/home` 下一層的單一名字（不是 `ubuntu`）。其他寫法（`/home//ubuntu`、`/home/bob/x`、`/home` 以外）都停止打包，要求先在裝置上處理；`/nonexistent` 例外 |
| 帳號的其他痕跡 | crontab、mail、`sudoers.d`、AccountsService 記錄（`users/`、`icons/`）、`/var/lib/sudo/lectured/` |
| `/home` 裏沒有帳號擁有的目錄 | 刪除，每刪一個印一行 `removed /home/…` |
| locate 資料庫 | 刪除（`plocate.db`、`mlocate.db`，裏面列着母機每一個檔名；它的 timer 會重建） |
| 連結 | 刪除動作會經過的目錄（`/home`、家目錄和其中的 `.config`、`.local` 等、網關目錄、`/root`、`/tmp`、`/var` 底下幾個、`/opt/thinksmart` 底下幾個）只要有一個是連結就停止打包。容器裏的絕對連結指向的是容器自己的路徑，其中 `/out` 和 `/w` 是這次打包的輸出和工作區 |
| `ubuntu`、`root` | `ubuntu` 用公開的固定雜湊，`root` 鎖定 |
| `-` 備份檔 | 刪除 |
| 主機名稱、時區 | `thinksmart`、`Etc/UTC` |
| 家目錄裏四個目錄（`~/.config/systemd` 整個，不只 `user/`） | 不在允許清單上的檔案全部刪除，**每刪一個印一行** `removed /home/ubuntu/…`，讓需要的檔案在第一次真正擷取時就看得見（Task 8） |
| 網關服務檔 | 用 `image/xiaozhi-hub.service` 覆寫 |
| kiosk 語言狀態檔 | 刪除 |
| `/root` 和 shell 啟動檔 | 從 skel 重建 |
| `/etc/gitconfig` | 刪除：系統層級的 `insteadOf` 或代理會把網關的 fetch 導到別處 |
| 更新器的殘留 | 刪除系統層備份、上一版客戶端和它的 Python 環境。現行版本沒有指向 `../../envs/` 的 `.venv` 時停止，否則每個環境都會被當成沒有用到而刪掉 |

另外把原有第 12 行的 `[ -d ] && [ -d ] || …` 改為 `if`，讓檔案通過 shellcheck。

- [x] **套用 diff**

```diff
--- a/image/sanitize-rootfs.sh
+++ b/image/sanitize-rootfs.sh
@@ -2,14 +2,30 @@
 # Strip everything personal or machine-specific from an extracted root filesystem before it goes
 # into a release image (checklist: 开源发布规划与版权审查 3.1). Run as root in the image-tools
 # container, on a copy, never on a running device:
-#   sanitize-rootfs.sh ROOT HUB_TEMPLATE
+#   sanitize-rootfs.sh ROOT HUB_TEMPLATE REPO
 # HUB_TEMPLATE is xiaozhi-hub-server's scripts/config.template.yaml of the shipped commit; the hub's
 # data/ starts over from it, the way its install script does it.
-# What stays on purpose (same as upstream): user ubuntu with password thinksmart, passwordless sudo,
-# SSH with password login. The README tells people to change the password.
+# REPO is this repository: update/thinksmart-update.conf and kiosk/thinksmart-kiosk.conf are keep
+# files on the device, so only this puts our copies (our update source) into the image.
+# What stays on purpose: user ubuntu with password thinksmart (ubuntu-password.hash), passwordless
+# sudo, SSH with password login; root is locked. The README tells people to change the password.
 set -eu
-R=${1:?root}; TEMPLATE=${2:?hub config template}
-[ -d "$R/etc" ] && [ -d "$R/home/ubuntu" ] || { echo "$R does not look like the root filesystem"; exit 1; }
+R=${1:?root}; TEMPLATE=${2:?hub config template}; REPO=${3:?repository}
+if [ ! -d "$R/etc" ] || [ ! -d "$R/home/ubuntu" ]; then echo "$R does not look like the root filesystem"; exit 1; fi
+# The deletions below go through these directories: a link among them (an absolute one resolves in
+# the container, where /out and /w are the build's own) would take them outside the copy.
+for p in home home/ubuntu home/ubuntu/.config home/ubuntu/.config/systemd home/ubuntu/.config/systemd/user \
+         home/ubuntu/.config/pipewire home/ubuntu/.config/wireplumber home/ubuntu/.local \
+         home/ubuntu/xiaozhi-hub-server home/ubuntu/xiaozhi-hub-server/main \
+         home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server home/ubuntu/xiaozhi-workspace \
+         root tmp var var/tmp var/log var/lib var/lib/thinksmart-update var/cache usr usr/local etc \
+         opt opt/thinksmart opt/thinksmart/client opt/thinksmart/envs opt/thinksmart/system; do
+    if [ -L "$R/$p" ]; then echo "sanitize: /$p is a link: the deletions would follow it out of the copy"; exit 1; fi
+done
+S=$(cd "$(dirname "$0")" && pwd)
+HOME_ALLOW=$S/home-allowlist.txt
+# shellcheck source=image/allowlist.sh
+. "$S/allowlist.sh"
 H=$R/home/ubuntu
 HUB=$H/xiaozhi-hub-server
 SRV=$HUB/main/xiaozhi-server
@@ -33,6 +49,71 @@
     [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 00051607 ] && rm -f "$f"
 done || true
 
+say "update source and kiosk settings: this repository's copies"
+install -m 644 -o 0 -g 0 "$REPO/update/thinksmart-update.conf" "$R/etc/thinksmart-update.conf"
+install -m 644 -o 0 -g 0 "$REPO/kiosk/thinksmart-kiosk.conf" "$R/etc/thinksmart-kiosk.conf"
+
+say "accounts: ubuntu with the published password, root locked, nobody else"
+people=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/passwd")
+groups=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/group")
+for u in $people; do
+    home=$(awk -F: -v u="$u" '$1 == u {print $6}' "$R/etc/passwd")
+    case $home in
+        /nonexistent) ;;
+        # one name right under /home, nothing else: /home//ubuntu or /home/bob/x would hit the wrong tree
+        /home/ubuntu|/home/.|/home/..|/home/*/*) echo "sanitize: $u's home is $home: sort it out on the device"; exit 1 ;;
+        /home/?*) rm -rf "$R$home" ;;
+        *) echo "sanitize: $u's home $home is outside /home: remove it on the device first"; exit 1 ;;
+    esac
+    rm -f "$R/var/spool/cron/crontabs/$u" "$R/var/mail/$u" "$R/var/lib/AccountsService/users/$u" \
+        "$R/var/lib/AccountsService/icons/$u" "$R/var/lib/sudo/lectured/$u"
+    if [ -d "$R/etc/sudoers.d" ]; then
+        grep -rlwF -e "$u" "$R/etc/sudoers.d" | while IFS= read -r f; do rm -f "$f"; done
+    fi
+    say "  removed account $u"
+done
+# edit FILE KIND: drop the removed accounts (passwd, shadow, subuid, subgid) or groups (group,
+# gshadow), and removed accounts from member lists; keeps owner and mode (the new text is written
+# into the same file). Users and groups stay apart: a system user can share a removed group's name.
+edit() {
+    f=$R/etc/$1
+    [ -e "$f" ] || return 0
+    case $2 in group|gshadow) rows=$groups ;; *) rows=$people ;; esac
+    ROWS=$rows PEOPLE=$people HASH=$(cat "$S/ubuntu-password.hash") awk -F: -v OFS=: -v kind="$2" '
+        BEGIN {
+            n = split(ENVIRON["ROWS"], d, "\n"); for (i = 1; i <= n; i++) if (d[i] != "") gone[d[i]] = 1
+            n = split(ENVIRON["PEOPLE"], d, "\n"); for (i = 1; i <= n; i++) if (d[i] != "") person[d[i]] = 1
+        }
+        function strip(list,   n, a, i, out) {
+            n = split(list, a, ","); out = ""
+            for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in person)) out = out (out == "" ? "" : ",") a[i]
+            return out
+        }
+        $1 in gone { next }
+        kind == "shadow" && $1 == "ubuntu" { $2 = ENVIRON["HASH"] }
+        kind == "shadow" && $1 == "root" { $2 = "!" }
+        kind == "group" { $4 = strip($4) }
+        kind == "gshadow" { $3 = strip($3); $4 = strip($4) }
+        { print }' "$f" > "$f.sanitize"
+    cat "$f.sanitize" > "$f"
+    rm -f "$f.sanitize"
+}
+edit passwd plain; edit shadow shadow; edit group group; edit gshadow gshadow; edit subuid plain; edit subgid plain
+rm -f "$R"/etc/shadow- "$R"/etc/passwd- "$R"/etc/group- "$R"/etc/gshadow- "$R"/etc/subuid- "$R"/etc/subgid-
+# what no account owns any more: a home left by userdel without -r, or by an account removed earlier
+for d in "$R"/home/* "$R"/home/.[!.]* "$R"/home/..?*; do
+    if { [ -e "$d" ] || [ -L "$d" ]; } && [ "${d##*/}" != ubuntu ]; then rm -rf "$d"; say "  removed /home/${d##*/}"; fi
+done
+# the locate database lists every file name the mother device had (its timer rebuilds it)
+rm -f "$R/var/lib/plocate/plocate.db" "$R/var/lib/mlocate/mlocate.db"
+
+say "host name and time zone: the public defaults"
+printf 'thinksmart\n' > "$R/etc/hostname"
+sed -i '/^127\.0\.1\.1[[:space:]]/d' "$R/etc/hosts"
+printf '127.0.1.1\tthinksmart\n' >> "$R/etc/hosts"
+printf 'Etc/UTC\n' > "$R/etc/timezone"
+ln -sfn /usr/share/zoneinfo/Etc/UTC "$R/etc/localtime"
+
 say "networks: Wi-Fi profiles, leases, Bluetooth pairings"
 rm -f "$R"/etc/netplan/90-NM-*.yaml
 rm -rf "$R"/etc/NetworkManager/system-connections/*
@@ -58,34 +139,46 @@
 rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/debconf/*-old "$R"/var/backups/*
 
 say "home: only what the voice terminal uses"
-for f in "$H"/* "$H"/.[!.]*; do
+for f in "$H"/* "$H"/.[!.]* "$H"/..?*; do
     case "${f##*/}" in
         .bashrc|.profile|.bash_logout|.config|.local|.ssh|xiaozhi-hub-server|xiaozhi-workspace) ;;
         Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos) ;;
         *) rm -rf "$f" ;;
     esac
 done
-for f in "$H"/.config/* "$H"/.config/.[!.]*; do
+for f in "$H"/.config/* "$H"/.config/.[!.]* "$H"/.config/..?*; do
     case "${f##*/}" in
         pipewire|wireplumber|systemd|user-dirs.dirs|user-dirs.locale) ;;
         *) rm -rf "$f" ;;
     esac
 done
-for f in "$H"/.local/share/* "$H"/.local/state/*; do
-    case "${f##*/}" in
-        uv) ;;          # the Python the hub's .venv runs on
-        *) rm -rf "$f" ;;
-    esac
+# where setup writes, only home-allowlist.txt stays: anything else may hold a token. Each removal
+# is printed: a file the device needs shows up here first (then it belongs on the list).
+for d in .config/systemd .config/pipewire .config/wireplumber .local; do
+    [ -d "$H/$d" ] || continue
+    (cd "$H" && find "$d" -mindepth 1 \( -type f -o -type l -o -type p -o -type s \)) | while IFS= read -r p; do
+        home_allowed "$p" || { rm -f "$H/$p"; say "  removed /home/ubuntu/$p"; }
+    done
+    find "$H/$d" -mindepth 1 -depth -type d -empty -delete
 done
+rm -rf "$H/.config/thinksmart-kiosk"   # the kiosk's language choice: a new device asks again
+# the gateway's unit as scripts/autostart.sh writes it, with the image's paths: whatever the mother
+# device had in it (an Environment= with a key) does not ship
+if [ -e "$H/.config/systemd/user/xiaozhi-hub.service" ]; then
+    install -m 644 -o 1000 -g 1000 "$S/xiaozhi-hub.service" "$H/.config/systemd/user/xiaozhi-hub.service"
+fi
 for d in Desktop Documents Downloads Music Pictures Public Templates Videos; do
     [ -d "$H/$d" ] && find "$H/$d" -mindepth 1 -delete
 done
 find "$H/xiaozhi-workspace" -mindepth 1 -delete
-# restore.*: what restore-userdata.sh unpacks the owner's data into, left if it was interrupted
-rm -rf "$R"/root/restore.* "$R"/root/.bash_history "$R"/root/.cache "$R"/root/.lesshst "$R"/root/.wget-hsts \
-    "$R"/root/.python_history "$R"/root/.viminfo "$R"/root/.local "$R"/root/.gitconfig
-
-say "hub: fresh data/ from the template, no logs, git on main"
+say "shell startup files and /root from /etc/skel (startup files are where tokens get exported)"
+find "$R/root" -mindepth 1 -maxdepth 1 ! -name .bashrc ! -name .profile -exec rm -rf {} +
+for f in .bashrc .profile; do install -m 644 -o 0 -g 0 "$R/etc/skel/$f" "$R/root/$f"; done
+for f in .bashrc .profile .bash_logout; do install -m 644 -o 1000 -g 1000 "$R/etc/skel/$f" "$H/$f"; done
+
+say "hub: fresh data/ from the template, no logs (its git: clean-hub-git.sh)"
+# a system-wide insteadOf or proxy would redirect the gateway's fetches; the image needs none
+rm -f "$R/etc/gitconfig"
 rm -rf "$SRV/data" "$SRV/tmp"
 install -d -o 1000 -g 1000 "$SRV/data" "$SRV/tmp"
 # Same as the hub's install script on a machine without Claude Code: Claude API, key set in the admin page
@@ -104,9 +197,26 @@
        -o -name '*.dpkg-old' -o -name '*.dpkg-dist' -o -name '*.ucf-old' \) \
     -not -path '*/site-packages/*' -not -path '*/.venv/*' -exec rm -rf {} + 2>/dev/null || true
 
-say "updater: no download leftovers or past check results"
+say "updater: no download leftovers, past checks, system backup or previous client"
 rm -rf "$R"/var/lib/thinksmart-update/download/* "$R"/var/lib/thinksmart-update/requests/*
-cur=$(readlink "$R/opt/thinksmart/client/current" 2>/dev/null || true)
-[ -n "$cur" ] && printf '{"current": "%s"}\n' "$cur" > "$R/var/lib/thinksmart-update/status.json"
+# a new device has nothing to roll back to, and both still point at upstream (pending.json and
+# system-pending.json are left alone: check-rootfs.sh refuses a capture with an update half done)
+rm -rf "$R/opt/thinksmart/system/backup"
+CL=$R/opt/thinksmart/client
+cur=$(readlink "$CL/current" 2>/dev/null || true)
+if [ -n "$cur" ]; then
+    for d in "$CL"/* "$CL"/.[!.]* "$CL"/..?*; do
+        if [ -e "$d" ] || [ -L "$d" ]; then
+            case ${d##*/} in current|"$cur") ;; *) rm -rf "$d" ;; esac
+        fi
+    done
+    env=$(readlink "$CL/$cur/.venv" 2>/dev/null || true)
+    # without it every env below would count as unused and go
+    case $env in ../../envs/?*) ;; *) echo "sanitize: client $cur has no .venv link into envs/ ('$env')"; exit 1 ;; esac
+    for e in "$R"/opt/thinksmart/envs/*; do
+        if [ -e "$e" ] && [ "../../envs/${e##*/}" != "$env" ]; then rm -rf "$e"; fi
+    done
+    printf '{"current": "%s"}\n' "$cur" > "$R/var/lib/thinksmart-update/status.json"
+fi
 
 say "done"
```

- [x] **image/clean-hub-git.sh**

取代 build-image.sh 原本那段只刪除分支、遠端 ref 和 stash 的整理。tag、notes 等其他 ref 也會保留未發佈的 commit，而 git 物件是壓縮過的，兩個文字掃描都看不見裏面的內容，所以除了 `main` 和 `origin/main` 以外的 ref 全部刪除，再 `gc --prune=now`。

順序有講究：`checkout` 會觸發 `post-checkout`，`checkout` 和 `update-ref` 會觸發 `reference-transaction`。母機的 hook 如果在容器裏執行，就能讀到秘密檔，也能寫進已經檢查過的 `data/`。所以第一個 git 指令之前就刪掉 hook；舊設定只當純文字檔讀（`git config -f` 不跟進 `include`），讀完立即換掉；之後每個 git 指令都帶 `core.hooksPath=/dev/null` 和 `core.fsmonitor=false`。最後 `.git` 第一層只留 git 需要的檔案，`COMMIT_EDITMSG`、`MERGE_MSG`、rebase 狀態、`logs/`、`info/exclude` 都刪掉。

```sh
#!/bin/sh
# The captured gateway checkout as a new device gets it (spec §5.3 point 3): COMMIT checked out as
# main, tracking origin/main; .git/config is image/hub-git-config (no insteadOf, proxy, extraHeader
# or include from the mother device); no other refs (tags, notes, stash, branches, other remotes)
# and no objects only they kept alive; .git holds only what git needs (no commit or merge messages,
# rebase state, logs, info/exclude) and no hooks besides git's samples.
#   clean-hub-git.sh HUB_DIR COMMIT
# Run as the checkout's owner (build-image.sh: uid 1000), so .git stays ubuntu's.
set -eu
D=${1:?hub dir}; C=${2:?commit}
S=$(cd "$(dirname "$0")" && pwd)
# The mother device's hooks and config must never run: hooks go before the first git command, the
# config is read as a plain file and replaced, and every git call runs without hooks or fsmonitor.
if [ -d "$D/.git/hooks" ]; then find "$D/.git/hooks" ! -type d ! -name '*.sample' -exec rm -f {} +; fi
# the config is replaced, so it must not need a setting it would lose (sha256 objects, worktree config)
[ -z "$(git config -f "$D/.git/config" --get-regexp '^extensions\.' || true)" ] \
    || { echo "clean-hub-git: the repository uses git extensions"; exit 1; }
cp "$S/hub-git-config" "$D/.git/config"
G() { git -c safe.directory='*' -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$D" "$@"; }
[ "$(G rev-parse HEAD)" = "$C" ] || { echo "clean-hub-git: HEAD is not $C"; exit 1; }
# a power cut right after the admin page's update check leaves these zero-filled; both are rewritten
rm -f "$D/.git/FETCH_HEAD" "$D/.git/refs/remotes/origin/main"
G checkout -q -B main "$C"
G for-each-ref --format='%(refname)' | while read -r ref; do
    case $ref in refs/heads/main) ;; *) G update-ref --no-deref -d "$ref" ;; esac
done
# The commit is on the published main (build-image.sh checks it), so origin/main may point at it
G update-ref refs/remotes/origin/main "$C"
G reflog expire --expire=now --all
G gc -q --prune=now
# what is left in .git: only what git needs to work
for f in "$D"/.git/* "$D"/.git/.[!.]* "$D"/.git/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in HEAD|config|index|objects|refs|packed-refs|shallow|hooks) ;; *) rm -rf "$f" ;; esac
    fi
done
[ -z "$(G status --porcelain)" ] || { echo "clean-hub-git: working tree is not clean:"; G status --short | head; exit 1; }
# ignored files are not in status: list them, check-rootfs.sh holds them to image/hub-ignored.txt
G ls-files --others --ignored --exclude-standard --directory | sed 's|^|clean-hub-git: ignored: |'
```

- [x] **image/tests/test-sanitize.sh**

```sh
#!/bin/sh
# sanitize-rootfs.sh and check-rootfs.sh on a synthetic capture:
#   fakeroot sh image/tests/test-sanitize.sh
set -eu
IMG=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$IMG/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
R=$T/root
n=0; failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; failed=1; }
t() { label=$1; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
nt() { label=$1; shift; if "$@" >/dev/null 2>&1; then no "$label"; else ok "$label"; fi; }
check() { sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$REPO"; }
# the tree belongs to uid 1000 and fakeroot runs as 0: git would refuse it as dubious
# shellcheck disable=SC2317 # called through eval in broken()
G() { git -c safe.directory='*' -c tag.gpgsign=false -c core.hooksPath=/dev/null -C "$R/home/ubuntu/xiaozhi-hub-server" "$@"; }

sh "$IMG/tests/make-fake-root.sh" "$R"
{ cat "$IMG/owner-identifiers.txt"; echo mother-host; } > "$T/ids"
C=$(G rev-parse HEAD); B=$(G rev-parse private-work)

nt "check-rootfs fails before sanitize" check
t "sanitize runs" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "clean-hub-git runs" sh "$IMG/clean-hub-git.sh" "$R/home/ubuntu/xiaozhi-hub-server" "$C"
if check; then ok "check-rootfs passes after sanitize"; else no "check-rootfs passes after sanitize"; fi

# the gateway checkout
HUB=$R/home/ubuntu/xiaozhi-hub-server
t "gateway on the published commit" test "$(G rev-parse main)" = "$C"
t "gateway .git/config is image/hub-git-config" cmp -s "$HUB/.git/config" "$IMG/hub-git-config"
nt "gateway tag gone" G rev-parse -q --verify refs/tags/private-work
nt "unpublished commit gone" G cat-file -e "$B"
nt "gateway hook gone" test -e "$HUB/.git/hooks/post-merge"
nt "/etc/gitconfig gone" test -e "$R/etc/gitconfig"
nt "no gateway hook ran during the cleanup" sh -c "ls '$HUB/main/xiaozhi-server/data' | grep -q -- -ran"
nt "commit message of the private commit gone" test -e "$HUB/.git/COMMIT_EDITMSG"
nt "merge message gone" test -e "$HUB/.git/MERGE_MSG"
nt "git logs gone" test -e "$HUB/.git/logs"
t "the gateway checkout still works" G status --porcelain

# accounts
for f in passwd shadow group gshadow subuid subgid; do
    nt "alice gone from $f" grep -qw alice "$R/etc/$f"
done
nt "private group carol gone from group" grep -q '^carol:' "$R/etc/group"
nt "private group carol gone from gshadow" grep -q '^carol:' "$R/etc/gshadow"
t "sudo keeps ubuntu" grep -qx 'sudo:x:27:ubuntu' "$R/etc/group"
t "gshadow sudo keeps ubuntu" grep -qx 'sudo:\*::ubuntu' "$R/etc/gshadow"
t "system user www-data kept in passwd" grep -q '^www-data:' "$R/etc/passwd"
t "system user www-data kept in shadow" grep -q '^www-data:' "$R/etc/shadow"
nt "private group www-data gone" grep -q '^www-data:' "$R/etc/group"
nt "alice's home gone" test -e "$R/home/alice"
nt "a home no account owns gone" test -e "$R/home/retired"
nt "alice's AccountsService entry gone" test -e "$R/var/lib/AccountsService/users/alice"
nt "locate database gone" test -e "$R/var/lib/plocate/plocate.db"
nt "alice's crontab gone" test -e "$R/var/spool/cron/crontabs/alice"
nt "alice's mail gone" test -e "$R/var/mail/alice"
nt "alice's sudoers file gone" test -e "$R/etc/sudoers.d/alice"
t "ubuntu's sudoers file kept" test -e "$R/etc/sudoers.d/90-ubuntu"
t "ubuntu hash is the published one" grep -qF "ubuntu:$(cat "$IMG/ubuntu-password.hash"):" "$R/etc/shadow"
t "published hash is thinksmart" test "$(openssl passwd -6 -salt "$(cut -d'$' -f3 "$IMG/ubuntu-password.hash")" thinksmart)" = "$(cat "$IMG/ubuntu-password.hash")"
t "root locked" grep -q '^root:!:' "$R/etc/shadow"
nt "shadow- gone" test -e "$R/etc/shadow-"
t "shadow keeps mode 640" test "$(stat -c %a "$R/etc/shadow")" = 640

# home and /root
U=$R/home/ubuntu/.config/systemd/user
nt "leak.service gone" test -e "$U/leak.service"
nt "systemd user.conf gone" test -e "$R/home/ubuntu/.config/systemd/user.conf"
nt "leak.service link gone" test -L "$U/default.target.wants/leak.service"
t "gateway unit is image/xiaozhi-hub.service" cmp -s "$U/xiaozhi-hub.service" "$IMG/xiaozhi-hub.service"
t "gateway unit link kept" test -L "$U/default.target.wants/xiaozhi-hub.service"
t "proximity unit kept" test -f "$U/vcnl4200-proximity-daemon.service"
t "uv kept" test -f "$R/home/ubuntu/.local/bin/uv"
t "uv's Python kept" test -f "$R/home/ubuntu/.local/share/uv/python/bin/python3"
nt "other .local/bin file gone" test -e "$R/home/ubuntu/.local/bin/my-script"
nt ".local/state gone" test -e "$R/home/ubuntu/.local/state"
nt "unlisted PipeWire file gone" test -e "$R/home/ubuntu/.config/pipewire/pipewire.conf.d/20-experiment.conf"
nt "kiosk language gone" test -e "$R/home/ubuntu/.config/thinksmart-kiosk/lang"
t "ubuntu .bashrc from skel" cmp -s "$R/home/ubuntu/.bashrc" "$R/etc/skel/.bashrc"
t "ubuntu .bashrc owned by 1000" test "$(stat -c %u "$R/home/ubuntu/.bashrc")" = 1000
t "root .profile from skel" cmp -s "$R/root/.profile" "$R/etc/skel/.profile"
nt "/root/.aws gone" test -e "$R/root/.aws"

# host, time, updater, settings
t "hostname" test "$(cat "$R/etc/hostname")" = thinksmart
nt "old hostname gone from hosts" grep -q mother-host "$R/etc/hosts"
t "timezone" test "$(cat "$R/etc/timezone")" = Etc/UTC
t "update conf is the repository's" cmp -s "$R/etc/thinksmart-update.conf" "$REPO/update/thinksmart-update.conf"
t "kiosk conf is the repository's" cmp -s "$R/etc/thinksmart-kiosk.conf" "$REPO/kiosk/thinksmart-kiosk.conf"
nt "system backup gone" test -e "$R/opt/thinksmart/system/backup"
nt "previous client gone" test -e "$R/opt/thinksmart/client/0.1.6"
nt "previous link gone" test -L "$R/opt/thinksmart/client/previous"
nt "previous env gone" test -e "$R/opt/thinksmart/envs/old"
t "current env kept" test -d "$R/opt/thinksmart/envs/new"

# every check must also fail: break one thing, expect a failure, put it back. A break or restore
# command that fails is reported, not fatal.
broken() {  # label, command that breaks the sanitized root, command that restores it
    if ! (eval "$2") >/dev/null 2>&1; then no "break: $1"; return; fi
    if check >/dev/null 2>&1; then no "check-rootfs catches: $1"; else ok "check-rootfs catches: $1"; fi
    (eval "$3") >/dev/null 2>&1 || no "restore: $1"
}
broken "upstream URL in a script" \
    "echo 'curl https://raw.githubusercontent.com/justhalfbit/xiaozhi-hub-server/main/x | bash' > '$HUB/scripts/bootstrap.sh'" \
    "echo 'echo install' > '$HUB/scripts/bootstrap.sh'"
broken "upstream URL in a LICENSES/ directory" "mkdir '$HUB/LICENSES'; echo 'curl https://github.com/justhalfbit/x | sh' > '$HUB/LICENSES/install.sh'" \
    "rm -r '$HUB/LICENSES'"
broken "upstream URL as git@" "echo 'git@github.com:justhalfbit/x.git' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "owner identifier" "echo 'by chris-yyau' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "mother hostname" "echo 'host mother-host' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "upstream SOURCES" "cp '$R/etc/thinksmart-update.conf' '$T/u'; echo 'SOURCES=\"x\"' > '$R/etc/thinksmart-update.conf'" \
    "cp '$T/u' '$R/etc/thinksmart-update.conf'"
broken "upstream gateway origin" "G remote set-url origin https://example.com/x.git" \
    "G remote set-url origin https://github.com/ohimsmart/oh-im-smart-gateway.git"
broken "insteadOf in the gateway's config" "G config url.https://mirror.example/.insteadOf https://github.com/" \
    "cp '$IMG/hub-git-config' '$HUB/.git/config'"
broken "a tag in the gateway" "G tag t" "G tag -d t"
broken "an unreachable object in the gateway" "echo x | G hash-object -w --stdin" "G prune --expire=now"
broken "a gateway hook" "printf '#!/bin/sh\n' > '$HUB/.git/hooks/post-merge'" "rm '$HUB/.git/hooks/post-merge'"
broken "/etc/gitconfig" "echo '[http]' > '$R/etc/gitconfig'" "rm '$R/etc/gitconfig'"
broken "a commit message in the gateway's .git" "echo private > '$HUB/.git/COMMIT_EDITMSG'" "rm '$HUB/.git/COMMIT_EDITMSG'"
broken "an ignored file in the gateway" "echo KEY=1 > '$HUB/.env'" "rm '$HUB/.env'"
broken "an extra file in the gateway's data/" "echo x > '$HUB/main/xiaozhi-server/data/x'" "rm '$HUB/main/xiaozhi-server/data/x'"
broken "a home no account owns" "mkdir '$R/home/retired'" "rmdir '$R/home/retired'"
broken "ubuntu out of the sudo group" "cp '$R/etc/group' '$T/g'; sed -i 's/^sudo:x:27:ubuntu\$/sudo:x:27:/' '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "a hidden ..name in home" "echo x > '$R/home/ubuntu/..notes'" "rm '$R/home/ubuntu/..notes'"
broken "an old system layer file" "cp '$R/usr/local/share/thinksmart-kiosk/welcome.html' '$T/w'; echo old > '$R/usr/local/share/thinksmart-kiosk/welcome.html'" \
    "cp '$T/w' '$R/usr/local/share/thinksmart-kiosk/welcome.html'"
broken "a key in the gateway unit" "echo 'Environment=K=1' >> '$U/xiaozhi-hub.service'" "cp '$IMG/xiaozhi-hub.service' '$U/xiaozhi-hub.service'"
broken "extra user unit" "echo x > '$U/x.service'" "rm '$U/x.service'"
broken "systemd user.conf" "echo 'DefaultEnvironment=K=1' > '$R/home/ubuntu/.config/systemd/user.conf'" \
    "rm '$R/home/ubuntu/.config/systemd/user.conf'"
broken "a file at the top of home" "echo x > '$R/home/ubuntu/.netrc'" "rm '$R/home/ubuntu/.netrc'"
broken "a directory in ~/.config" "mkdir '$R/home/ubuntu/.config/git'" "rmdir '$R/home/ubuntu/.config/git'"
broken "missing gateway unit" "mv '$U/xiaozhi-hub.service' '$T/hub.service'" "mv '$T/hub.service' '$U/xiaozhi-hub.service'"
broken "dangling gateway link" "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s /nonexistent/xiaozhi-hub.service '$U/default.target.wants/xiaozhi-hub.service'" \
    "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s /home/ubuntu/.config/systemd/user/xiaozhi-hub.service '$U/default.target.wants/xiaozhi-hub.service'"
broken "unit as a link" "mv '$U/vcnl4200-proximity-daemon.service' '$T/v'; ln -s /nonexistent '$U/vcnl4200-proximity-daemon.service'" \
    "rm '$U/vcnl4200-proximity-daemon.service'; mv '$T/v' '$U/vcnl4200-proximity-daemon.service'"
broken "another account" "cp '$R/etc/passwd' '$T/p'; echo 'bob:x:1002:1002::/home/bob:/bin/sh' >> '$R/etc/passwd'" "cp '$T/p' '$R/etc/passwd'"
broken "a private group" "cp '$R/etc/group' '$T/g'; echo 'carol:x:1003:' >> '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "gshadow group without group" "cp '$R/etc/gshadow' '$T/gs'; echo 'dave:!::' >> '$R/etc/gshadow'" "cp '$T/gs' '$R/etc/gshadow'"
broken "group member without account" "cp '$R/etc/group' '$T/g'; sed -i 's/^audio:x:29:.*/audio:x:29:ubuntu,ghost/' '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "hostname" "echo other > '$R/etc/hostname'" "echo thinksmart > '$R/etc/hostname'"
broken "NTP line" "cp '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf' '$T/n'; echo '[Time]' > '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf'" \
    "cp '$T/n' '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf'"
broken "token in .bashrc" "echo 'export T=1' >> '$R/home/ubuntu/.bashrc'" "cp '$R/etc/skel/.bashrc' '$R/home/ubuntu/.bashrc'"
broken "file in /root" "echo x > '$R/root/.netrc'" "rm '$R/root/.netrc'"
broken "kiosk language" "mkdir -p '$R/home/ubuntu/.config/thinksmart-kiosk'; echo en > '$R/home/ubuntu/.config/thinksmart-kiosk/lang'" \
    "rm -r '$R/home/ubuntu/.config/thinksmart-kiosk'"
broken "update half done" "echo '{}' > '$R/var/lib/thinksmart-update/pending.json'" "rm '$R/var/lib/thinksmart-update/pending.json'"
broken "previous client" "mkdir '$R/opt/thinksmart/client/0.9.0'" "rmdir '$R/opt/thinksmart/client/0.9.0'"
broken "the client's env missing" "mv '$R/opt/thinksmart/envs/new' '$T/env'" "mv '$T/env' '$R/opt/thinksmart/envs/new'"
broken "a second env" "mkdir '$R/opt/thinksmart/envs/extra'" "rmdir '$R/opt/thinksmart/envs/extra'"
if check >/dev/null 2>&1; then ok "every break was put back"; else no "every break was put back"; fi

# an account whose home is outside /home: sanitize stops instead of leaving it behind
R=$T/root2
sh "$IMG/tests/make-fake-root.sh" "$R"
echo 'bob:x:1002:1002:Bob:/srv/bob:/bin/sh' >> "$R/etc/passwd"
nt "sanitize refuses a home outside /home" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"

# a home that names ubuntu's another way: sanitize stops and ubuntu's home stays
R=$T/root3
sh "$IMG/tests/make-fake-root.sh" "$R"
echo 'bob:x:1002:1002:Bob:/home//ubuntu:/bin/sh' >> "$R/etc/passwd"
nt "sanitize refuses /home//ubuntu" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "ubuntu's home survives /home//ubuntu" test -d "$R/home/ubuntu/xiaozhi-hub-server"

# /home as a link: rm -rf through it would leave the copy
R=$T/root4
sh "$IMG/tests/make-fake-root.sh" "$R"
mv "$R/home" "$R/home.real"; ln -s home.real "$R/home"
nt "sanitize refuses /home as a link" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"

# a link deeper down (the envs directory): sanitize stops before deleting through it
R=$T/root6
sh "$IMG/tests/make-fake-root.sh" "$R"
mv "$R/opt/thinksmart/envs" "$R/opt/thinksmart/envs.real"; ln -s envs.real "$R/opt/thinksmart/envs"
nt "sanitize refuses a link among the directories it deletes in" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing deleted through the link" test -d "$R/opt/thinksmart/envs.real/old"

# the current client without its .venv link: sanitize stops instead of deleting every env
R=$T/root5
sh "$IMG/tests/make-fake-root.sh" "$R"
rm "$R/opt/thinksmart/client/1.0.0/.venv"
nt "sanitize refuses a client without .venv" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "the client's env survives" test -d "$R/opt/thinksmart/envs/new"

echo "1..$n"
exit "$failed"
```

- [x] **跑測試**

```bash
dash -n image/sanitize-rootfs.sh && dash -n image/clean-hub-git.sh
shellcheck -x -s sh image/sanitize-rootfs.sh image/clean-hub-git.sh image/tests/test-sanitize.sh
fakeroot sh image/tests/test-sanitize.sh > /tmp/test-sanitize.out; echo "exit $?"
grep -c '^not ok' /tmp/test-sanitize.out; tail -1 /tmp/test-sanitize.out
```

Expected:
- 兩個 `dash -n` 和 shellcheck 都沒有輸出；
- `exit 0`；
- `not ok` 的計數是 `0`；
- 最後一行是 `1..116`（第一版；現在 `1..200`）。

- [x] **Commit**

```bash
git add image/sanitize-rootfs.sh image/clean-hub-git.sh image/tests/test-sanitize.sh
git commit -m "sanitize: accounts, /root, home allowlist, gateway unit and git, host name, time zone, repo settings, no rollback leftovers"
```

---

### Task 6: check-image-privacy.sh 和測試

> **已完成（`d489db0`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Create: `image/check-image-privacy.sh`、`image/tests/test-image-privacy.sh`

**Interfaces:**
- Produces: `check-image-privacy.sh IMAGE|DIR SECRETS_FILE`，或 `check-image-privacy.sh IMAGE|DIR --test-image`。第一個參數是目錄時遞迴掃描檔案樹（計數是檔案數），是檔案時掃描原始位元組（計數是行數）。掃描檔案樹時，key 規則命中會再印出最多 20 個檔案路徑，讓失敗查得出來；秘密檔的命中不印路徑，因為 Wi-Fi 名稱可能就是檔名的一部分。結束碼：0 乾淨；1 找到東西；2 秘密檔缺少或是空的，或 grep 出錯。只印計數，不印比對到的內容。
- 秘密檔每行結尾的 CR 會被去掉（Windows 換行存檔時，否則每個秘密都比對不到而通過）；只有空白的行跳過。

**跟 spec 字面規則的差異：** spec §5.3 第 5 點寫的是 `sk-[A-Za-z0-9_-]{32,}`。這個字元集合也涵蓋 urlsafe base64，在本機實測中比對到一個 wheel `RECORD` 裏的 sha256（`grpcio-1.84.0.dist-info/RECORD`，約 26,000 行雜湊中 1 行），乾淨的映像也可能因此失敗，而且只印計數，查不出是哪一行。所以本計劃在前面加上左邊界 `(?<![A-Za-z0-9_-])`：`sk-` 前面是 key 字元時不算。這只排除雜湊中間的 `sk-`；真正的 key 前面是 `=`、引號、空白或行首，照樣會被找到，含 `-` 和 `_` 的 key 也照樣找得到（測試第 7 項和第 13 項）。spec 的文字在下一次修改 spec 時跟着更新。

- [x] **image/check-image-privacy.sh**

```sh
#!/bin/sh
# Privacy scan (spec §5.3 point 5) of the root file tree before mke2fs, and again of the raw bytes
# of the finished disk.img (every byte that ships, metadata included). The tree pass also catches a
# string mke2fs would split across non-adjacent blocks.
#   check-image-privacy.sh IMAGE|DIR SECRETS_FILE   one literal per line: Wi-Fi names, API keys,
#                                                   e-mail... (a trailing CR is dropped; blank lines skipped)
#   check-image-privacy.sh IMAGE|DIR --test-image   no owner secrets checked; such an image is never published
# Exit 0 clean, 1 something found, 2 a missing/empty secrets file or a grep error. Prints counts
# (lines in an image, files in a tree), never what matched. In a tree, a key pattern's hit also
# prints the file paths (up to 20) so it can be found; an owner secret's never does, since a Wi-Fi
# name can be part of a file name.
set -eu
export LC_ALL=C
IMG=${1:?image}; SECRETS=${2:?SECRETS_FILE or --test-image}
fail=0
check() {  # label, then grep arguments
    label=$1; shift
    rc=0
    if [ -d "$IMG" ]; then
        files=$(grep -r -D skip -a -l "$@" "$IMG") || rc=$?
        c=$(printf '%s' "$files" | grep -c '' || true)
    else
        c=$(grep -a -c "$@" "$IMG") || rc=$?
    fi
    [ "$rc" -le 1 ] || { echo "check-image-privacy: grep failed for $label"; exit 2; }
    printf '%-28s %s\n' "$label" "$c"
    [ "$c" = 0 ] || fail=1
    case $label in
        "owner secret"*) ;;
        *) if [ -d "$IMG" ] && [ "$c" != 0 ]; then printf '%s\n' "$files" | head -20 | sed "s|^$IMG|    |"; fi ;;
    esac
}
check "ssh-ed25519 public keys" -F -e "ssh-ed25519 AAAA"
check "ssh-rsa public keys"     -F -e "ssh-rsa AAAA"
# a real PEM block: the header, optional encryption headers (Proc-Type, DEK-Info) and a blank line,
# then base64. No start-of-line anchor (in a raw image a key can follow zero bytes); -z splits on
# NUL so the pattern can span lines. The header alone in quotes (cryptography's ssh.py) is no key.
check "private keys (PEM)"      -Pz -e '-----BEGIN [A-Z ]*PRIVATE KEY-----\r?\n(?:[A-Za-z-]+:[^\n]*\r?\n)*(?:\r?\n)?[A-Za-z0-9+/=]{40,}'
# Real keys are long runs; "sk-"/"xai-" alone match ordinary words (disk-, ssh-sk-helper). A key
# starts after a non-key character: "sk-" inside a base64url hash (a wheel's RECORD) is no key.
check "sk- API keys"            -P -e '(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{32,}'
check "xai- API keys"           -E -e "xai-[A-Za-z0-9]{32,}"
if [ "$SECRETS" = --test-image ]; then
    echo "TEST IMAGE: owner secrets not checked; never publish this image"
else
    [ -f "$SECRETS" ] || { echo "check-image-privacy: no secrets file $SECRETS"; exit 2; }
    k=0
    cr=$(printf '\r')
    while IFS= read -r s || [ -n "$s" ]; do
        s=${s%"$cr"}
        case $s in *[![:space:]]*) ;; *) continue ;; esac
        k=$((k + 1))
        check "owner secret #$k" -F -e "$s"
    done < "$SECRETS"
    [ "$k" -gt 0 ] || { echo "check-image-privacy: $SECRETS lists nothing"; exit 2; }
fi
[ "$fail" = 0 ] || { echo "privacy check FAILED"; exit 1; }
echo "privacy check ok"
```

- [x] **image/tests/test-image-privacy.sh**

```sh
#!/bin/sh
# check-image-privacy.sh on small synthetic images:  sh image/tests/test-image-privacy.sh
set -eu
IMG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; failed=0
expect() {  # label, wanted exit code, image file, secrets argument
    n=$((n + 1)); rc=0
    sh "$IMG/check-image-privacy.sh" "$3" "$4" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "$2" ]; then echo "ok $n - $1"; else echo "not ok $n - $1 (exit $rc, wanted $2)"; failed=1; fi
}
printf 'nothing here\0\0more data\n' > "$T/clean.img"
echo 'my-wifi-name' > "$T/secrets"
printf 'not-in-image-1\nnot-in-image-2\n' > "$T/two"
printf 'my-wifi-name\nnot-in-image\n' > "$T/first"
: > "$T/empty"
ssh-keygen -q -t ed25519 -N '' -C '' -f "$T/k" >/dev/null
openssl genrsa -aes128 -traditional -passout pass:x 2048 > "$T/enc.pem" 2>/dev/null
{ cat "$T/clean.img"; cat "$T/k"; } > "$T/key.img"
{ printf 'x\0\0\0\0\0\0\0\0'; cat "$T/k"; } > "$T/zeros.img"
{ cat "$T/clean.img"; cat "$T/enc.pem"; } > "$T/enc.img"
{ cat "$T/clean.img"; echo '_SK_START = b"-----BEGIN OPENSSH PRIVATE KEY-----"'; } > "$T/const.img"
{ cat "$T/clean.img"; echo 'key=sk-ant-api03-abcdefghijklmnopqrstuvwxyz_0123456789-AB'; } > "$T/sk.img"
{ cat "$T/clean.img"; echo 'ssid=my-wifi-name'; } > "$T/secret.img"
# a wheel's RECORD line: urlsafe-base64 sha256 with "sk-" inside
{ cat "$T/clean.img"; echo 'grpc/_cython/x.so,sha256=AbCdsk-SOPLHaey6-7ekD23Qhu3k4QUNmYI1ScVU,1234'; } > "$T/record.img"
printf 'my-wifi-name\r\n' > "$T/crlf"
printf ' \nnot-in-image\n' > "$T/blank"
mkdir "$T/tree" "$T/tree-secret" "$T/tree-key"
cp "$T/clean.img" "$T/tree/a"
cp "$T/secret.img" "$T/tree-secret/a"
cp "$T/k" "$T/tree-key/id_ed25519"

expect "clean image passes" 0 "$T/clean.img" "$T/secrets"
expect "two absent secrets pass" 0 "$T/clean.img" "$T/two"
expect "private key fails" 1 "$T/key.img" "$T/secrets"
expect "private key after zero bytes fails" 1 "$T/zeros.img" "$T/secrets"
expect "encrypted RSA PEM fails" 1 "$T/enc.img" "$T/secrets"
expect "PEM header as a constant passes" 0 "$T/const.img" "$T/secrets"
expect "sk-ant key with - and _ fails" 1 "$T/sk.img" "$T/secrets"
expect "owner secret fails" 1 "$T/secret.img" "$T/secrets"
expect "first secret found, second not: fails" 1 "$T/secret.img" "$T/first"
expect "empty secrets file refused" 2 "$T/clean.img" "$T/empty"
expect "missing secrets file refused" 2 "$T/clean.img" "$T/none"
expect "--test-image skips secrets" 0 "$T/secret.img" --test-image
expect "sk- inside a base64url hash passes" 0 "$T/record.img" "$T/secrets"
expect "secrets file with CRLF still finds the secret" 1 "$T/secret.img" "$T/crlf"
expect "whitespace-only secrets line skipped" 0 "$T/clean.img" "$T/blank"
expect "clean file tree passes" 0 "$T/tree" "$T/secrets"
expect "secret in a file tree fails" 1 "$T/tree-secret" "$T/secrets"
expect "private key in a file tree fails" 1 "$T/tree-key" "$T/secrets"
n=$((n + 1))
if sh "$IMG/check-image-privacy.sh" "$T/tree-key" "$T/secrets" 2>&1 | grep -q 'id_ed25519'; then
    echo "ok $n - a key hit in a tree names the file"
else echo "not ok $n - a key hit in a tree names the file"; failed=1; fi
n=$((n + 1))
if sh "$IMG/check-image-privacy.sh" "$T/tree-secret" "$T/secrets" 2>&1 | grep -q "$T"; then
    echo "not ok $n - an owner secret hit names no file"; failed=1
else echo "ok $n - an owner secret hit names no file"; fi
n=$((n + 1))
if sh "$IMG/check-image-privacy.sh" "$T/secret.img" "$T/secrets" 2>&1 | grep -q my-wifi-name; then
    echo "not ok $n - output names the secret"; failed=1
else echo "ok $n - output never names the secret"; fi
echo "1..$n"
exit "$failed"
```

- [x] **跑測試**

```bash
shellcheck -x -s sh image/check-image-privacy.sh image/tests/test-image-privacy.sh
sh image/tests/test-image-privacy.sh > /tmp/test-privacy.out; echo "exit $?"
grep -c '^not ok' /tmp/test-privacy.out; tail -1 /tmp/test-privacy.out
```

Expected: shellcheck 沒有輸出；`exit 0`；`not ok` 的計數是 `0`；最後一行是 `1..21`（第一版；現在 `1..38`）。

- [x] **Commit**

```bash
git add image/check-image-privacy.sh image/tests/test-image-privacy.sh
git commit -m "check-image-privacy.sh: file tree and raw image, real PEM blocks, sk- keys with - and _, required secrets file"
```

---

### Task 7: build-image.sh 接上新流程

> **已完成（`8849833`、`e110fc1`）。** 下面的程式碼和預期輸出是第一版的紀錄，以 commit 為準。

**Files:**
- Modify: `image/build-image.sh`

**Interfaces:**
- Consumes: `sanitize-rootfs.sh ROOT TEMPLATE REPO`、`clean-hub-git.sh HUB_DIR COMMIT`、`check-rootfs.sh ROOT IDS REPO`、`check-image-privacy.sh IMAGE|DIR SECRETS|--test-image`。
- Produces: `build-image.sh WORK_DIR OUT_DIR HUB_REPO SECRETS_FILE|--test-image`。第 4 個參數改為必填。

改動：

| 項目 | 做法 |
|---|---|
| 秘密檔 | 必填，沒有非空白內容就停止；`--test-image` 時映像名稱加上 `-TEST-DO-NOT-PUBLISH` |
| 網關 | `HUB_REPO` 的 origin 必須是 ohimsmart 網關（`HUB_MAIN` 因此對照我們的 `main`）。映像裏的網關 git 整段改為以 uid 1000 呼叫 `clean-hub-git.sh`，remote 由 `image/hub-git-config` 決定 |
| repo 掛載 | 整個 repo 以唯讀方式掛載到容器的 `/repo`，sanitize 和 check-rootfs 從那裏讀取（spec §5.3 第 7 點） |
| 母機主機名稱 | 加入識別字串清單，`ubuntu`、`localhost`、`thinksmart` 這類通用名稱除外 |
| `check-rootfs.sh` | 網關 repo 整理之後、`mke2fs` 之前執行 |
| 私人資料掃描 | 整段換成 `check-image-privacy.sh`：check-rootfs 之後先掃檔案樹，`mke2fs` 之後再掃 `disk.img` |
| NTP | 原有只檢查檔案存在的 `need`，由 check-rootfs 的完整一行比對取代 |

**刻意刪除**原有的三項上游作者檢查：電郵 `qiuhe.zhang`、區網 `192.168.100.x` 和代理 `127.0.0.1:7897`。spec §5.3 第 5 點明定移除，因為它們屬於上游作者，對我們沒有作用。我們自己的電郵、Wi-Fi 名稱等放在 `SECRETS_FILE`；維護者帳號名稱放在 `owner-identifiers.txt`。

- [x] **套用 diff**

```diff
--- a/image/build-image.sh
+++ b/image/build-image.sh
@@ -1,17 +1,19 @@
 #!/bin/bash
 # Build the release image from a capture made by pull-from-device.sh:
-#   image/build-image.sh WORK_DIR OUT_DIR HUB_REPO [SECRETS_FILE]
+#   image/build-image.sh WORK_DIR OUT_DIR HUB_REPO SECRETS_FILE|--test-image
 # WORK_DIR   has root.tar.zst, boot.tar.zst, versions.txt (hub commit, client version, system layer
 #            version and file-set id)
 # OUT_DIR    gets <name>.img.xz, SHA256SUMS (.img.xz and .img), packages.txt
-# HUB_REPO   a checkout of xiaozhi-hub-server holding the captured commit (for the config template)
-# SECRETS_FILE (optional, keep it outside any repository) one literal string per line that must not
+# HUB_REPO   a checkout of ohimsmart/oh-im-smart-gateway (its origin must be that repository) holding
+#            the captured commit (for the config template)
+# SECRETS_FILE (required; keep it outside any repository) one literal string per line that must not
 #            appear anywhere in the image: Wi-Fi names, API keys, device ids, the owner's e-mail...
+#            --test-image instead skips that check and names the image ...-TEST-DO-NOT-PUBLISH.
 # HUB_MAIN   (environment, default origin/main, fetched first) the hub's published main: the shipped
 #            commit must be on it, or every device's scripts/update.sh (git merge --ff-only) fails.
 #            HUB_MAIN=main checks against the local main before it is pushed (push before releasing).
 # RELEASE_MANIFEST (environment) the latest.json of the newest online update (a file, or the URL
-#            https://github.com/justhalfbit/xiaozhi-thinksmart-client/releases/latest/download/latest.json).
+#            https://github.com/ohimsmart/oh-im-smart-client/releases/latest/download/latest.json).
 #            The image must carry exactly that client and system layer version, so a freshly flashed
 #            device reports "up to date" instead of holding something no release has (publish the
 #            update first, then build the image). ALLOW_UNRELEASED=1 skips this, for test images.
@@ -22,7 +24,11 @@
 # Runs everything that needs root inside a container (image/Dockerfile); the work tree lives in a
 # Docker volume so ownership, devices and capabilities survive.
 set -euo pipefail
-WORK=$(cd "${1:?work dir}" && pwd); OUT=${2:?out dir}; HUB=$(cd "${3:?hub repo}" && pwd); SECRETS=${4:-}
+WORK=$(cd "${1:?work dir}" && pwd); OUT=${2:?out dir}; HUB=$(cd "${3:?hub repo}" && pwd)
+SECRETS=${4:?SECRETS_FILE (one secret per line, outside any repository) or --test-image}
+if [ "$SECRETS" != --test-image ]; then
+    grep -q '[^[:space:]]' "$SECRETS" || { echo "$SECRETS lists no secrets"; exit 1; }
+fi
 HERE=$(cd "$(dirname "$0")" && pwd)
 mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
 read -r HUB_COMMIT CLIENT_VERSION SYSTEM_VERSION SYSTEM_TREE < <(paste -sd' ' "$WORK/versions.txt")
@@ -46,20 +52,29 @@
 PY
 fi
 NAME=${IMAGE_NAME:-thinksmart-ubuntu-$(date +%Y%m%d)}
+GATEWAY_URL=https://github.com/ohimsmart/oh-im-smart-gateway.git
+[ "$(git -C "$HUB" remote get-url origin)" = "$GATEWAY_URL" ] || {
+    echo "$HUB: origin is not $GATEWAY_URL (the shipped commit must be on our gateway's main)"; exit 1; }
 HUB_MAIN=${HUB_MAIN:-origin/main}
 [ "$HUB_MAIN" = origin/main ] && git -C "$HUB" fetch -q origin main
 git -C "$HUB" merge-base --is-ancestor "$HUB_COMMIT" "$HUB_MAIN" || {
     echo "hub commit $HUB_COMMIT is not on $HUB_MAIN: merge it into main (fast-forward) first"; exit 1; }
 git -C "$HUB" show "$HUB_COMMIT:scripts/config.template.yaml" > "$WORK/hub-config.template.yaml"
-[ -n "$SECRETS" ] && cp "$SECRETS" "$WORK/secrets.txt" || : > "$WORK/secrets.txt"
+if [ "$SECRETS" = --test-image ]; then
+    TEST_IMAGE=1; NAME=$NAME-TEST-DO-NOT-PUBLISH; : > "$WORK/secrets.txt"
+else
+    TEST_IMAGE=0; cp "$SECRETS" "$WORK/secrets.txt"
+fi
 
 # the DMIC fix must be the codec-dmic build (it only exists on the device and in codec-dmic/out)
 KO_MD5=$(awk '/snd-soc-msm8916-digital.ko/{print $1}' "$HERE/../codec-dmic/expected.md5")
 DTB_MD5=$(awk '/apq8053-lenovo-cd-18781y.dtb/{print $1}' "$HERE/../codec-dmic/expected.md5")
 docker build -q -t thinksmart-image "$HERE" >/dev/null 2>&1
 docker volume create tsimg-work >/dev/null
-docker run --rm -i -v tsimg-work:/w -v "$WORK:/in:ro" -v "$OUT:/out" -v "$HERE:/s:ro" \
+# /repo: this repository, for the keep files sanitize puts in and the system layer check-rootfs compares
+docker run --rm -i -v tsimg-work:/w -v "$WORK:/in:ro" -v "$OUT:/out" -v "$HERE:/s:ro" -v "$HERE/..:/repo:ro" \
     -e NAME="$NAME" -e HUB_COMMIT="$HUB_COMMIT" -e CLIENT_VERSION="$CLIENT_VERSION" -e KO_MD5="$KO_MD5" -e DTB_MD5="$DTB_MD5" \
+    -e TEST_IMAGE="$TEST_IMAGE" \
     thinksmart-image bash -s <<'EOF'
 set -euo pipefail
 BOOT_UUID=35bca636-764e-4f53-b5e5-96eb774eb19e
@@ -79,7 +94,14 @@
 sh /s/initramfs-usb-ncm.sh /w/boot/initramfs
 
 log "sanitize"
-sh /s/sanitize-rootfs.sh $R /in/hub-config.template.yaml
+# the mother device's name is an owner identifier: it must not survive anywhere (hosts, prompts, logs)
+orig_host=$(cat $R/etc/hostname)
+cp /s/owner-identifiers.txt /w/owner-identifiers.txt
+case $orig_host in
+    thinksmart|ubuntu|localhost|"") echo "mother hostname '$orig_host' is generic: not searched for" ;;
+    *) echo "$orig_host" >> /w/owner-identifiers.txt ;;
+esac
+sh /s/sanitize-rootfs.sh $R /in/hub-config.template.yaml /repo
 
 log "files the image must carry: DMIC fix, audio rules, ALSA plugin, user unit links"
 # codec-dmic/build.sh output (codec-dmic/expected.md5): the DTB with qcom,dmic-sample-rate and the module
@@ -112,8 +134,7 @@
     n=$((n + 1))
 done
 echo "held packages: $n"
-# Chinese time servers, rsyslog off (device-setup.sh files / tidy)
-need $R/etc/systemd/timesyncd.conf.d/thinksmart.conf
+# rsyslog off (device-setup.sh tidy); the NTP= line is checked by check-rootfs.sh
 [ ! -e $R/etc/systemd/system/multi-user.target.wants/rsyslog.service ] || { echo "rsyslog still enabled (device-setup.sh tidy)"; exit 1; }
 # Wi-Fi power save off (device-setup.sh files)
 need $R/etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf
@@ -137,22 +158,15 @@
 
 log "hub repository: $HUB_COMMIT as main, tracking origin/main"
 # as the owner (uid 1000), so .git stays ubuntu's
-G() { setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/tmp git -c 'safe.directory=*' -C $R/home/ubuntu/xiaozhi-hub-server "$@"; }
-[ "$(G rev-parse HEAD)" = "$HUB_COMMIT" ] || { echo "hub HEAD is not $HUB_COMMIT"; exit 1; }
-# rewritten below; a power cut right after the admin page's update check leaves them zero-filled
-rm -f $R/home/ubuntu/xiaozhi-hub-server/.git/FETCH_HEAD $R/home/ubuntu/xiaozhi-hub-server/.git/refs/remotes/origin/main
-G checkout -q -B main "$HUB_COMMIT"
-G for-each-ref --format='%(refname)' refs/heads refs/remotes refs/stash | { grep -v -x -e refs/heads/main -e refs/remotes/origin/main -e refs/remotes/origin/HEAD || true; } \
-    | while read -r ref; do G update-ref -d "$ref"; done || true
-G remote | { grep -v -x origin || true; } | while read -r r; do G remote remove "$r"; done
-G remote set-url origin https://github.com/justhalfbit/xiaozhi-hub-server.git
-# The commit is on the published main (checked on the host), so origin/main may point at it
-G update-ref refs/remotes/origin/main "$HUB_COMMIT"
-G branch -q -u origin/main main
-G config --unset-all http.proxy 2>/dev/null || true
-G reflog expire --expire=now --all
-G gc -q --prune=now
-[ -z "$(G status --porcelain)" ] || { echo "hub working tree is not clean:"; G status --short | head; exit 1; }
+setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/tmp \
+    sh /s/clean-hub-git.sh $R/home/ubuntu/xiaozhi-hub-server "$HUB_COMMIT"
+
+log "file tree: sources, system layer, upstream URLs, owner identifiers, accounts, home"
+sh /s/check-rootfs.sh $R /w/owner-identifiers.txt /repo
+
+log "privacy check over the file tree"
+if [ "$TEST_IMAGE" = 1 ]; then sh /s/check-image-privacy.sh $R --test-image
+else sh /s/check-image-privacy.sh $R /in/secrets.txt; fi
 
 log "capabilities to check after mke2fs"
 getcap -r $R/usr 2>/dev/null | sed "s|^$R||" > /w/caps.txt || true
@@ -199,30 +213,10 @@
 [ "$(stat -c %s /w/disk.img)" = $(( (ROOT_START + root_sectors) * 512 )) ] || { echo "mke2fs changed the image size"; exit 1; }
 
 log "privacy check over the whole image"
-fail=0
-check() {  # label, then grep arguments
-    local label=$1; shift
-    n=$(grep -a -c "$@" /w/disk.img || true)
-    printf '%-28s %s\n' "$label" "$n"; [ "$n" = 0 ] || fail=1
-}
-check "ssh-ed25519 public keys" -F -e "ssh-ed25519 AAAA"
-check "ssh-rsa public keys"     -F -e "ssh-rsa AAAA"
-# Real keys are long runs of letters and digits; "sk-"/"xai-" alone match ordinary words (disk-, ssh-sk-helper)
-check "sk- API keys"            -E -e "sk-[A-Za-z0-9]{32,}"
-check "xai- API keys"           -E -e "xai-[A-Za-z0-9]{32,}"
-check "owner e-mail"            -F -e "qiuhe.zhang"
-# a host on the owner's LAN (requests' docstring has the network 192.168.100.0/24, which is fine)
-check "LAN host 192.168.100.x"  -E -e "192\.168\.100\.[1-9][0-9]{0,2}([^0-9/]|$)"
-check "Mac proxy 127.0.0.1:7897" -F -e "127.0.0.1:7897"
-n=0
-while IFS= read -r s; do
-    [ -n "$s" ] || continue
-    c=$(grep -a -c -F -e "$s" /w/disk.img || true)
-    [ "$c" = 0 ] || { echo "secret #$((n+1)) found $c times"; fail=1; }
-    n=$((n+1))
-done < /in/secrets.txt
-echo "owner secrets checked: $n"
-[ $fail = 0 ] || { echo "privacy check FAILED"; exit 1; }
+# the upstream author's e-mail, LAN and proxy checks are gone (spec §5.3 point 5): ours are listed
+# in SECRETS_FILE, and the maintainer's handle in owner-identifiers.txt
+if [ "$TEST_IMAGE" = 1 ]; then sh /s/check-image-privacy.sh /w/disk.img --test-image
+else sh /s/check-image-privacy.sh /w/disk.img /in/secrets.txt; fi
 
 log "package list"
 awk '/^Package:/{p=$2} /^Version:/{v=$2} /^Status:/{s=$0} /^$/{if (s ~ / installed$/) print p, v; s=""}' \
```

- [x] **檢查**

```bash
bash -n image/build-image.sh
git show HEAD:image/build-image.sh > /tmp/bi-before.sh; shellcheck /tmp/bi-before.sh | grep -c '^In ' ; shellcheck image/build-image.sh | grep -c '^In '
git grep -n justhalfbit -- image update kiosk ':!kiosk/qrcode.js' ':!image/check-rootfs.sh' ':!image/tests'
```

Expected：
- `bash -n` 沒有輸出；
- 第一個計數是 `1`，第二個是 `0`（原有第 54 行的 SC2015 消失了）；
- `git grep` 沒有輸出。`check-rootfs.sh` 和 `image/tests/` 是刻意含有上游名稱的：前者是掃描用的正規表示式，後者是測試資料。

- [x] **Commit**

```bash
git add image/build-image.sh
git commit -m "build-image: required secrets file, gateway origin ohimsmart, repo mounted for sanitize, both checks"
```

---

### Task 7b: 網關 main 的對照、ubuntu 帳號的個人資料、/etc/hosts

設計審查第 2 到 6 輪找到的缺口，都要在 Task 8 之前修好：

- `HUB_MAIN=main` 只對照本機的 `main`，沒有 fetch。映像裏的 `clean-hub-git.sh` 把 `origin/main` 設成出貨的 commit，所以 check-rootfs 的「main = origin/main」永遠成立；如果那個 commit 從來沒有 push，每台裝置的 `scripts/update.sh` 都會失敗。改為：`HUB_MAIN` 不是 `origin/main` 時，只有 `--test-image` 或 `ALLOW_UNRELEASED=1` 的打包可以繼續，否則一開始就停下（所以命名的條件不需要另外處理）。預設的 fetch 寫明目標 ref（`+refs/heads/main:refs/remotes/origin/main`），不靠 clone 的 fetch 設定去更新 `origin/main`。
- ubuntu 帳號的 passwd 名稱欄（GECOS）和 AccountsService 的 `users/ubuntu`（`Icon=`、`Email=`）、`icons/ubuntu`（頭像）是母機主人的，sanitize 和 check-rootfs 都沒有處理。改為：GECOS 固定為 `Ubuntu`；頭像刪除；`users/ubuntu` 是連結時 sanitize 停下（見下面連結那一點），是一般檔案時只留下 `[User]` 這一行和 `Session=`、`XSession=`、`SystemAccount=`、`Language=` 開頭的行。check-rootfs 用同一個完整比對的樣式檢查，連結、目錄和讀不到的檔案都算失敗（fail closed）。每一行都要完整符合：`Session=`、`XSession=` 後面只能是 session 名稱的字元，`SystemAccount=` 只能是 `true` 或 `false`，`Language=` 只能是 locale 的字元，所以 `Session=plasma RealName=…` 這種接在後面的內容也會被刪掉、被檢查擋下。
- `/etc/hosts` 只換掉 `127.0.1.1` 那一行，母機主人加上的區網名稱會留下；`/etc/machine-info`（`PRETTY_HOSTNAME=` 等）沒有處理。改為：sanitize 把 `/etc/hosts` 整個換成 Ubuntu 原本的內容（`stock_hosts`，放在 sanitize 和 check-rootfs 共用的 `allowlist.sh`），刪除 `/etc/machine-info`；check-rootfs 逐位元組比對 `/etc/hosts`，並要求 `/etc/machine-info` 不存在。
- 只檢查了 `timesyncd.conf.d/thinksmart.conf`。`NTP=` 是累加的（`timesyncd.conf(5)`：每次指定都加到清單裏，只有空的 `NTP=` 才清空），所以主設定檔 `/etc/systemd/timesyncd.conf` 裏母機留下的 `NTP=`、或其他 drop-in 的 `NTP=`，都會跟我們的伺服器一起用。改為：`kiosk/timesyncd.conf` 在 `NTP=` 那一行之前加一行空的 `NTP=`，清掉主設定檔設的伺服器（系統層逐位元組比對，所以 check-rootfs 已經會要求這一行）；check-rootfs 另外要求 systemd 讀 timesyncd drop-in 的四個目錄（`/etc`、`/run`、`/usr/local/lib`、`/usr/lib` 下的 `systemd/timesyncd.conf.d`）裏只有 `/etc/systemd/timesyncd.conf.d/thinksmart.conf`（排在它之後的 drop-in 可以再加伺服器，或再清空），而且這四個目錄都不是連結（`find` 不會走進當作起點的連結，裏面的 drop-in 會被漏掉），列不出內容也算失敗。
- sanitize 和 check-rootfs 在容器裏跑，絕對連結（或往上爬出根目錄的相對連結）在容器裏指向容器本身，不是映像；sanitize 的連結防護只擋指向 `/w`、`/out` 的。所以：`var/lib/AccountsService/icons`、`var/log`、`etc/NetworkManager/system-connections`、`var/lib/bluetooth` 等任何一個目錄（或它上面的目錄）是這種連結時，sanitize 的刪除落空，check-rootfs 也讀不到映像裏的檔案，開機後連結在映像裏指回母機的資料；sanitize 用 `>`、`cat >` 寫的檔案（帳號檔、`hostname`、`hosts`、`timezone`、`machine-id`、`users/ubuntu`）和用 `install` 寫的 shell 啟動檔是連結時，寫入穿過連結。逐一列出 sanitize 碰的目錄永遠列不完，改為兩條通用的規則，放在 `allowlist.sh`，sanitize 和 check-rootfs 共用：（一）`out_dir_links` 列出所有指向根目錄以外的目錄連結，只允許 Ubuntu 原有、sanitize 不在底下做事的 `/var/run`、`/var/lock`（`OUT_DIR_LINKS_OK`；Task 8 第一次真正擷取時看見別的，查清是 Ubuntu 原有的才加入，每一條都要說得出是甚麼）；（二）`WRITTEN_FILES` 裏的路徑不能是連結：sanitize 寫的檔案，加上 sanitize 和 `build-image.sh` 開始 `find` 的目錄（`find` 不走進當作起點的連結，即使是根目錄裏的相對連結，後面的檔案也會留下）。有任何一項，sanitize 一開始就停下、甚麼都不改，check-rootfs 也失敗。根目錄裏的相對連結在容器和映像裏指向同一處，不受影響（例如 Ubuntu 的 `/lib -> usr/lib`）。`machine-id` 原本 check-rootfs 沒有檢查，改為要求它是空的一般檔案。
- 新的 fetch 寫法沒有測試能證明它真的更新了 `origin/main`。改為：fetch 之後再用 `git ls-remote` 向 GitHub 取 `main` 的 commit，跟本機的 `origin/main` 不同就停下。這一步每次打包都會實際執行；`test-build-image.sh` 用一個代替 `git` 的小腳本（只攔下 `fetch` 和 `ls-remote`）測它的兩個結果。

**Files:**
- Modify: `kiosk/timesyncd.conf`
- Modify: `image/allowlist.sh`、`image/build-image.sh`、`image/sanitize-rootfs.sh`、`image/check-rootfs.sh`
- Modify: `image/tests/make-fake-root.sh`、`image/tests/test-sanitize.sh`
- Create: `image/tests/test-build-image.sh`

- [ ] **`kiosk/timesyncd.conf`**

`NTP=ntp.aliyun.com ...` 那一行之前加上：

```ini
# NTP= adds to the list: this empty one first drops what timesyncd.conf itself may set
NTP=
```

- [ ] **`allowlist.sh`**

檔尾加上：

```sh
# /etc/hosts as Ubuntu writes it, with the image's host name: sanitize writes it, check-rootfs compares
stock_hosts() {
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tthinksmart\n\n'
    printf '# The following lines are desirable for IPv6 capable hosts\n'
    printf '::1     ip6-localhost ip6-loopback\nfe00::0 ip6-localnet\nff00::0 ip6-mcastprefix\n'
    printf 'ff02::1 ip6-allnodes\nff02::2 ip6-allrouters\n'
}
# the lines of ubuntu's AccountsService entry the image keeps (an awk pattern, whole lines only):
# sanitize keeps them, check-rootfs fails on any other
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
ACCOUNTS_KEEP='/^\[User\]$|^(Session|XSession)=[A-Za-z0-9._-]*$|^SystemAccount=(true|false)$|^Language=[A-Za-z0-9_.@:-]*$/'
# no link at all: the files sanitize writes into (>, cat >, install; a write would go through it) and
# the directories where sanitize or build-image.sh start a find (find does not enter a starting point
# that is a link, so what is behind it would stay)
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
WRITTEN_FILES='etc/passwd etc/shadow etc/group etc/gshadow etc/subuid etc/subgid etc/hostname etc/hosts etc/timezone etc/machine-id root/.bashrc root/.profile home/ubuntu/.bashrc home/ubuntu/.profile home/ubuntu/.bash_logout var/lib/AccountsService/users/ubuntu var/lib/thinksmart-update/status.json
etc home opt root usr/local var/log lib/modules home/ubuntu/xiaozhi-workspace home/ubuntu/xiaozhi-hub-server home/ubuntu/.config/systemd home/ubuntu/.config/pipewire home/ubuntu/.config/wireplumber home/ubuntu/.local
home/ubuntu/Desktop home/ubuntu/Documents home/ubuntu/Downloads home/ubuntu/Music home/ubuntu/Pictures home/ubuntu/Public home/ubuntu/Templates home/ubuntu/Videos'
# links that lead out of the root: an absolute one to a directory, or a relative one climbing past /.
# In the build container they lead into the container, not the image, so sanitize's deletions and
# check-rootfs's checks would miss the image's files there. Allowed (shell patterns), where nothing
# deletes or checks through them: Ubuntu's own, and uv's links from a Python minor version to the
# installed release (the gateway's .venv Python, kept whole by home-allowlist.txt)
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
OUT_DIR_LINKS_OK='/var/run /var/lock /home/ubuntu/.local/share/uv/python/*'
# inroot ROOT PATH: PATH inside the image with every link on it followed there (an absolute target is
# the image's /); past 40 links, or ., an empty name or .. after something that is not a directory
# (the kernel refuses those), it gives up: an empty line, which no check accepts
inroot() {
    _r=$1; _rest=${2#"$1"}; _q=$1; _i=0
    while [ -n "$_rest" ]; do
        _rest=${_rest#/}; _c=${_rest%%/*}; _rest=${_rest#"$_c"}
        case $_c in
            '' | .) [ -d "$_q" ] || { echo; return 0; }; continue ;;
            ..) [ -d "$_q" ] || { echo; return 0; }; _q=${_q%/*}; [ "${#_q}" -ge "${#_r}" ] || _q=$_r; continue ;;
        esac
        if [ -L "$_q/$_c" ]; then
            [ "$_i" -lt 40 ] || { echo; return 0; }
            _k=$(readlink "$_q/$_c"); _i=$((_i + 1))
            case $_k in /*) _q=$_r ;; esac
            _rest=$_k$_rest
        else
            _q=$_q/$_c
        fi
    done
    printf '%s\n' "$_q"
}
# out_dir_links ROOT SCRATCH: each such link but those, as "/path -> target", one per line; returns 1
# when find fails (SCRATCH holds its list: in a pipe its failure would go unseen)
out_dir_links() {
    find "$1" -xdev -type l > "$2" || { echo "find failed in $1"; return 1; }
    while IFS= read -r _l; do
        _p=$(readlink "$_l") || { echo "${_l#"$1"} -> (unreadable)"; continue; }
        case $_p in
            # an absolute one always leaves the image in the container
            /*) ;;
            # a relative one leaves it when it climbs past / lexically (from the link's directory), or
            # when, followed here, it does not end inside the root (through an absolute link on its
            # way, such as /var/run, or one that only resolves in the image)
            *) _d=${_l#"$1"}
               if ! printf '%s/%s\n' "${_d%/*}" "$_p" | awk -F/ '{
                   n = 0; for (i = 1; i <= NF; i++) if ($i == "..") { if (--n < 0) exit 0 } else if ($i != "" && $i != ".") n++
                   exit 1 }'; then
                   if _t=$(readlink -f "$_l"); then
                       case $_t in "$1" | "$1"/*) continue ;; esac
                   fi
               fi ;;
        esac
        # what it names: a directory in the image (followed there) or here (where sanitize follows it)
        _t=$(inroot "$1" "$_l")
        if [ -z "$_t" ]; then echo "${_l#"$1"} -> $_p (does not resolve in the image)"; continue; fi
        [ -d "$_t" ] || [ -d "$_l" ] || continue
        _ok=; set -f   # the entries split into patterns, not file names
        for _g in $OUT_DIR_LINKS_OK; do
            # shellcheck disable=SC2254 # the entries are patterns
            case ${_l#"$1"} in $_g) _ok=1 ;; esac
        done; set +f
        [ -n "$_ok" ] || printf '%s -> %s\n' "${_l#"$1"}" "$_p"
    done < "$2"
}
```

（判斷相對連結是否爬出根目錄用的是字面上的 `..`。路上經過別的連結、或名稱裏有換行的連結，字面判斷可能漏掉，但這種連結要刻意製造；Ubuntu 的根目錄裏沒有往上爬的相對連結。sanitize 和 check-rootfs 都沒有用 `set -f`，所以函式裏的 `set +f` 只是還原。）

用 `OUT_DIR_LINKS_OK` 的 uv 那一條另外加一個測試：`make-fake-root.sh` 在 `.local/share/uv/python` 裏加上 `mkdir -p home/ubuntu/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu` 和 `ln -s /home/ubuntu/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu home/ubuntu/.local/share/uv/python/cpython-3.12-linux-aarch64-gnu`（uv 0.13 實際的樣子），所以每一次 sanitize 和 check-rootfs 都要接受它，原有的測試才會通過。網關 `.venv` 的 Python 也照 uv 0.13 的樣子經過這個連結：`echo py > $H/.local/share/uv/python/bin/python3` 那一行之後加上 `echo py > $H/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu/bin/python3.12`（目錄先 `mkdir -p`），`.venv/bin/python` 的連結改為 `ln -s /home/ubuntu/.local/share/uv/python/cpython-3.12-linux-aarch64-gnu/bin/python3.12 $HUB/main/xiaozhi-server/.venv/bin/python`；`test-sanitize.sh` 的 `broken "the gateway's Python missing"` 改為搬走、搬回 `$R/home/ubuntu/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu/bin/python3.12`（項數不變）。舊的 `inroot()` 在這個樣子上會報 `the gateway's .venv has no Python`，所以 `the image passes check-rootfs` 那幾項在改動前的 `check-rootfs.sh` 上也會失敗（不算在下面 24 項新測試裏）。

（`inroot` 從 `check-rootfs.sh` 搬來這裏，多一個 ROOT 參數，`out_dir_links` 也用它：一個連結在容器裏離開映像（絕對連結都是；相對連結字面上爬出根目錄，或在這裏跟過去不落在根目錄裏），而且在映像裏（`inroot`）或在容器裏指向目錄，就列出來；在映像裏解析不了的也列出來。只看容器那一邊，經過 uv 小版本連結、只在映像裏存在的目錄會被漏掉；只看字面，經過 `/var/run` 這種絕對連結的相對連結會被漏掉。`out_dir_links` 走整個根目錄一次，跟 sanitize 開頭的連結防護一樣：Task 8 的打包紀錄寫下它花了多久。）

- [ ] **`build-image.sh`**

檔頭說明 `HUB_MAIN` 那一行改為：

```bash
#            HUB_MAIN=main checks against the local main before it is pushed: test images only.
```

`HUB_MAIN=${HUB_MAIN:-origin/main}` 和之後的 fetch 改為：

```bash
HUB_MAIN=${HUB_MAIN:-origin/main}
# a commit checked against the local main only may never reach GitHub: devices could not update
if [ "$HUB_MAIN" != origin/main ] && [ "$SECRETS" != --test-image ] && [ "${ALLOW_UNRELEASED:-}" != 1 ]; then
    echo "HUB_MAIN=$HUB_MAIN is for test images only (--test-image or ALLOW_UNRELEASED=1)"; exit 1
fi
if [ "$HUB_MAIN" = origin/main ]; then
    git -C "$HUB" fetch -q origin +refs/heads/main:refs/remotes/origin/main
    # the published main itself, not whatever the fetch left in the clone
    [ "$(git -C "$HUB" rev-parse refs/remotes/origin/main)" = "$(git -C "$HUB" ls-remote origin refs/heads/main | cut -f1)" ] \
        || { echo "$HUB: origin/main is not GitHub's main after the fetch"; exit 1; }
fi
```

命名的條件和未 commit 改動的檢查不變。

- [ ] **`sanitize-rootfs.sh`**

`. "$S/allowlist.sh"` 那一行之後（任何刪除和寫入之前）加上：

```sh
# links that would take the changes below into the build container instead of the image
out_dir_links "$R" "$L.links" > "$L" || { cat "$L"; rm -f "$L.links"; exit 1; }
rm -f "$L.links"
for f in $WRITTEN_FILES; do
    if [ -L "$R/$f" ]; then echo "/$f -> $(readlink "$R/$f")"; fi
done >> "$L"
if [ -s "$L" ]; then
    echo "sanitize: links where it deletes or writes (replace them on the device with what they point at):"; cat "$L"; exit 1
fi
```

（`$L` 是開頭連結防護用過的暫存檔，這裏重新寫過。）

`edit()` 裏 `ROWS=$rows ...` 之前加上 `rm -f "$f.sanitize"`（擷取結果裏那個暫存檔若是連結，寫入會穿過它）。`edit passwd plain` 改為 `edit passwd passwd`（`subuid`、`subgid` 仍是 `plain`，它們只有三欄），awk 裏 root 那一行之後加上：

```awk
        kind == "passwd" && $1 == "ubuntu" { $5 = "Ubuntu" }
```

`edit ... subgid plain` 那一行之後加上：

```sh
# ubuntu's name (above), photo and e-mail are the mother device owner's: the image's ubuntu keeps
# only its session and language settings (not a link: checked at the top; a directory there fails
# check-rootfs)
A=$R/var/lib/AccountsService
rm -f "$A/icons/ubuntu"
if [ -f "$A/users/ubuntu" ]; then
    rm -f "$A/users/ubuntu.sanitize"
    awk "$ACCOUNTS_KEEP" "$A/users/ubuntu" > "$A/users/ubuntu.sanitize"
    cat "$A/users/ubuntu.sanitize" > "$A/users/ubuntu"
    rm -f "$A/users/ubuntu.sanitize"
fi
```

把寫 `/etc/hostname`、`/etc/hosts`、`/etc/timezone` 的四行（`printf 'thinksmart\n' > ...`、`sed -i '/^127\.0\.1\.1[[:space:]]/d' ...`、`printf '127.0.1.1\tthinksmart\n' >> ...`、`printf 'Etc/UTC\n' > ...`）換成：

```sh
# /etc/hosts whole: the owner's LAN names in it are no one else's (none of these is a link: checked at
# the top)
rm -f "$R/etc/machine-info"
printf 'thinksmart\n' > "$R/etc/hostname"
stock_hosts > "$R/etc/hosts"
printf 'Etc/UTC\n' > "$R/etc/timezone"
```

- [ ] **`check-rootfs.sh`**

在 `# files named for an account` 那段之前加上：

```sh
# no link where sanitize deleted or wrote: the checks below would read through it into the container
out_dir_links "$R" "$T/links" > "$T/x" || bad "$(cat "$T/x")"
[ ! -s "$T/x" ] || bad "links out of the root: $(head -5 "$T/x" | tr '\n' ' ')"
for f in $WRITTEN_FILES; do
    [ ! -L "$R/$f" ] || bad "/$f is a link"
done
# ubuntu's account says Ubuntu: no owner's name, photo or e-mail
awk -F: '$1 == "ubuntu" && $5 == "Ubuntu" {f = 1} END {exit !f}' "$R/etc/passwd" \
    || bad "ubuntu's name in /etc/passwd is not Ubuntu (the mother device owner's?)"
absent "$R/var/lib/AccountsService/icons/ubuntu" || bad "ubuntu's AccountsService photo is still there"
U=$R/var/lib/AccountsService/users/ubuntu
if [ -e "$U" ] || [ -L "$U" ]; then
    # (awk exits 2 on a file it cannot read: that fails too)
    if [ -L "$U" ] || [ ! -f "$U" ]; then bad "/var/lib/AccountsService/users/ubuntu is not a regular file"
    elif ! awk "!($ACCOUNTS_KEEP) {f = 1} END {exit f}" "$U"; then
        bad "ubuntu's AccountsService entry holds more than its session and language settings"
    fi
fi
```

刪掉 `check-rootfs.sh` 裏的 `inroot()`（搬到 `allowlist.sh`，見上），網關 `.venv` 那一行改為 `py=$(inroot "$R" "$SRV/.venv/bin/python")`。舊的只解析路徑最後一段，uv 0.13 的 `.venv/bin/python` 卻是經過 Python 小版本那個目錄連結（`…/uv/python/cpython-3.12-linux-aarch64-gnu/bin/python3.12`），在容器裏會讀到容器自己的 `/`，網關 `.venv` 的檢查就失敗。

`/etc/hosts` 的檢查（`grep -c '^127\.0\.1\.1...` 那個 `if`）換成：

```sh
# (none of them a link: checked with WRITTEN_FILES above)
{ [ -f "$R/etc/machine-id" ] && [ ! -s "$R/etc/machine-id" ]; } || bad "/etc/machine-id is not an empty file (each device makes its own)"
stock_hosts | cmp -s - "$R/etc/hosts" || bad "/etc/hosts is not Ubuntu's stock file for thinksmart"
absent "$R/etc/machine-info" || bad "/etc/machine-info is still there"
```

timesyncd 的 `grep -qxF 'NTP=...'` 那一行之後加上：

```sh
# no other drop-in (in /etc after ours, or in /run, /usr/local/lib, /usr/lib) may change NTP= again;
# a link there would hide its drop-ins from find, and names says "(unreadable)" when it cannot list
for t in etc run usr/local/lib usr/lib; do
    p=$R/$t/systemd/timesyncd.conf.d
    if [ "$t" = etc ]; then want='thinksmart.conf '; else want=; fi
    if [ -L "$p" ]; then bad "/$t/systemd/timesyncd.conf.d is a link"
    elif [ -e "$p" ] && [ "$(names "$p")" != "$want" ]; then
        bad "timesyncd drop-ins other than ours in /$t/systemd/timesyncd.conf.d: $(names "$p")"
    fi
done
```

- [ ] **`test-sanitize.sh` 和 `make-fake-root.sh`**

`make-fake-root.sh`：ubuntu 的 passwd 行改為 `ubuntu:x:1000:1000:Mother Owner,,,:/home/ubuntu:/bin/bash`；`etc/hosts` 那一行改為 `printf '127.0.0.1\tlocalhost\n127.0.1.1\tmother-host\n192.168.1.20\tnas.home\n' > etc/hosts`，之後加上 `echo 'PRETTY_HOSTNAME=Mother Owner tablet' > etc/machine-info`；在 alice 的 AccountsService 檔之後加上：

```sh
mkdir -p var/lib/AccountsService/icons
printf '[User]\nSession=plasma\nIcon=/var/lib/AccountsService/icons/ubuntu\nEmail=owner@example.invalid\nSystemAccount=false\n' > var/lib/AccountsService/users/ubuntu
echo 'photo' > var/lib/AccountsService/icons/ubuntu
```

`test-sanitize.sh`：在 `alice's AccountsService entry gone` 之後加上：

```sh
t "ubuntu's name is Ubuntu" grep -qx 'ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash' "$R/etc/passwd"
nt "ubuntu's photo gone" test -e "$R/var/lib/AccountsService/icons/ubuntu"
nt "ubuntu's e-mail and photo path gone" grep -qE '^(Email|Icon)=' "$R/var/lib/AccountsService/users/ubuntu"
t "ubuntu's session kept" grep -qx 'Session=plasma' "$R/var/lib/AccountsService/users/ubuntu"
t "hosts is Ubuntu's stock file" sh -c '. "$1/allowlist.sh"; stock_hosts | cmp -s - "$2/etc/hosts"' sh "$IMG" "$R"
nt "machine-info gone" test -e "$R/etc/machine-info"
```

（`sh -c` 那一行前面加 `# shellcheck disable=SC2016 # the inner sh expands them`。）在 `broken "ubuntu without passwordless sudo"` 之前加上：

```sh
broken "ubuntu named after the owner" "sed -i 's/^ubuntu:x:1000:1000:Ubuntu:/ubuntu:x:1000:1000:Mother Owner:/' '$R/etc/passwd'" \
    "sed -i 's/^ubuntu:x:1000:1000:Mother Owner:/ubuntu:x:1000:1000:Ubuntu:/' '$R/etc/passwd'"
broken "ubuntu's AccountsService photo" "echo photo > '$R/var/lib/AccountsService/icons/ubuntu'" "rm '$R/var/lib/AccountsService/icons/ubuntu'"
broken "an e-mail in ubuntu's AccountsService entry" "echo Email=owner@example.invalid >> '$R/var/lib/AccountsService/users/ubuntu'" "sed -i '\$d' '$R/var/lib/AccountsService/users/ubuntu'"
broken "ubuntu's AccountsService entry as a link" "mv '$R/var/lib/AccountsService/users/ubuntu' '$T/as-ubuntu'; ln -s /etc/passwd '$R/var/lib/AccountsService/users/ubuntu'" \
    "rm '$R/var/lib/AccountsService/users/ubuntu'; mv '$T/as-ubuntu' '$R/var/lib/AccountsService/users/ubuntu'"
broken "a LAN name in /etc/hosts" "echo '192.168.1.20 nas.home' >> '$R/etc/hosts'" "sed -i '\$d' '$R/etc/hosts'"
broken "/etc/machine-info" "echo 'PRETTY_HOSTNAME=x' > '$R/etc/machine-info'" "rm '$R/etc/machine-info'"
broken "a name after ubuntu's session" "sed -i 's/^Session=plasma$/Session=plasma RealName=Owner/' '$R/var/lib/AccountsService/users/ubuntu'" \
    "sed -i 's/^Session=plasma RealName=Owner$/Session=plasma/' '$R/var/lib/AccountsService/users/ubuntu'"
broken "/etc/hosts as a link" "mv '$R/etc/hosts' '$T/hosts'; ln -s '$T/stock-hosts' '$R/etc/hosts'" "rm '$R/etc/hosts'; mv '$T/hosts' '$R/etc/hosts'"
broken "a timesyncd drop-in after ours" "echo 'NTP=time.example.invalid' > '$R/etc/systemd/timesyncd.conf.d/zz-other.conf'" "rm '$R/etc/systemd/timesyncd.conf.d/zz-other.conf'"
broken "AccountsService icons as a link" "mv '$R/var/lib/AccountsService/icons' '$T/icons-dir'; ln -s '$T/icons-dir' '$R/var/lib/AccountsService/icons'" \
    "rm '$R/var/lib/AccountsService/icons'; mv '$T/icons-dir' '$R/var/lib/AccountsService/icons'"
```

`/etc/hosts as a link` 指向的 `$T/stock-hosts` 跟 `stock_hosts` 的內容完全相同，所以只有「不是連結」那個檢查擋得下它。在這些 `broken` 之前產生它：

```sh
# shellcheck disable=SC2016 # the inner sh expands them
# (|| : so the run on the old allowlist.sh, which has no stock_hosts, gets to its failures;
# "hosts is Ubuntu's stock file" fails when stock_hosts does)
sh -c '. "$1/allowlist.sh"; stock_hosts' sh "$IMG" > "$T/stock-hosts" || :
```

在 `nothing written through the link` 那一行之後加上：

```sh
# AccountsService's icons as a link out of the root: sanitize stops before it changes anything
R=$T/root9
sh "$IMG/tests/make-fake-root.sh" "$R"
mv "$R/var/lib/AccountsService/icons" "$T/icons9"; ln -s "$T/icons9" "$R/var/lib/AccountsService/icons"
nt "sanitize refuses linked AccountsService icons" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing deleted through the icons link" test -f "$T/icons9/ubuntu"

# /etc/hosts as a link out of the root (not into the build's own directories): sanitize stops and
# writes nothing through it
R=$T/root10
sh "$IMG/tests/make-fake-root.sh" "$R"
printf '192.168.1.20\tnas.home\n' > "$T/lan-hosts"; rm "$R/etc/hosts"; ln -s "$T/lan-hosts" "$R/etc/hosts"
nt "sanitize refuses a linked /etc/hosts" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing written through the hosts link" grep -qx '192.168.1.20	nas.home' "$T/lan-hosts"
```

（`grep -qx` 那一行的引號裏是一個 tab。）再加上兩組（root12：AccountsService 的 icons 搬到 `cpython-3.12.11-linux-aarch64-gnu/icons`，用經過 uv 小版本連結的絕對連結指過去，`sanitize refuses icons behind uv's link` 和 `nothing deleted behind uv's link`；root11：`etc/passwd.sanitize` 和 `users/ubuntu.sanitize` 是指到根目錄外檔案的連結，`sanitize runs over linked scratch files` 和 `nothing written through the scratch-file links`），以及四個 `broken`：網關的 Python 經過 42 個目錄連結、經過 `file/..`、經過 `file/.`，和一個經過 `/var/run` 離開根目錄的相對連結（`ln -s /run var/run; ln -s ../run/../../etc var/lib/out`）。程式碼見 commit e1d1526 的 `test-sanitize.sh`。

在 `AccountsService icons as a link` 之後再加上：

```sh
broken "a machine-id" "echo 0123456789abcdef0123456789abcdef > '$R/etc/machine-id'" ": > '$R/etc/machine-id'"
broken "a timesyncd drop-in directory as a link" "mkdir -p '$R/run/systemd' '$R/usr/share/td'; echo 'NTP=time.example.invalid' > '$R/usr/share/td/a.conf'; ln -s ../../usr/share/td '$R/run/systemd/timesyncd.conf.d'" \
    "rm '$R/run/systemd/timesyncd.conf.d'; rm -r '$R/usr/share/td'"
```

（第二個是根目錄裏的相對連結，`out_dir_links` 不管它，只有 timesyncd 那一段的「不是連結」擋得下。）再加上：

```sh
broken "a relative link climbing out of the root" "ln -s ../../../../../../../tmp '$R/etc/climb'" "rm '$R/etc/climb'"
broken "/var/log as a link inside the root" "mv '$R/var/log' '$R/var/log.real'; ln -s log.real '$R/var/log'" "rm '$R/var/log'; mv '$R/var/log.real' '$R/var/log'"
```

- [ ] **`test-build-image.sh`（新）**

`build-image.sh` 在呼叫 Docker 之前就停下的檢查，不需要 Docker：

```sh
#!/bin/sh
# build-image.sh's checks that stop it before Docker runs:
#   sh image/tests/test-build-image.sh
set -eu
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
IMG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; failed=1; }
# a capture whose hub commit is on no main (each run must stop before Docker), and a release manifest
# naming exactly its versions
mkdir -p "$T/work" "$T/hub"
printf '%s\n1.0.0\n5\nabc\n' 0000000000000000000000000000000000000000 > "$T/work/versions.txt"
echo '{"version": "1.0.0", "system": {"version": "5", "tree": "abc"}}' > "$T/manifest.json"
echo 'a secret' > "$T/secrets.txt"
git -C "$T/hub" init -q -b main
git -C "$T/hub" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m x
git -C "$T/hub" remote add origin https://github.com/ohimsmart/oh-im-smart-gateway.git
git -C "$T/hub" update-ref refs/remotes/origin/main HEAD
# build-image.sh clears every GIT_* variable: an empty HOME keeps the caller's ~/.gitconfig (an
# insteadOf would change the origin URL it checks) away from it
run() { HOME=$T XDG_CONFIG_HOME=$T bash "$IMG/build-image.sh" "$T/work" "$T/out" "$T/hub" "$@" > "$T/log" 2>&1; }
# git, but fetch does nothing and ls-remote answers $LSREMOTE: the published-main check without GitHub
REALGIT=$(command -v git)
mkdir "$T/bin"
# shellcheck disable=SC2016 # the generated script expands them when it runs
printf '#!/bin/sh\nfor a; do case $a in fetch) exit 0 ;; ls-remote) printf "%%s\\trefs/heads/main\\n" "$LSREMOTE"; exit 0 ;; esac; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/bin/git"
chmod +x "$T/bin/git"
HEADC=$(git -C "$T/hub" rev-parse HEAD)

if HUB_MAIN=main RELEASE_MANIFEST=$T/manifest.json run "$T/secrets.txt"; then no "HUB_MAIN=main refused for a release"
elif grep -q 'is for test images only' "$T/log"; then ok "HUB_MAIN=main refused for a release"
else no "HUB_MAIN=main refused for a release"; fi
# a test image may: it gets past the check and stops at the hub commit (not on that main)
if HUB_MAIN=main ALLOW_UNRELEASED=1 run --test-image; then no "HUB_MAIN=main allowed for a test image"
elif grep -q 'is not on main' "$T/log" && ! grep -q 'is for test images only' "$T/log"; then ok "HUB_MAIN=main allowed for a test image"
else no "HUB_MAIN=main allowed for a test image"; fi
# origin/main must be what GitHub says main is
if PATH=$T/bin:$PATH LSREMOTE=1111111111111111111111111111111111111111 ALLOW_UNRELEASED=1 run --test-image; then
    no "an origin/main that is not GitHub's main refused"
elif grep -q "origin/main is not GitHub's main" "$T/log"; then ok "an origin/main that is not GitHub's main refused"
else no "an origin/main that is not GitHub's main refused"; fi
if PATH=$T/bin:$PATH LSREMOTE=$HEADC ALLOW_UNRELEASED=1 run --test-image; then no "GitHub's main accepted"
elif grep -q 'is not on origin/main' "$T/log" && ! grep -q "is not GitHub's main" "$T/log"; then ok "GitHub's main accepted"
else no "GitHub's main accepted"; fi

echo "1..$n"
exit "$failed"
```

- [ ] **驗證**

```bash
fakeroot sh image/tests/test-sanitize.sh > /tmp/test-sanitize.out; echo "exit $?"
sh image/tests/test-build-image.sh > /tmp/test-build.out; echo "exit $?"
grep -c '^not ok' /tmp/test-sanitize.out /tmp/test-build.out
shellcheck -x -s sh image/allowlist.sh image/check-rootfs.sh image/sanitize-rootfs.sh image/tests/test-sanitize.sh image/tests/make-fake-root.sh image/tests/test-build-image.sh
shellcheck image/build-image.sh
```

Expected：兩個 `exit 0`；兩個 `not ok` 計數都是 `0`（`test-sanitize.sh` 共 232 項，`test-build-image.sh` 4 項）；shellcheck 沒有輸出。新加的 24 項分兩次對照改動前的程式（各在一份工作樹的副本裏）：（一）改動前的 `sanitize-rootfs.sh`、`check-rootfs.sh`、`allowlist.sh`：7 項 sanitize 的 `t`/`nt`（ubuntu 的名稱、頭像、e-mail、stock hosts、machine-info、兩個 `sanitize refuses`）必須失敗，`ubuntu's session kept`、`nothing deleted through the icons link`（舊的 sanitize 不碰 ubuntu 的頭像）和 `nothing written through the hosts link`（舊的 `sed -i` 換掉連結本身）通過；這一次 `broken` 不算數：舊的 sanitize 留下區網名稱，舊的 check-rootfs 在乾淨的映像上就失敗，每個 `broken` 都「抓到」。（二）新的 sanitize 和 `allowlist.sh`，加上改動前的 `check-rootfs.sh`（只換上新的 `inroot()`，乾淨的映像才通過）：14 項新的 `check-rootfs catches` 都必須失敗。合計 21 項失敗。commit 審查時加的 8 項裏，對準缺口的 6 項（四個 `broken`、`nothing written through the scratch-file links`、`sanitize refuses icons behind uv's link`）都在加它之前那一版的程式上失敗過。另外只把 `inroot()` 換回舊的，`check-rootfs passes after sanitize` 必須失敗；改動前的 `build-image.sh` 跑 `test-build-image.sh`，第 1、3 項必須失敗。

- [ ] **Commit**

```bash
git add kiosk/timesyncd.conf image/allowlist.sh image/build-image.sh image/sanitize-rootfs.sh image/check-rootfs.sh image/tests/make-fake-root.sh image/tests/test-sanitize.sh image/tests/test-build-image.sh
git commit -m "fix(image): local-main gateway checks only for test images; no owner's name, photo or LAN names in the image"
```

---

### Task 8: 在 UM 用真正的擷取結果打包（測試映像）

這一步要用到母機和網關計劃的成果。前置條件如下，未滿足時把這個 task 標為 blocked，Task 1–7b 照樣 merge：

- chris 已加入 docker group；
- 已安裝 `qemu-user-static` 和 `binfmt-support`；
- 網關計劃已 merge。

**Files:**
- Create: `screen/vcnl4200-proximity-daemon.service`（從母機取得）
- Modify（按結果）：`image/system-files.txt`、`image/home-allowlist.txt`、`image/hub-ignored.txt`、`image/upstream-provenance.txt`；按下面失敗表格改動的 `image/sanitize-rootfs.sh`、`image/check-rootfs.sh` 和補上的測試，也放進同一個 commit

- [ ] **把母機上的接近感應服務檔收進 repo**

```bash
scp ubuntu@<母機>:.config/systemd/user/vcnl4200-proximity-daemon.service screen/
```

在 `image/system-files.txt` 的 `screen/vcnl4200-proximity-daemon.py` 那一行之後加上：

```
screen/vcnl4200-proximity-daemon.service /home/ubuntu/.config/systemd/user/vcnl4200-proximity-daemon.service 644 ubuntu user:vcnl4200-proximity-daemon.service
```

讀一遍檔案，確認裏面沒有 key 或個人路徑。然後跑 `GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q update` 和 `fakeroot sh image/tests/test-sanitize.sh`，兩者都必須全部通過。

- [ ] **母機裝上這個分支的系統層**

母機上還是舊的系統層：舊的 NTP 設定和舊的 `welcome.html` 都還指向上游。所以先在母機上，用這個分支的 checkout 執行：

```bash
sudo sh image/device-setup.sh files
```

母機上的網關 checkout 照 spec §5.3 第 6 點第 2、3 步換到我們網關的 `main`（舊的 HEAD 是新 `main` 的祖先，所以 build-image.sh 的祖先檢查擋不下舊版本，必須在這裏換）：

```bash
( set -e   # 任何一步失敗（包括 fetch 和祖先檢查）就整段停下，不重啟網關
cd ~/xiaozhi-hub-server
git remote set-url origin https://github.com/ohimsmart/oh-im-smart-gateway.git
git fetch origin +refs/heads/main:refs/remotes/origin/main
git merge-base --is-ancestor HEAD origin/main
git checkout -q main
git merge -q --ff-only origin/main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
systemctl --user restart xiaozhi-hub.service
echo "gateway on origin/main" )
```

Expected：印出 `gateway on origin/main`。沒有印出就停下，回報是哪一步失敗。

確認網關已啟用自動啟動（`systemctl --user is-enabled xiaozhi-hub.service` 印出 `enabled`），而且沒有進行中的更新（`/var/lib/thinksmart-update/` 裏沒有 `pending.json` 或 `system-pending.json`）。

- [ ] **擷取和打包測試映像**

```bash
set -o pipefail   # 否則打包那一行的結束碼是 tee 的
rm -rf ~/tsimg/work &&   # 先清空：擷取失敗時不會拿上一次的封存去打包
TS_HOST=<母機 IP> image/pull-from-device.sh ~/tsimg/work &&
time ALLOW_UNRELEASED=1 image/build-image.sh ~/tsimg/work ~/tsimg/out ~/src/oh-im-smart-gateway --test-image 2>&1 | tee ~/tsimg/build.log
```

Expected：
- 結束碼 0；
- `~/src/oh-im-smart-gateway` 的 `origin` 必須正好是 `https://github.com/ohimsmart/oh-im-smart-gateway.git`（用 SSH clone 的話先 `git remote set-url origin` 改成這個網址），否則打包一開始就停下；
- 依次看到 `== sanitize`、`== hub repository`、`check-rootfs: ok`，然後檔案樹、boot 檔案、每個解開的 initramfs、整個映像各一次 `privacy check ok`。母機的主機名稱是 `thinksmart`、`ubuntu` 或 `localhost` 時，每一次掃描都先印 `TEST IMAGE` 提示；否則印 `owner secret #1`（主機名稱）的計數，必須是 0；
- 最後產生 `~/tsimg/out/<name>-TEST-DO-NOT-PUBLISH.img.xz`；
- 在紀錄裏記下 `privacy check over the whole image` 這一步花了多久（`==` 行後面的時間，跟下一行 `== package list` 相減），因為 `grep -Pz` 掃描整個映像的時間未經實測。

- [ ] **逐行看 sanitize 刪掉了甚麼**

Run: `grep -e 'removed /home/' -e 'clean-hub-git: ignored:' ~/tsimg/build.log`

每一行都要能說出那是甚麼。裝置需要的檔案要放進 repo 和 `system-files.txt`，或加入允許清單，然後重新打包。

- [ ] **按失敗訊息處理，不能為了通過而放寬比對規則**

| 命中的內容 | 處理 |
|---|---|
| `system layer differs` | 母機沒有裝上這個分支的系統層：回到上一步 |
| `timesyncd drop-ins other than ours` | 在母機上刪掉訊息列出的檔案（`NTP=` 只能來自 `kiosk/timesyncd.conf`），然後重新擷取 |
| `links where it deletes or writes`（sanitize）、`links out of the root`、`/<路徑> is a link`（check-rootfs） | 每一條先查清是甚麼。母機自己做的：在母機上換成真正的目錄或檔案（連結指向的內容搬過去），或換成根目錄裏的相對連結，然後重新擷取。Ubuntu 或套件原有、而且 sanitize 不在它底下刪改任何東西的目錄連結：加入 `allowlist.sh` 的 `OUT_DIR_LINKS_OK`，寫明是哪個套件的 |
| ubuntu 的名稱、AccountsService、`/etc/hosts`、`/etc/machine-info` 的失敗 | sanitize 應該已經處理：是 sanitize 的錯，修 `sanitize-rootfs.sh` 並加測試，不是改母機 |
| `<路徑> is not mode <權限>, owner <擁有者>` | 內容已相同的檔案 `device-setup.sh files` 會跳過，不會修正權限：在母機上照 `image/system-files.txt` 那一行執行 `sudo chmod <權限> <路徑>` 和 `sudo chown <擁有者> <路徑>`，然後重新擷取 |
| `not on home-allowlist.txt`、`missing …` | 查清楚那個檔案是甚麼。裝置需要的放進 repo 和允許清單；母機缺少的在母機修正後重新擷取，不要從清單刪除 |
| 系統層檔案裏的上游網址 | 不加入允許清單，回到 Task 1 修改來源檔 |
| 網關或客戶端檔案裏的上游網址 | 屬於出處標示的才加 `line` 條目；安裝或 clone 指令要回到網關或客戶端計劃修改 |
| 帳號、家目錄在 `/home` 以外 | 在母機上處理那個帳號，然後重新擷取 |
| sanitize 的 `names both <帳號> and ubuntu` | 在母機上把那個帳號從該 sudoers 檔拿掉（`sudo visudo -f`），然後重新擷取 |
| `sudo policy this check does not know` | 看印出的那幾行。是 Ubuntu 原本就有、不影響 ubuntu 免密碼 sudo 的寫法，才把它加入 `check-rootfs.sh` 的允許清單並補一個測試；要求密碼、`requiretty`、別的 `secure_path`、權限不對的檔案，都在母機上修正後重新擷取 |
| `file names with an owner identifier` | 在母機上改名或刪除那個檔案，然後重新擷取 |
| `files of an owner (u) or group (g) id with no /etc/passwd or /etc/group entry` | 在母機上用 `find / -xdev -uid <id>`（或 `-gid`）找出那些檔案：已刪帳號的刪除，裝置需要的改為 root 或 ubuntu 擁有，然後重新擷取 |
| 主機名稱（`owner secret #1`）的命中 | 在母機上用 `grep -rlF <主機名稱>` 找出位置；屬於母機身分的在 sanitize 加一條清理並補測試 |
| `ignored files in the gateway not on hub-ignored.txt` | 網關需要的加入 `hub-ignored.txt`（它的 `main/xiaozhi-server/.venv/` 已在清單裏）；其餘在母機上刪除後重新擷取 |
| 檔案樹掃描的 key 命中（印出的路徑） | 查清楚那是甚麼：母機自己產生的 key（例如 `ssl-cert` 的 `snakeoil` key）在 sanitize 加一條刪除並補測試；套件裏的測試用 key 要回報，不能放寬規則 |
| 秘密檔的命中（只有計數） | 在母機上用 `grep -rlF` 找出位置並處理，然後重新擷取 |
| 連結 | 母機上把該目錄換成實際的目錄，然後重新擷取 |

- [ ] **用正式的秘密檔再跑一次**

```bash
ALLOW_UNRELEASED=1 image/build-image.sh ~/tsimg/work ~/tsimg/out-secrets ~/src/oh-im-smart-gateway ~/tsimg/secrets.txt
```

`~/tsimg/secrets.txt` 至少列出：
- 維護者的電郵；
- 母機用過的 Wi-Fi 名稱；
- 網關後台設定過的每一個 API key。

這個檔案不放進任何 repo。

Expected：通過，`owner secret #1` 起每一項的計數都是 0；用另一個輸出目錄，不蓋掉上一次的 `SHA256SUMS`。`ALLOW_UNRELEASED=1` 的映像同樣命名為 `-TEST-DO-NOT-PUBLISH`：這一步只證明秘密檔的掃描通過，正式映像在「教學和映像 Release」計劃裏產生。

- [ ] **再跑兩個測試，確認清單改動沒有破壞它們**

```bash
fakeroot sh image/tests/test-sanitize.sh > /tmp/test-sanitize.out; echo "exit $?"
sh image/tests/test-image-privacy.sh > /tmp/test-privacy.out; echo "exit $?"
grep -h '^not ok' /tmp/test-sanitize.out /tmp/test-privacy.out
```

Expected：兩個 `exit 0`，`grep` 沒有輸出。

- [ ] **Commit**

```bash
git add screen/vcnl4200-proximity-daemon.service image/system-files.txt image/home-allowlist.txt image/hub-ignored.txt image/upstream-provenance.txt
git add -u image/   # sanitize, check-rootfs and their tests, if the failure table above changed them
git status --short  # nothing under image/ left unstaged or untracked
git commit -m "Image allowlists checked against the mother device capture; proximity unit into the system layer"
```

---

## 不在本計劃內

- 審查第 2 輪中評為 low、刻意不做的項目：
  - `grep -I` 跳過二進位檔，是 spec §5.3 第 5 點的寫法；
  - check-rootfs 的上游網址命中會把整行印進打包紀錄（紀錄只在 UM 上，而且 `line` 條目本來就要整行內容）；
  - `passwd` 的主群組欄、`envs/<id>` 是否真的是目錄：都不屬於本計劃的來源和私人資料範圍（系統層檔案的權限和擁有者，check-rootfs 有檢查，Task 8 的表格有處理方法）；
  - ~~已刪帳號 UID 擁有的其他檔案~~：設計審查後改為在 check-rootfs 檢查（`e110fc1`）。

- §5.3 第 6 點：母機在第一個正式版本前的準備，以及 §5.6 映像 Release 說明和 GPL 原始碼附件，都屬於「教學和映像 Release」計劃。
- README 裏的網址，同樣屬於「教學和映像 Release」計劃。
- 網關 repo 裏的網址（`bootstrap.sh` 等）屬於網關計劃。Task 8 的掃描會證明它已完成。

<!-- design-review-coverage: DEGRADED 1/3 reviewer_1=runtime-failed reviewer_3=runtime-failed -->

<!-- design-reviewed: PENDING -->
