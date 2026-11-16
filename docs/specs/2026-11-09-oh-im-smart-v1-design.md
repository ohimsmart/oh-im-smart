# Oh I'm Smart v1 設計

- 日期：2026-11-09
- 狀態：已口頭確認；blueprint review 7 輪後，維護者決定以 skip 檔進入實作計劃。最後一輪的 8 個中等問題已修正但未再審閱，餘下項目見 `docs/reviews/oh-im-smart-v1-design/follow-up-issues.md`
- 範圍：v1，即可刷機的發行版

## 1. 目標與要解決的問題

**目標：** Oh I'm Smart 是一個 oh-my-zsh 風格的開源發行版，供聯想 ThinkSmart View（CD-18781Y）作語音助手使用。任何人拿着一部原廠裝置，跟着本 repo 的教學刷機，就能得到：

- 繁體中文、简体中文、English 三語介面；
- 可分開設定 API key 的語音辨識（ASR）和語音合成（TTS）；
- 可自選的說話語言；
- MCP 工具設定；
- 之後的線上更新全部來自 Oh I'm Smart 的 repo。

教學提供繁中、简中和英文三個版本。

**v1 的支援程度：** 路線 B（已刷過 postmarketOS／Ubuntu 的裝置）是 v1 驗收過的路線。路線 A（原廠裝置）的教學完整提供，但在有原廠裝置跑完整個流程之前標示為「實驗性」（§7.3、§10）。

**要解決的問題：** 這些改動目前只存在於維護者自己的裝置，以及兩個仍未合併的上游 PR（[client #4](https://github.com/justhalfbit/xiaozhi-thinksmart-client/pull/4)、[gateway #9](https://github.com/justhalfbit/xiaozhi-hub-server/pull/9)）。其他人無法直接使用，而且上游一更新就會把補丁蓋掉。

## 2. 不在 v1 範圍內

- 外掛框架。留待 v1.1，連同第一個外掛：遠端 agent harness 的 MCP server。
- 遠端 agent、Hindsight／Claude-Mem 記憶、其他模型服務。
- 自建網關或 UI。
- 更新簽名（§8）。
- 英文喚醒詞。喚醒詞仍然只有中文，寫明為已知限制。
- 為已裝上游版本的裝置提供遷移腳本。
- 自動偵測時區（§5）。

## 3. 上游

三個上游 repo 都由 justhalfbit 維護。網關和 Ubuntu 映像的 README 寫明是 MIT 授權；客戶端也附有 LICENSE 檔，內容在建立 repo 前要再確認。

| 上游 | 內容 | 更新機制 |
|---|---|---|
| `thinksmart-ubuntu-image` | 刷機教學、系統層、映像製作工具 | 映像放在 Release；系統層隨客戶端的線上更新一起發佈 |
| `xiaozhi-thinksmart-client` | 語音客戶端、觸控介面 | `thinksmart-update`：讀取 `SOURCES`；逐檔核對 sha256；只接受比現有版本**更新**的版本；新版本自檢失敗時才回復 |
| `xiaozhi-hub-server` | 網關、管理後台 | `scripts/update.sh`：`git fetch` 後 `git merge --ff-only`；失敗就回復 |

兩套更新機制都假設每個元件各有一個 repo，所以不用 monorepo。

## 4. Repo 結構和擁有者

GitHub organization：`ohimsmart`（已建立）。

| Repo | 來自 | v1 內容 |
|---|---|---|
| `ohimsmart/oh-im-smart`（主 repo，即本 repo） | thinksmart-ubuntu-image | 三語教學、系統層、bootstrap 準備指令、映像製作、映像 Release |
| `ohimsmart/oh-im-smart-client` | xiaozhi-thinksmart-client | #4 的改動＋英文；線上更新 Release |
| `ohimsmart/oh-im-smart-gateway` | xiaozhi-hub-server | #9 的改動＋英文；裝置上網關的 git remote |

規則：

- **三個都是全新 repo，不是 GitHub fork。** 從上游歷史開始，上游設為 `upstream` remote，出處寫在 LICENSE、NOTICE 和 README。原因：GitHub 的預設搜尋不會顯示 fork。
- **`chris-yyau` 下的兩個 fork 只用來向上游提交 PR。** #4 和 #9 保持開啟。
- **主分支只用 merge**，禁止 rebase 和 force-push，並用分支保護強制執行。原因是網關更新用 `git merge --ff-only`。
- **定期合併上游。** 改動盡量放在新檔案裏。必須修改上游檔案時，改動要集中、小而清楚。

**決策紀錄：** 第一個映像寫進 `/etc/thinksmart-update.conf`（標記為 `keep`）的來源網址，裝置會一直沿用，所以擁有者必須一開始定好。

- 不用個人帳號：日後搬遷要依賴 GitHub 轉址，而舊名稱被重新使用時轉址就會消失。
- 不用 fork：Council 二比二，以「預設搜尋看不到 fork」作為決定性理由。
- 重新評估的時間點：大部分時間都花在同步上游時，就停止同步、正式分家。

## 5. 發佈和映像製作

### 5.1 發佈物

| 發佈物 | 怎樣做 | 發佈到 |
|---|---|---|
| 客戶端和系統層的線上更新 | 在 UM 執行 `update/make-release.py`，arm64 部分用 qemu 模擬 | `oh-im-smart-client` Release，標籤 `c<客戶端版本>-s<系統層版本>` |
| 網關 | merge 到 `oh-im-smart-gateway` 的 `main` | — |
| 刷機映像 | 在 UM 上對母機（維護者的 ThinkSmart）執行 `pull-from-device.sh`，再執行 `build-image.sh` | `oh-im-smart` Release，標籤用日期 |

UM 的前置準備：

- `sudo apt install qemu-user-static binfmt-support`；
- 把 `chris` 加進 docker group。

第一次打包後，要在實機確認客戶端正常運行。遇到模擬問題時，改用 Mac mini 作後備。映像只在內核、驅動或鎖定的套件改變時才重做。

### 5.2 版本規則

更新器按數字比較客戶端的 `__version__` 和系統層的 `VERSION`，只接受較新的版本。

- 每個元件的版本號在我們的 repo 內只升不降。
- 第一個 Oh I'm Smart 版本要高於母機現有的版本（系統層目前是 0.2.1）。我們的系統層從 **1.0.0**、客戶端從 **1.0.0** 開始，避免跟上游日後的 0.x 版本號重疊。
- 每次合併上游後，發佈清單都要確認版本號沒有倒退或撞號，才執行 `make-release.py`。

### 5.3 更新來源以打包流程為準

`/etc/thinksmart-update.conf` 標記為 `keep`，而且 `build-image.sh` 原本會把網關的 remote 寫死為上游，所以單靠修改 repo 裏的預設值，**不會**改變映像實際帶出去的內容。打包流程本身必須負責寫入正確的來源：

1. `update/thinksmart-update.conf`：`SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"`。格式沿用上游，是指向 Releases 的基本網址。
2. `image/sanitize-rootfs.sh`：清理後，用 repo 版本覆寫 `$R/etc/thinksmart-update.conf`。
3. `image/build-image.sh` 裏設定網關 remote 的那一行：網關的 remote 改為 `https://github.com/ohimsmart/oh-im-smart-gateway.git`。`HUB_MAIN` 的檢查也改為對照我們的網關 repo。
4. 網關 repo 內指向上游的網址改為 `ohimsmart/oh-im-smart-gateway`：`scripts/bootstrap.sh` 的預設 repo 和檔案開頭用法說明裏的 `raw.githubusercontent.com` 安裝指令；`bootstrap.sh` 判斷「現有 checkout 是不是本專案」的條件（目前只認 origin 含 `xiaozhi-hub-server`）改為同時接受 `oh-im-smart-gateway`，並加一個測試：對 origin 是新網址的 checkout 重跑 `bootstrap.sh`，必須走到 `scripts/update.sh`；`pipeline.py` 的 `DESIGN_DOC_URL`、管理後台 `index.html` 的 GitHub 連結、`hub-docs/guide.md` 的安裝指令，以及網關和客戶端 `README` 裏的安裝和 clone 指令（例如網關 README 的 `curl … bootstrap.sh | bash` 和 `git clone`）。README 裏指向上游的徽章和出處說明保留，以 `line` 條目列入允許清單。純屬出處標示的字串，例如天氣外掛的 User-Agent，不改動，而是以「檔案路徑＋該行內容」精確列入允許清單。
4a. sanitize 刪除 `/opt/thinksmart/system/backup` 和客戶端的上一版：新刷的裝置沒有可回復的歷史，而這兩處都會含有上游網址。
4b. 主 repo 其他寫死上游的地方一併改為 ohimsmart：`make-release.py` 的 Release 說明、`kiosk/welcome.html` 的 QR 後備連結、`kiosk/thinksmart-kiosk.conf` 的 `HELP_URL`（也是 `keep` 檔，同樣由 sanitize 覆寫）、`build-image.sh` 註解裏的 manifest 網址。
5. **打包檢查：** 順序是 sanitize → 改寫網關 remote（第 3 點）→ 掃描 → `mke2fs`。掃描以檔案樹方式進行：`grep -rInE '(github(usercontent)?\.com[/:]|githubusercontent\.com/)justhalfbit' "$R"`，涵蓋 `https://github.com/`、`git@github.com:` 和 `raw.githubusercontent.com/` 三種寫法，逐行輸出「路徑:行號:內容」。repo 裏已 commit 一份允許清單 `image/upstream-provenance.txt`，路徑一律相對於 `$R`、以 `/` 開頭（例如 `/home/ubuntu/xiaozhi-hub-server/README.md`）。條目有兩種：
   - `file<TAB><路徑模式>`：整個檔案都允許，只用於網關和客戶端目錄下的 `LICENSE*`、`NOTICE*`（README 不在此列，因為它含有會被照着執行的安裝指令）；
   - `line<TAB><路徑><TAB><完整的一行內容>`：只允許那一行，例如天氣外掛的 User-Agent。

   任何一行命中如果不符合清單裏的條目，打包就失敗。

   **來源的正向檢查：** 同樣在 `mke2fs` 之前，`$R/etc/thinksmart-update.conf` 必須含有第 1 點那一行完整的 `SOURCES=`，網關 clone 的 origin 必須等於 `https://github.com/ohimsmart/oh-im-smart-gateway.git`，否則打包失敗。

   **私人資料的掃描：** 對整個 `disk.img` 的原始位元組 grep 繼續保留，並作以下改動：
   - 原有的兩項 SSH 檢查（`ssh-ed25519 AAAA`、`ssh-rsa AAAA`）只能找到公鑰，改名為公鑰檢查。另加私鑰檢查，只認真正的 PEM 區塊：標頭 `-----BEGIN [A-Z ]*PRIVATE KEY-----`（涵蓋 OpenSSH、RSA、EC、PKCS#8，包括 `ENCRYPTED PRIVATE KEY`）後面接換行，可以有加密 PEM 的 `Proc-Type:`、`DEK-Info:` 這類標頭行和一個空行，然後是 40 字元以上的 base64，即 `grep -aPzc -e "-----BEGIN [A-Z ]*PRIVATE KEY-----\r?\n(?:[A-Za-z-]+:[^\n]*\r?\n)*(?:\r?\n)?[A-Za-z0-9+/=]{40,}" disk.img`。標頭前面不設行首錨點，因為原始映像裏檔案邊界不是換行，金鑰前面可能是 0 位元組；`-z` 以 NUL 分段，所以跨換行比對可行。只比對標頭字串會誤判 `cryptography` 的 `serialization/ssh.py` 這類把標頭寫成引號常數的程式庫原始碼（網關經 `pyjwt[crypto]` 依賴它）。以四個合成測試確認：放入一把不在 `SECRETS_FILE` 裏的私鑰，打包必須失敗；同一把金鑰前面加上一串 0 位元組，打包仍然必須失敗；放入一把以密碼加密的傳統 RSA PEM（含 `Proc-Type`、`DEK-Info`），打包必須失敗；放入一行 `_SK_START = b"-----BEGIN OPENSSH PRIVATE KEY-----"`，打包必須通過；
   - API key 的樣式放寬為 `(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{32,}`（`grep -P`），涵蓋 `sk-ant-…` 這類含連字號的 key；前面的 lookbehind 要求 `sk-` 前面不是 key 的字元，因為 base64url 雜湊（例如 wheel 的 `RECORD` 檔）裏也會出現 `sk-`；
   - `SECRETS_FILE` 改為**必填**，而且至少要有一行非空內容，否則打包失敗。只有測試用映像可以用明確的 `--test-image` 參數略過，這種映像不得發佈。
   - 原有寫死的上游作者識別字串（電郵、內網網段、代理位址）屬於上游作者，對我們沒有作用，移除。改為一份已 commit、不含秘密的維護者識別清單 `image/owner-identifiers.txt`（例如母機原本的主機名稱、維護者的電郵）。這份清單**以檔案樹方式**掃描 `$R`，用跟上游網址相同的「路徑＋整行」允許清單機制，所以 LICENSE、NOTICE、README 裏的出處說明可以逐行豁免，不會令打包失敗。
6. **母機的準備：** 在母機安裝第一個 Oh I'm Smart 版本之前：
   1. 手動替換 `/etc/thinksmart-update.conf`。
   2. 網關 clone：把 origin 改為我們的 repo，`git fetch origin`。#9 必須以 merge commit（不是 squash）併入 `oh-im-smart-gateway` 的 `main`，所以母機現有的 `HEAD` 是新 `main` 的祖先。執行 `git merge-base --is-ancestor HEAD origin/main` 確認；成立的話 `git checkout main`（必要時從 `origin/main` 建立）、`git branch -u origin/main`，再執行 `scripts/update.sh`。不成立的話，在旁邊重新 clone 那個 commit，把 `data/` 搬過去再換上。
   3. 確認網關的 `HEAD` 等於本次要發佈的 `main` commit，不相等就停止。
   4. 母機的客戶端是自行安裝的版本，從客戶端頁面更新時會要求確認「取代自訂版本」（`replace_custom`）；§5.6 第 3 步照此確認。
7. **sanitize 需要的 repo 檔案：** 打包容器原本只掛載 `image/`。`build-image.sh` 改為把整個 repo 唯讀掛載在容器的 `/repo`：sanitize 從那裏取要覆寫的設定檔（`update/thinksmart-update.conf`、`kiosk/thinksmart-kiosk.conf`），check-rootfs 從那裏逐檔比對系統層。

### 5.4 母機的私人資料

`pull-from-device.sh` 會擷取整個根檔案系統。

- `sanitize-rootfs.sh` 原本已經會重設 SSH 金鑰、WiFi、`machine-id` 和網關資料。
- **新增**（全部直接操作 `$R` 底下的檔案，不用會修改容器本身的 `userdel` 或 `passwd`）：
  - 把 `$R/etc/shadow` 裏 `ubuntu` 的雜湊換成 repo 裏已 commit 的固定常數，即 `thinksmart` 的 SHA-512 雜湊；
  - 鎖定 `root`（雜湊欄改為 `!`）；
  - 移除 UID 1000–59999 之間、但不是 `ubuntu` 的帳號：它們在 `passwd`、`shadow`、`group`、`gshadow`、`subuid`、`subgid` 裏的條目；`group` 和 `gshadow` 成員清單（例如 `sudo:x:27:ubuntu,<user>`）裏的名字；家目錄、`/var/spool/cron/crontabs/<user>`、`/var/mail/<user>`，以及 `/etc/sudoers.d/` 裏提到該帳號的檔案。`nobody`（65534）等系統帳號不受影響；
  - 刪除 `/etc/shadow-`、`/etc/passwd-`、`/etc/group-`、`/etc/gshadow-`、`/etc/subuid-`、`/etc/subgid-`。這些是系統自動建立的備份，會含有舊的密碼雜湊或帳號名稱；
  - 清空 `$R/root`，只保留 `.bashrc` 和 `.profile`。原本只刪除固定清單裏的檔案，`/root/.config`、`/root/.aws`、`/root/.docker` 之類會漏掉；
  - `ubuntu` 家目錄裏原本整批保留的目錄改為只留指定項目：`~/.config/systemd/user` 只保留 `system-files.txt` 和 `device-setup.sh` 安裝的服務檔和連結，加上網關 `scripts/autostart.sh enable` 安裝的 `xiaozhi-hub.service` 和 `default.target.wants/xiaozhi-hub.service`（少了它們，刷機後網關不會開機自啟）；`~/.config/pipewire`、`~/.config/wireplumber` 只保留這兩處安裝的音效設定檔（例如 `main.lua.d/99-cd18781y-alsa.lua`）；`~/.local` 只保留 `share/uv`（網關 `.venv` 用的 Python）和 `bin/uv`、`bin/uvx`（網關更新依賴時 `scripts/install.sh` 要用 `uv`，缺了會改從 astral.sh 重新下載），其餘全部刪除；
  - `$R/etc/hostname` 改為固定的公開名稱 `thinksmart`；`/etc/hosts` 整個換成 Ubuntu 原本的內容（只有 `localhost`、`thinksmart` 和 IPv6 的固定幾行），母機主人加上的區網名稱不留下；刪除 `/etc/machine-info`；
  - `ubuntu` 帳號的名稱欄（GECOS）改為 `Ubuntu`；刪除 AccountsService 裏 `ubuntu` 的頭像；`users/ubuntu` 只留下 `[User]` 和 `Session=`、`XSession=`、`SystemAccount=`、`Language=` 這幾種完整符合格式的行（`Icon=`、`Email=` 等是母機主人的）；
  - 容器裏的絕對連結指向容器本身，不是映像：擷取結果裏有指向根目錄以外的目錄連結（Ubuntu 原有的 `/var/run`、`/var/lock`，和 uv 在 `~/.local/share/uv/python` 裏從 Python 小版本指向安裝版本的連結除外：沒有東西透過它們刪改；網關 `.venv/bin/python` 經過它們，check-rootfs 檢查它時把路徑上每一段連結都在映像裏解析）、往上爬出根目錄（或經過絕對連結離開根目錄）而指向目錄的相對連結，或 sanitize 要寫的檔案（`passwd` 等帳號檔、`hostname`、`hosts`、`timezone`、`machine-id`、shell 啟動檔、`users/ubuntu`、更新程式的 `status.json`）和它開始 `find` 的目錄（`/etc`、`/home`、`/var/log` 等）是連結，sanitize 就停下、甚麼都不改；
  - shell 啟動檔常被用來 export token，所以不保留母機的版本：`root` 的 `.bashrc`、`.profile` 和 `ubuntu` 的 `.bashrc`、`.profile`、`.bash_logout`，都用 `$R/etc/skel` 的同名檔覆寫，擁有者和權限照原樣設定；
  - 時區重設為 `Etc/UTC`：改寫 `$R/etc/timezone`，並把 `$R/etc/localtime` 連結到對應檔案；
  - 刪除 kiosk 的語言狀態檔（§6.2）。
- **打包檢查：**
  - `$R/etc/shadow` 的 `ubuntu` 雜湊必須跟常數完全相同，`root` 必須是鎖定狀態；
  - `$R/root` 裏只能有上述兩個檔案；上述 shell 啟動檔跟 `$R/etc/skel` 的同名檔逐位元組相同；
  - 上述家目錄裏只留指定項目的目錄，內容必須跟預期的路徑清單完全相同；以一個合成的根檔案系統測試：多一個含假 token 的用戶服務檔，打包必須刪除它，而 `xiaozhi-hub.service` 和它的 `default.target.wants` 連結必須保留；
  - `$R/etc/hostname` 是 `thinksmart`；`/etc/hosts` 跟 Ubuntu 原本的內容逐位元組相同；`/etc/machine-info` 不存在；`machine-id` 是空的一般檔案；
  - `ubuntu` 的名稱欄是 `Ubuntu`，沒有頭像，`users/ubuntu` 只有上述幾種行；
  - 沒有上述的連結；
  - 被移除的帳號名稱不再出現在 `passwd`、`shadow`、`group`、`gshadow`、`subuid`、`subgid` 裏。以一個合成的根檔案系統測試：多一個帳號，帶群組成員資格、crontab 和 `sudoers.d` 檔；
  - kiosk 的語言狀態檔不存在；
  - 任何一項不符合，打包就失敗；
  - 另外使用一份不放入任何 repo 的 `SECRETS_FILE`（必填，見 §5.3 第 5 點），列出 WiFi 名稱、API key、電郵等字串，打包時逐一比對，確認都沒有出現在映像裏。
- 教學的首次設定仍然要求用戶修改 `ubuntu` 的密碼。由於 root 已鎖定，原本「修改 root 密碼」的步驟改為「用 `sudo`」。

### 5.5 時區和 NTP

不併入上游 image repo 的自動時區 PR（[#9](https://github.com/justhalfbit/thinksmart-ubuntu-image/pull/9)）。它每次聯網都會以明文 HTTP 呼叫 ip-api.com，等於把每部裝置的公網 IP 交給第三方，而且回應未經驗證就以 root 身份套用。v1 的做法：

- NTP 改為 `NTP=ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org pool.ntp.org ntp.ubuntu.com`，全部寫在 `NTP=` 裏，依序嘗試。只要設定了 `NTP=`，timesyncd 就會忽略 `FallbackNTP=`，所以不能把國內伺服器放在那裏。裝置沒有 RTC 電池，對時之前 TLS 會失敗，所以必須盡快對時。上游已實測 `ntp.ubuntu.com` 在國內要約 20 秒，因此維持上游「國內可達的伺服器在前」的次序；`ntp.aliyun.com` 在國外也能回應，其他地區只是多試一兩個伺服器。改動只是在後面加上 `pool.ntp.org`。來源檔 `kiosk/timesyncd-cn.conf` 改名為 `timesyncd.conf`，同時更新 `system-files.txt`。安裝路徑不變；`build-image.sh` 原本只檢查檔案存在，改為檢查完整的 `NTP=` 一行。`NTP=` 是累加的（`timesyncd.conf(5)`），所以檔案在那一行之前先放一行空的 `NTP=`，清掉主設定檔 `/etc/systemd/timesyncd.conf` 可能設的伺服器；打包檢查另外要求四個 `systemd/timesyncd.conf.d` 目錄（`/etc`、`/run`、`/usr/local/lib`、`/usr/lib` 下）裏只有這一個 drop-in，而且它們都不是連結。
- `image/device-setup.sh` 不再寫死 `Asia/Shanghai`。映像預設 `Etc/UTC`（見 §5.4）。
- 教學的首次設定加入一步：`sudo timedatectl set-timezone <你的時區>`，並附上三種語言的常見例子，例如 `Asia/Hong_Kong`、`Asia/Shanghai`、`America/Los_Angeles`。
- 由網關後台用電腦瀏覽器的時區一鍵設定，留待 v1 之後再做。

### 5.6 第一個映像的發佈順序

1. 網關和客戶端的改動 merge 到各自的 `main`。
2. 母機按 §5.3 第 6 點準備好。
3. 發佈線上更新 Release；母機經線上更新安裝它，並在實機測試。
4. 擷取母機、打包映像（通過 §5.3 和 §5.4 的檢查），以 **pre-release** 發佈映像。
5. 以這個 pre-release 映像跑一次驗收（§9）。通過後才改為正式的 Latest；不通過就修正並重新打包。

每個映像 Release 的說明要寫明：

- 對應的客戶端、網關和系統層版本；
- 內核、模組的原始碼（GPL-2.0）：每個映像 Release 都**附上**對應的原始碼，不只是連結：`kernel/README.md` 指定的內核原始碼 tarball（附 sha256）、內核 config、`kernel/build.sh` 和 `codec-dmic/`，並寫明打包時 `oh-im-smart` 的 commit；
- `packages.txt`。

## 6. 三語介面

### 6.1 翻譯機制

沿用 #4 和 #9 的做法：以介面上的简中原文作為鍵，每種語言各有一份字典。目前的執行程式碼只認得 `zh-Hans` 和 `zh-Hant` 兩種，所以加英文需要以下**全部**改動：

| 位置 | 改動 |
|---|---|
| 客戶端 `web/i18n.js` | `saved`、`requested` 的允許清單加入 `en`；`normalize()`：以 `zh` 開頭、而且含 `Hant`、`TW`、`HK` 或 `MO` 的對應繁中（沿用原有的 `zh-` 判斷，所以 `en-HK` 仍是英文），其他以 `zh` 開頭的對應简中，其餘對應英文；字典改為三選一；語言選單加 English；先後次序改為 `?lang` → 已記住的值 → 瀏覽器語言（見 §6.2） |
| 客戶端 `web/en.js` | 新檔；在使用 i18n 的頁面加入 `<script>` |
| 網關 `core/admin/static/i18n/runtime.js` | 跟客戶端相同的三項改動 |
| 網關 `core/admin/static/i18n/en.js` | 新檔 |
| 網關 `core/admin/admin_handler.py` | 靜態檔允許清單加入 `en.js`，否則會回傳 404 |
| 主 repo `kiosk/keyboard.js` | 「空格」「完成」「前往」等按鍵文字改為每次彈出鍵盤時，才按 `document.documentElement.lang` 選取，不在載入時固定 |

**翻譯的邊界：** 網關後端（例如 `pipeline.py` 的檢查結果、`speech_settings.py` 的設定驗證錯誤）和更新器（`thinksmart-update` 的 job 狀態、`check_error`，以及 `Fail(...)` 拋出的錯誤）目前會先把數值填進中文句子，再交給頁面，所以頁面無法翻譯。改法如下：

- **訊息格式：** 這些訊息除了原有的 `message`（保留，以免舊頁面失效），再加上 `msg_key` 和 `msg_params` 兩個欄位：
  - `msg_key` 是帶佔位符的简中範本，例如 `已更新到 {version}`；
  - `msg_params` 是參數，例如 `{"version": "1.0.1"}`。參數值可以是另一個 `{msg_key, msg_params}` 物件，用於句中嵌句的情況，例如回復訊息 `{version} 自检没通过（{why}），已退回 {old}` 裏的 `{why}`。
- **多欄位的物件：** 網關 `pipeline.py` 回傳的流程步驟（`title`、`value`、`hint`）和提示（`title`、`say`、`result`）有多個欄位，其中一些是填了數值的中文句子，例如 `停顿 {silence}ms 算说完`、`缓冲约 … 秒`、思考力度、提示卡的 `title`／`source`／`when`。規則：每個欄位的值可以是普通字串（頁面用 `t()` 翻譯），也可以是 `{msg_key, msg_params}` 物件；頁面用同一個函式處理兩種情況。`pipeline.py` 裏所有填入數值的欄位都改用物件。用戶輸入、模型名稱和提示詞原文不翻譯。
- **頁面：** 用 `t(msg_key)` 取得譯文範本，再填入參數；參數是物件時先遞迴翻譯。沒有 `msg_key` 時才顯示原有的 `message`。
- **自檢的原因：** 回復訊息裏 `{why}` 的來源不是 `Fail`，而是 `self_test` 和 `system_self_test` 回傳的中文字串，也一併改為回傳 `{msg_key, msg_params}`：`SYS_CHECK_WHY` 的各項、`{unit} 没有正常运行`、`没装成功（{why}）` 和回復訊息後面的「请重启设备」都是 key。
- **我們自己寫的錯誤也要帶 key：** 更新器的 `Fail` 改為 `Fail(key, **params)`，網關設定驗證的錯誤同樣帶 key 和參數。`set_job(..., 'failed', ...)` 和 `check_error` 收到 `Fail` 時傳出它的 key 和參數。網關現有以繁中寫成的驗證錯誤，改以简中範本作為 key，繁中放回繁中字典。
- **第三方的例外文字**（不是 `Fail` 也不是我們的驗證錯誤，例如網絡函式庫的錯誤）照原樣顯示，前面接上已翻譯的固定前綴，例如「安裝出錯：」。
- **重新開機提示：** 歡迎頁原本用正規表示式比對更新器的中文訊息來判斷要不要重新開機，改為讀取 `job.reboot`。`set_job` 加上 `reboot` 參數，規則如下：
  - `install_system` 在動作含 `boot` 時，**先**把 `reboot` 寫入 `st['system']`，**然後**才刪除 `SYS_PENDING`，避免中途當掉時遺失；
  - `recover()` 處理未完成安裝時，從該次安裝的動作清單（是否含 `boot`）推算 `reboot`，不讀可能過時的狀態欄位；
  - 同時更新兩者時，系統層成功而客戶端失敗或回復，客戶端那個 job 仍然帶着 `reboot`。
  
  更新器測試涵蓋：只更新系統層、兩者同時更新、系統層成功但客戶端失敗、在寫入紀錄和刪除 `SYS_PENDING` 之間中斷。四種情況都必須有 `job.reboot`。
- **網關的更新進度：** 網關後台的「更新」進度和錯誤，是解析 `scripts/update.sh` 的中文輸出而來。v1 不翻譯這部分：頁面以「更新紀錄」標題照原樣顯示，視為診斷文字，寫入 §10 的已知限制。
- **測試：** 字典完整性測試的原文條目要涵蓋所有 `msg_key`，包括巢狀的 key 和 `Fail` 的 key。字典完整性測試也從 Python 原始碼擷取 `msg_key` 字面值（`Fail`、`self_test`、`system_self_test`、`pipeline.py`）。英文介面另加測試：無效的 ASR 網址、缺少 API key、無效的 MCP 設定、「連不上更新伺服器」、系統層自檢失敗後的回復訊息、網關流程頁裏填了數值的欄位，都必須顯示英文。

### 6.2 首次開機的語言選擇

`thinksmart-kiosk.py` 的 `check_target()` 一發現客戶端可以連上，就會直接載入客戶端網址。歡迎頁本身是 `file://`，無法跟客戶端共用 localStorage。所以語言選擇要由 kiosk 外殼負責：

1. **狀態檔：** `/home/ubuntu/.config/thinksmart-kiosk/lang`。kiosk 以 `ubuntu` 身份運行，可以自行建立這個目錄，不需要 root。
2. **選擇語言：** 歡迎頁經現有的 `window.webkit.messageHandlers.thinksmart` 通道（目前用來設定 WiFi）送出新指令 `set_language`。kiosk 外殼驗證值是 `zh-Hant`、`zh-Hans` 或 `en` 之一，寫入狀態檔（寫入失敗時回報錯誤給歡迎頁，不會靜默略過）。
3. **選擇之後：** 歡迎頁立即以所選語言重新顯示，並保留 WiFi 設定介面。原有的離開條件（客戶端可以連上，而且 `needs_network_setup()` 為否）維持不變，再加上「狀態檔已存在」：三者同時成立時，`check_target()` 和 `reload()` 才會離開歡迎頁。在此之前，歡迎頁一開始就顯示「繁體中文／简体中文／English」三個按鈕。
4. **已在使用中、經線上更新升級的裝置：** 沒有狀態檔，所以下次停在歡迎頁時會顯示一次選語言畫面。點選後就會繼續進入客戶端，不會因此卡住。
5. **傳遞語言：** 外殼載入**預設的**客戶端網址（`127.0.0.1:8090`）時，用 `urllib.parse` 把 `lang=<locale>` 合併進原有的查詢字串。用戶自訂的網址不改動。`page_status()` 也加入 `lang`，讓重新開機後的歡迎頁知道該用甚麼語言。
6. **歡迎頁的翻譯：** 歡迎頁用一份精簡版的 `i18n.js`：只負責翻譯，語言由 kiosk 經 `page_status()` 提供，不讀寫 localStorage，也不自行重新載入。三份字典沿用。由 JavaScript 動態寫入的文字，例如狀態文字和 WiFi 介面，全部經過 `t()`；日期改用 `Intl.DateTimeFormat(locale)` 顯示。`<html lang>` 跟隨所選語言，`keyboard.js` 也按它選擇按鍵文字。
7. 新的 kiosk 檔案（`i18n.js`、三份字典）都要加入 `image/system-files.txt`，否則系統層更新不會安裝它們。

**單一資料來源：** 在裝置上，kiosk 的狀態檔是唯一的權威來源。

- 客戶端設定頁的語言選單也經同一個 `set_language` 通道寫入狀態檔。kiosk 外殼原本只接受本機客戶端頁面送來的 WiFi 指令，所以要把 `set_language` 加入允許的指令集，並更新測試這個指令集的現有測試。
- 切換語言後，客戶端以新的 `?lang` 重新載入，不能沿用網址裏舊的 `?lang`。
- 因為 kiosk 每次載入客戶端都會附上 `?lang`，所以 `?lang` 的優先次序必須高於 localStorage 裏已記住的值。這改變了 #4 測試裏「已記住的值優先」和「無效的 `lang` 回到简中」兩項預期。這兩項測試要按新規則改寫：`?lang` → 已記住的值 → 瀏覽器語言；無效的 `?lang` 直接忽略。
- 歡迎頁不使用 localStorage。

網關後台在電腦上開啟，沒有 kiosk，按「已記住的值 → 瀏覽器語言」決定。

### 6.3 其他

- **說話語言：** #9 已支援 `zh-Hant`、`zh-Hans`、`yue-HK`、`en`、`ja`、`ko`、`es`、`fr`，這次不改。
- **字串拼接：** 只把影響英文詞序的地方改成範本字串。
- **翻譯：** 英文字典由 Claude 起草，維護者審閱；繁中沿用 #4 和 #9。
- **喚醒詞規則：** 在 `en.js` 裏，所有含「小麦」的條目都必須逐字保留中文喚醒詞，可以在後面加拼音說明。這條規則由測試強制。

### 6.4 測試

- **字典完整性：** 客戶端（擴充 `tests/test_i18n.cjs`）、網關、kiosk 歡迎頁各有一個測試。原文條目同時從 HTML 標記和程式碼裏的 `t('…')` 呼叫擷取。每份字典的條目必須跟原文完全一致，並檢查喚醒詞規則。
- **語言判斷：** 測試 `?lang=en`、已記住的 `en`、英文瀏覽器、無效的語言值。
- **kiosk 外殼：** 擴充 `kiosk/test_kiosk_commands.py`，測試 `set_language` 的驗證、未選語言時留在歡迎頁、`load_uri` 有附加 `?lang`。

## 7. 刷機教學和 bootstrap 的修正

### 7.1 教學檔案

保留上游的檔案結構，減少合併衝突：

- `README.md`：简中，修改原檔；
- `README.en.md`：英文，修改原檔；
- `README.zh-Hant.md`：繁中，新增。

三份互相連結。主要改動有四項：映像和 bootstrap 準備步驟、首次設定（改密碼、設時區）、ohimsmart 網址，以及 §7.3 的連線方式。

新增 `tools/check-readmes.sh`，比對三份教學裏的指令區塊和網址是否一致，有任何不一致就報錯。

### 7.2 問題

維護者在 2026-11-09 刷機時，bootstrap 開機後，電腦（omarchy，Linux）認不到它的 USB 網絡。改用裝置鍵盤執行 `nmtui` 也失敗，因為 bootstrap 映像的 `/etc/machine-id` 是空的，D-Bus 和 NetworkManager 都起不來。結果卡了約 16 分鐘。

### 7.3 修正：`bootstrap/prepare.sh`

自己寫一個小腳本，不包裝 rickx 的腳本。rickx 的腳本只接受以命令列參數傳入 WiFi 和登入密碼，會讓密碼出現在處理程序清單裏；它還需要 `losetup`、`sudo` 和多個輔助檔案。

**做法：**

- **可選用：** 只用 USB 的用戶可以照上游直接刷未改動的 bootstrap 映像，不必執行 `prepare.sh`。
- 在一般權限的 Docker 容器裏執行（不用 `--privileged`），容器映像要包含 e2fsprogs 和 openssl。以 `--user $(id -u):$(id -g)` 執行並設定 `umask 077`：輸出檔建立在權限 700 的暫存目錄裏、權限 600，失敗或中斷時由 `trap` 刪除未完成的檔案。教學 §0.2 的事前準備加入 Docker。
- **改寫方式：** 不用 loop 裝置。用 `sfdisk -d` 讀出 bootstrap 映像的分區表（Alpine 容器裏沒有 JSON 解析工具），找出卷名是 `pmOS_root`、有 `extent` 功能的根分區的位元組偏移；找不到就拒絕執行。只接受 `/etc/machine-id` 是空的映像，也就是未改動的上游映像：在改過的映像上，`debugfs` 釋放舊 WiFi 檔案時不會清除內容，舊密碼會留在空閒空間裏。以 `debugfs -w` 改寫：每個檔案先 `rm` 再 `write`，再用 `set_inode_field` 設定 mode、uid 0、gid 0，最後讀回內容比對。`debugfs` 遇到單一指令錯誤時通常仍以 0 結束，所以每一步都以讀回結果判斷成敗，不看結束碼。
- 只做四件事：
  1. 寫入新的 32 位十六進位 `machine-id`。
  2. 互動讀取 WiFi 名稱和密碼，保留反斜線和前後空格（所以都用 `IFS=` 和 `-r`）：WiFi 名稱用 `IFS= read -r`，輸入時顯示；在終端機上密碼用 `IFS= read -rsp`，`-p` 讓 bash 在關掉回顯之後才印出問題，馬上打字也不會顯示；從管道讀入時密碼用 `IFS= read -r`。WiFi 名稱一律寫成十進位位元組清單（`ssid=` 後面以 `;` 分隔的數字），密碼按 NetworkManager keyfile 的規則跳脫（反斜線加倍、開頭的空格寫成 `\s`）。寫成 `wlan0` 的 `.nmconnection`，擁有者 `0:0`、權限 600、`autoconnect=true`。密碼不經命令列參數傳遞。WiFi 名稱留空就略過 WiFi，只用 USB；密碼留空表示開放網絡（`key-mgmt` 不設定）。
  3. 互動讀取 bootstrap 登入密碼，不設預設值，要求至少 8 個字元，並拒絕 `thinksmart`。用 `openssl passwd -6 -stdin` 產生雜湊，只套用到 `pmos`，並鎖定 `root`。
  4. 清除映像裏的 SSH 主機金鑰。映像的 sshd 服務每次啟動會自己產生缺少的金鑰，`prepare-image.sh` 確認這一點，不另加開機腳本。
- 不啟用 rickx 的自動改分區服務。

**改好的映像同時支援 USB 和 WiFi**，USB 網絡設定原封不動。所以這是**額外加上**的連線方式，不是取代 USB。教學的 A5 改為：

1. 先等 USB 網絡（`172.16.42.1`），跟上游一樣。
2. 兩分鐘內沒有出現，而且 A4 用了 `prepare.sh` 並填了 WiFi 的話（沒改過的映像沒有 WiFi 設定），改用 WiFi：在路由器的裝置列表找主機名稱 `thinksmarter`，或用 `nmap -p 22 --open <你的網段>` 掃描。bootstrap 階段只開放 port 22，所以「給 AI 助手的說明」那一節也要改為只掃 port 22；port 16688 留到刷完 Ubuntu 之後才用。
3. 兩者都失敗時，接上 USB 鍵盤，在裝置上以 `pmos` 登入。沒用 `prepare.sh` 的話，連 WiFi 之前先改密碼、鎖定 root：上游映像的 `pmos` 和 `root` 密碼都是公開的 `thinksmart`，sshd 也允許 root 用密碼登入。

   ```sh
   passwd
   doas passwd -l root
   doas grep '^root:!' /etc/shadow
   ```

   最後一行要印出以 `root:!` 開頭的一行，否則停下，不連 WiFi。然後執行以下手動修正：

   ```sh
   doas sh -c 'dbus-uuidgen > /etc/machine-id'
   doas rc-service dbus start
   doas rc-service networkmanager start
   doas nmtui
   ```

**教學必須提醒用戶：**

- bootstrap 階段的 SSH 會開放在區域網絡上，直到刷入 Ubuntu 為止，所以登入密碼不能用預設值；
- 完成後刪除改好的 bootstrap 副本，因為它含有 WiFi 密碼和登入密碼的雜湊。

**狀態標示：** 路線 A 和 WiFi 連線方式在教學裏標示為「實驗性：未經 Oh I'm Smart 在原廠裝置上實測」，直到有原廠裝置跑完整個流程才移除這個標示。v1 驗收不包括路線 A（§1、§9）。

### 7.4 驗證

`prepare.sh` 的自動測試在 UM 上對真實的 bootstrap 映像執行，檢查以下各項：

- `machine-id` 是 32 位十六進位；
- `.nmconnection` 存在、擁有者 `0:0`、權限 600；解析後 `interface-name=wlan0`、`autoconnect=true`，`ssid`、`key-mgmt`、`psk` 跟輸入相同。以一個含空格、反斜線和 `;` 的 WiFi 名稱做來回測試；WiFi 名稱留空時不產生 `.nmconnection`；
- `root` 已鎖定。從 `pmos` 的雜湊取出 salt：用同一個 salt 對測試密碼執行 `openssl passwd -6 -salt <salt>`，結果必須完全相同；對 `thinksmart` 執行則必須不同。`prepare.sh` 輸入空白或 `thinksmart` 時必須拒絕；
- 主機上的輸出檔權限是 600，中斷執行後不留下未完成的檔案；
- SSH 主機金鑰已清除；
- 沒有自動改分區服務的連結；
- 以一個測試用密碼執行時，處理程序清單和日誌都不會出現它。

macOS Docker Desktop 上至少要跑一次相同的檢查。Windows 標示為未實測。一個 WiFi 名稱留空的映像也在 macOS 上跑過（4b 計劃 Task 2）。

## 8. 安全

- 更新沒有簽名，而且以 root 身份安裝。誰控制了 `oh-im-smart-client` 的 Release，誰就能控制所有裝置；tag 保護也無法限制發佈者本人更改 `releases/latest`。上游作者在 2026-11-01 明確決定不簽名。
- **v1 的保護措施：**
  - 負責發佈的帳號（`chris-yyau`）必須已開啟雙重驗證，在發佈第一個映像前確認；
  - organization 強制成員啟用雙重驗證：維護者決定暫緩，有第二位成員加入之前必須開啟；
  - release tag 和主分支受保護。
- **之後：** 加入更新簽名，屬探索項目。
- **映像**只帶文件寫明的預設帳號密碼（`ubuntu`／`thinksmart`，首次設定時必須修改），`root` 鎖定，不帶任何維護者的資料（§5.4）。**bootstrap 副本**帶有用戶自己的 WiFi 密碼和登入密碼雜湊，只存在於用戶的電腦上，用完就刪除（§7.3）。兩者都不帶維護者的資料。

## 9. 測試和驗收

| 層面 | 測試 |
|---|---|
| 現有測試 | 三個 repo 原有的測試必須全部通過。唯一例外是 §6.2 按新的語言優先次序明確改寫的測試 |
| 翻譯 | §6.4 |
| bootstrap | §7.4 |
| 教學 | `tools/check-readmes.sh` |
| 映像打包 | §5.3 的上游網址檢查和必填的 `SECRETS_FILE`；§5.4 的帳號、shell 啟動檔和 shadow 檢查；§5.5 的 `NTP=` 一行 |
| 線上更新回復 | 在本機架設測試來源（`SOURCES=http://127.0.0.1:<port>/`，上游允許的測試用法），提供一個版本號較高、但自檢會失敗的系統層。確認工作狀態變為回復、系統層的備份已還原。客戶端的回復由上游自身的測試覆蓋。更新器會記住看過最新的 manifest 發佈時間，所以這個測試必須在正式 Release 產生**之前**進行，或在測試後清除更新器的狀態，否則正式 manifest 會因為「比較舊」而被拒絕 |
| 第一個版本的升級路徑 | 「上一版」定義為上游版本：母機從上游版本經線上更新升級到 Oh I'm Smart 1.0.0，見 §5.6 |

**驗收（v1 完成的標準）：** 維護者的裝置先備份，再用路線 B 跟着**繁中教學**重刷 Oh I'm Smart 映像，然後逐項確認：

1. 開機出現三語選擇；選 English 後，歡迎頁、客戶端和螢幕鍵盤都是英文；重新開機後仍然是英文。
2. 網關後台在英文瀏覽器上以英文顯示。
3. ASR 和 TTS 分別用不同的 API key 和網址儲存。
4. 說話語言切換為 `yue-HK`，進行一輪對話；再切換為 `en`，再進行一輪。
5. 在英文後台新增一個 MCP server，顯示正常。
6. 後台檢查更新時顯示「已是最新」，而且 `/etc/thinksmart-update.conf` 的來源和網關的 remote 都指向 `ohimsmart`。
7. `ubuntu` 用預設密碼登入後可以修改密碼；`root` 是鎖定狀態；時區可以用 `timedatectl` 設定。

## 10. 風險和已知限制

- **路線 A 和 bootstrap WiFi 未經實機驗證。** v1 標示為實驗性，驗收不包括它們；`prepare.sh` 可選用，USB 方式維持不變。
- **網關後台的更新紀錄不翻譯**（§6.1），以診斷文字照原樣顯示。
- **x86 模擬：** 第一次打包後要在實機驗證，必要時用 Mac mini。
- **上游衝突：** #4 和 #9 的改動跟上游 0.1.6 可能有衝突。修改 README 和 kiosk 等上游檔案，也會增加日後合併的衝突。
- **喚醒詞只有中文。**
- **刷完 Ubuntu 後不能用 USB 登入**（上游已知問題）。
- **時區要手動設定**，直到後台加入一鍵設定。
- **映像裏的 `ubuntu` 帳號用已知的預設密碼**，跟上游相同。教學要求首次設定時修改。

## 11. v1 之後

1. v1.1：外掛框架，連同遠端 agent harness 的 MCP server，經 Tailscale 連接。
2. Hindsight 記憶。經 MCP 接入，放在大主機上，不放在裝置上。
3. 用 GitHub Actions 自動打包。
4. 更新簽名。
5. 從網關後台一鍵設定時區。
