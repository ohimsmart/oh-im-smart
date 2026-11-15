# Oh I'm Smart：ThinkSmart View 語音終端

[简体中文](README.md) | 繁體中文 | [English](README.en.md)

把聯想 **ThinkSmart View（型號 CD-18781Y）** 刷成一臺本地語音助手：開機直接進語音介面，說「小麥小麥」喚醒，背後可以接 Claude、DeepSeek 等多種大模型。

Oh I'm Smart 是 [justhalfbit/thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image) 的延伸版本。映像基於 [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart)（Ubuntu 24.04 + postmarketOS 核心 6.19），去掉了 Plasma 桌面，預裝：

- 語音客戶端 [ohimsmart/oh-im-smart-client](https://github.com/ohimsmart/oh-im-smart-client)（出自 [justhalfbit/xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client)）：喚醒、對話介面、睡眠時段、亮度、線上更新；
- 小智閘道器 [ohimsmart/oh-im-smart-gateway](https://github.com/ohimsmart/oh-im-smart-gateway)（出自 [justhalfbit/xiaozhi-hub-server](https://github.com/justhalfbit/xiaozhi-hub-server)）：本機語音識別，接各家大模型和語音合成，帶網頁管理後臺；
- 裝置修復：兩顆麥克風、揚聲器、螢幕熄屏和接近喚醒、WiFi 穩定性、GPU 白屏/卡死補丁等。

介面有繁體中文、簡體中文和英文，首次開機時選擇；喚醒詞「小麥小麥」只有中文。

> ⚠️ 刷機會清掉原來的 Teams / Android 系統。第一次刷之前**一定先整盤備份 eMMC**（[A2](#a2-整盤備份原廠-emmc必做)），這是以後回到原廠的唯一辦法。

第一個 Oh I'm Smart 映像還在準備中，Releases 頁面暫時是空的；發布後這句會刪掉。

本文就是完整的刷機教程，寫成了人和 AI 助手都能照著一步步做的樣子。

---

## 目錄

- [給 AI 助手的說明（先讀這一節）](#給-ai-助手的說明先讀這一節)
- [0. 準備](#0-準備)
- [1. 進入 EDL 模式，判斷走哪條路線](#1-進入-edl-模式判斷走哪條路線)
- [路線 A：第一次刷（裝置還是原廠系統）](#路線-a第一次刷裝置還是原廠系統)
- [路線 B：已經刷過本映像或上游 Ubuntu 映像](#路線-b已經刷過本映像或上游-ubuntu-映像)
- [2. 首次開機和設定](#2-首次開機和設定)
- [3. 常見問題排查](#3-常見問題排查)
- [4. 備份和還原使用者資料](#4-備份和還原使用者資料)
- [5. 以後的更新](#5-以後的更新)
- [附錄：分割區和映像結構](#附錄分割區和映像結構)
- [致謝和宣告](#致謝和宣告)

---

## 給 AI 助手的說明（先讀這一節）

如果你是被使用者叫來幫忙刷機的 AI 助手（Agent），請先讀完這一節，再從第 0 步開始。

### 目標

把本倉庫 Release 裡的映像寫進使用者這臺 ThinkSmart View 的 `system` 分割區，讓它開機進入語音助手介面，然後陪使用者完成首次設定（介面語言、WiFi、閘道器管理員密碼、API Key、改預設密碼、時區）。

### 整體流程

```
第 0 步  準備：確認型號 → 裝 edl → 下載並校驗檔案
第 1 步  進 EDL 模式 → edl printgpt → 按 system 分割區大小選路線
  路線 A（原廠系統）：整盤備份 → 刷 lk2nd 到 boot →（可選）用 prepare.sh 準備 bootstrap
                      → 刷 bootstrap 到 system → 開機 → SSH 進 bootstrap 改分割區表
                      → 關機 → 再進 EDL → 刷本映像到 system
  路線 B（刷過 Ubuntu）：（可選）備份使用者資料 → 進 EDL → 刷本映像到 system
第 2 步  首次開機：選介面語言 → 螢幕配 WiFi → 找 IP → 閘道器後臺設密碼、填 API Key
         → 改 ubuntu 的密碼、設時區 → 試語音
```

### 必須先停下來、得到使用者明確同意才能做的操作

下面每一項都不可逆，或者會清掉資料。執行前把**要執行的完整命令**和**後果**告訴使用者，等使用者明確回答「同意 / 可以 / 執行」之類的話再做。一次同意只管這一步，下一步要重新問。

| 步驟 | 操作 | 後果 |
| --- | --- | --- |
| A2 | 整盤備份時，目標檔案已經存在 | 覆蓋舊備份，舊備份就沒了。預設換個檔名，不要覆蓋 |
| A3 | `edl w boot lk2nd.img` | 原廠 bootloader 鏈被換成 lk2nd，Android/Teams 從此起不來 |
| A4 | `edl w system <bootstrap 映像>`（下載的或 `prepare.sh` 改好的） | 原廠 `system` 分割區被覆蓋 |
| A6 | 在 bootstrap 裡執行 `apply-ubuntu-gpt.sh` | 改寫整張分割區表，原廠的 vendor、cache、userdata 等分割區被刪掉 |
| A8 / B3 | `edl w system thinksmart-ubuntu-…img` | `system` 分割區原有內容全部被覆蓋（包括舊系統裡的聊天記錄、API Key、WiFi 配置） |
| — | 任何 `edl wf`（整盤寫回） | 整個 eMMC 被覆蓋。只有使用者明確要求回原廠時才用 |

另外兩種情況也要停下來問：

- 任何一步的輸出和本文寫的「期望輸出」對不上；
- 同一條寫入命令失敗了一次。可以說明情況後建議重試一次，再失敗就停下來，別反覆重試。

### 需要使用者本人動手的操作

AI 助手做不了這些，到這一步要明確告訴使用者做什麼，等使用者說「好了」再繼續：

- 插拔 USB 線和電源線、換線、換電腦上的 USB 口；
- 按鍵組合進 EDL 模式（拔電源線 → 插 USB 線 → 按住音量 + 和音量 − → 插電源線 → 3～5 秒後鬆開音量鍵，見 1.1）；
- 關機和開機：這臺裝置**沒有電源鍵**，插上電源線就開機。系統開著時要先關機再拔電：在語音介面的設定頁最底下點「關機」，或者 SSH 執行 `sudo systemctl halt`，螢幕變黑後等 10 秒再拔（黑屏後系統還要幾秒才收尾）。拔掉後要等 30 秒左右再插上才會開機，馬上插回去可能開不了機。不要用 `sudo poweroff`：插著電時它會馬上重新開機。關不了機（比如停在緊急模式、lk2nd 介面）才直接拔；
- 看裝置螢幕，告訴你上面顯示什麼（黑屏、lk2nd 介面、歡迎頁、語音介面……）；
- 首次開機在螢幕上選介面語言；
- 在裝置觸控式螢幕上選 WiFi、輸入 WiFi 密碼；
- 回答 `prepare.sh` 的問題（WiFi 名稱、WiFi 密碼、bootstrap 的登入密碼）；
- 在瀏覽器裡開啟閘道器管理後臺，設定管理員密碼、填 API Key；
- 對著裝置說「小麥小麥」，確認語音能用；
- macOS 彈出「允許配件連線？」時點「允許」，Windows 彈出 UAC 時點「是」。

### 絕對不能自作主張做的事

- 不能用 `edl w` 寫 `boot`、`system` 以外的任何分割區；不能用 `edl e`（擦除）、`edl wl`、`edl qfp` 等批次寫入命令。
- 不能用 fastboot 刷寫或擦除：`fastboot flash`、`fastboot erase`、`fastboot oem unlock` 都不要用。這臺機器的 bootloader 是鎖的，fastboot 寫不進去，亂試只會出問題。
- 不能在已經改過分割區表的裝置上再執行 `apply-ubuntu-gpt.sh`，也不能自己對 `/dev/mmcblk0` 執行 `sfdisk`、`dd`、`parted`。
- 不能刪除、移動、覆蓋原廠整盤備份 `stock-full-emmc.bin`，也不能把它上傳到任何地方。裡面有這臺裝置獨有的資料（序列號、校準資料、原廠系統裡的帳號資訊）。
- 不能把使用者的 WiFi 密碼、API Key、裝置密碼寫進日誌、提交到倉庫，或發給任何第三方服務。
- 不能替使用者回答 `prepare.sh` 的問題，不能把 WiFi 密碼或登入密碼寫進命令、檔案或記錄。`prepare.sh` 改好的 bootstrap 副本用完（A8 之後）就刪掉。
- 不能修改下載來的映像檔案。校驗和對不上就重新下載。
- 寫入過程中不要叫使用者拔線或斷電。

### 執行約定

- 每一步先執行「命令」，再對照「期望輸出」和「怎麼判斷成功」。對上了才進下一步；對不上就看「失敗了怎麼辦」，還解決不了就停下來問使用者。
- 把每條 `edl` 命令的完整輸出儲存下來（`2>&1 | tee 日誌檔案`），出問題時給使用者看。
- 裝置的 IP **自己找，不要問使用者**：先從本機 IP 算出網段，再分兩個階段掃區域網。bootstrap 階段（A5）只開 22 埠，用 `nmap -p 22 --open <網段，比如 192.168.1.0/24>`，主機名是 `thinksmarter`；刷入本映像之後用 `nmap -p 22,16688 --open <網段>`，再開啟 `http://<IP>:16688/admin` 確認標題是「小智 Hub 管理後臺」。具體命令和沒有 nmap 時的辦法見[2.3](#23-找到裝置的-ip)。
- 本文的命令預設在 macOS / Linux 的終端裡執行。Windows 用 PowerShell，按 [0.2 Windows](#windows-1011未實測) 設好 `edl` 之後，`edl` 命令照抄；其他命令換成下表的寫法：

  | macOS / Linux | Windows PowerShell |
  | --- | --- |
  | `shasum -a 256 檔案` | `Get-FileHash 檔案 -Algorithm SHA256` |
  | `ls -l 檔案` | `(Get-Item 檔案).Length` |
  | `grep 內容 檔案` | `Select-String 內容 檔案` |
  | `python3` | `python` |
  | `ping -c 3 地址` | `ping -n 3 地址` |
  | `xz -dk 檔案.xz` | 用 7-Zip 解壓 |
  | `… 2>&1 \| tee 日誌` | 照抄（PowerShell 裡 `tee` 就是 `Tee-Object`） |

- Windows 部分本專案**沒有實測**，是按 edl 和上游的資料寫的，標著「Windows 未實測」。遇到對不上的情況，最省事的辦法是換一臺 macOS 或 Linux 電腦來刷。
- 使用者已經刷過本映像，只是想升級？直接看[路線 B](#路線-b已經刷過本映像或上游-ubuntu-映像)，但仍要先做第 0、1 步。

---

## 0. 準備

### 0.1 確認裝置型號

只支援 **Lenovo ThinkSmart View CD-18781Y**：8 英寸豎屏，高通 APQ8053，2 GB 記憶體，8 GB eMMC。

- 看裝置背面或底部的標籤，型號寫的是 **CD-18781Y**。
- 進 EDL 後（第 1 步）`edl printgpt` 的輸出裡會有 `CPU detected: "APQ8053"` 和 `total_blocks:15269888`，這兩項對不上就**不是這臺機器，停止**。
- 型號不是 CD-18781Y 的機器（包括 ThinkSmart View Plus）沒有測過，不要刷。

### 0.2 電腦和工具

需要：

- 一臺 macOS、Linux 或 Windows 電腦，**剩餘空間 20 GB 以上**（原廠整盤備份約 7.3 GB，bootstrap 映像約 1 GB，用 `prepare.sh` 的話改好的副本再約 1 GB，本映像壓縮包約 0.7 GB、解壓後約 3.5 GB）；
- 一根**能傳資料**的 USB 線（裝置端是 USB-C）。最好直接插電腦本體的口，別經過擴充套件塢或 USB Hub；
- [bkerler/edl](https://github.com/bkerler/edl)：高通 EDL 刷機工具，下面按系統給安裝命令；
- 解壓 `.xz` 的工具和 SSH 客戶端（macOS、Linux、Windows 10/11 都自帶 SSH）。

#### macOS

```bash
brew install libusb xz git
python3 -m venv ~/edl-venv
source ~/edl-venv/bin/activate
git clone https://github.com/bkerler/edl.git ~/edl-src
cd ~/edl-src && git submodule update --init --recursive
pip install .
```

以後每開一個新終端，先執行 `source ~/edl-venv/bin/activate`，`edl` 命令才可用。

`pip install .` 如果在最新版 Python 上報錯，改用 Python 3.12：`brew install python@3.12`，把上面的 `python3 -m venv` 換成 `python3.12 -m venv`，重新做一遍。

#### Linux（Debian / Ubuntu）

```bash
sudo apt install git xz-utils python3-venv python3-dev liblzma-dev libusb-1.0-0
sudo systemctl disable --now ModemManager    # ModemManager 會搶佔 EDL 裝置
git clone https://github.com/bkerler/edl.git ~/edl-src
cd ~/edl-src && git submodule update --init --recursive
sudo bash ./install-linux-edl-drivers.sh     # 裝 udev 規則，普通使用者也能訪問 EDL 裝置
python3 -m venv ~/edl-venv
source ~/edl-venv/bin/activate
pip install .
```

裝完 udev 規則後拔插一次 USB 線。仍然提示沒權限的話，在 `edl` 前面加 `sudo`，並寫成 venv 裡的完整路徑：`sudo ~/edl-venv/bin/edl …`。

#### Windows 10/11（未實測）

上游作者就是在 Windows 上刷的（上游 FLASHING.md 的命令是 PowerShell 寫法）。本專案沒有在 Windows 上實測，下面是按 edl 原始碼和資料整理的做法。

不建議直接用 edl 自帶的一鍵腳本 `install_edl_win10_win11.ps1`。它裝的是 Python 3.9，而 edl 要求 3.10 以上；它放進 PATH 的 `edl.bat` 呼叫的檔案在 edl 3.62 裡已經不存在，直接敲 `edl` 會報找不到檔案。改用下面的手動步驟，在 PowerShell（不是 CMD）裡執行：

```powershell
winget install -e --id Python.Python.3.12
winget install -e --id Git.Git
winget install -e --id akeo.ie.Zadig
winget install -e --id 7zip.7zip
```

裝完關掉 PowerShell 再重新開啟，然後：

```powershell
git clone https://github.com/bkerler/edl.git $env:USERPROFILE\edl-src
cd $env:USERPROFILE\edl-src
git submodule update --init --recursive
py -3.12 -m venv $env:USERPROFILE\edl-venv
& $env:USERPROFILE\edl-venv\Scripts\python.exe -m pip install -r requirements.txt
```

以後每開一個新的 PowerShell，先執行下面兩行。之後本文裡的 `edl …` 命令就能照抄：

```powershell
& $env:USERPROFILE\edl-venv\Scripts\Activate.ps1
function edl { python "$env:USERPROFILE\edl-src\edl.py" @args }
```

`Activate.ps1` 報「禁止執行腳本」的話，先執行 `Set-ExecutionPolicy -Scope Process Bypass`（只對當前視窗有效）。

USB 驅動：第一次進 EDL 後（第 1.1 步）要用 Zadig 給裝置裝 WinUSB 驅動，edl 才能訪問它。edl 自帶了 Windows 版的 libusb 庫，不用另外裝。

為什麼不用 WSL：WSL2 預設看不到 USB 裝置，要另裝 usbipd-win 轉接；EDL 裝置在刷寫過程中會重新連線，轉接容易斷。edl 直接在 Windows 上跑更穩。

#### 檢查 edl 裝好了

```bash
edl --help
```

期望輸出開頭有 `Qualcomm Sahara / Firehose Client`，後面是一長串用法說明。提示找不到 `edl`：macOS / Linux 先執行 `source ~/edl-venv/bin/activate`；Windows 先執行上面「每開一個新的 PowerShell」那兩行。

#### Docker（只有 A4 想用 `prepare.sh` 時才需要）

`prepare.sh` 在 Docker 容器裡改 bootstrap 映像，所以要裝 Docker。只用 USB 線連 bootstrap 的話不用裝。

- macOS：裝 Docker Desktop，第一次開啟時同意授權條款，等它顯示正在執行：

  ```bash
  brew install --cask docker-desktop
  ```

- Linux：裝 Docker Engine，把自己加進 `docker` 組，然後登出再登入：

  ```bash
  sudo apt install docker.io
  sudo usermod -aG docker $USER
  ```

- Windows：未實測。

裝好後 `docker info` 不報錯就可以了。

### 0.3 下載檔案

建一個工作目錄，比如 `~/thinksmart`，把下面的檔案都放進去。後面的命令都在這個目錄裡執行。

| 檔案 | 從哪下載 | 什麼時候用 |
| --- | --- | --- |
| `thinksmart-ubuntu-<日期>.img.xz`、`SHA256SUMS` | 本倉庫 [Releases](https://github.com/ohimsmart/oh-im-smart/releases) 最新版 | 兩條路線都要 |
| `lk2nd.img` | 上游倉庫 [prebuilt/lk2nd.img](https://github.com/rickx/ubuntu-thinksmart/raw/main/prebuilt/lk2nd.img) | 只有路線 A |
| `bootstrap-pmos-ssh-generic-qcom-msm8953.img` 和同名 `.sha256` | 上游 Release [bootstrap-2026-05-22](https://github.com/rickx/ubuntu-thinksmart/releases/tag/bootstrap-2026-05-22) | 只有路線 A |

不用另外下載上游的分割區表檔案：bootstrap 映像裡已經帶了改分割區表的腳本 `/usr/local/sbin/apply-ubuntu-gpt.sh` 和佈局檔案。

```bash
mkdir -p ~/thinksmart && cd ~/thinksmart
curl -L -O https://github.com/rickx/ubuntu-thinksmart/raw/main/prebuilt/lk2nd.img
curl -L -O https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/bootstrap-pmos-ssh-generic-qcom-msm8953.img
curl -L -O https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/bootstrap-pmos-ssh-generic-qcom-msm8953.img.sha256
# 本映像：到 Releases 頁面複製最新版兩個檔案的下載地址，同樣用 curl -L -O 下載
```

Windows PowerShell 裡把 `curl` 寫成 `curl.exe`，其餘照抄。GitHub 在國內打不開或很慢時，給 curl 加代理引數 `-x http://<代理地址>:<埠>`，或者用瀏覽器下載後放進這個目錄。

### 0.4 校驗檔案

```bash
cd ~/thinksmart
shasum -a 256 -c --ignore-missing SHA256SUMS          # Linux 也可以用 sha256sum
shasum -a 256 bootstrap-pmos-ssh-generic-qcom-msm8953.img lk2nd.img
cat bootstrap-pmos-ssh-generic-qcom-msm8953.img.sha256
```

期望輸出：

- 第一條列印 `thinksmart-ubuntu-<日期>.img.xz: OK`；
- bootstrap 映像的 SHA256 和 `.sha256` 檔案裡的值一樣：`7d79db19b0911647bf6ab0a9a2924ef5cf83b4674798a54acdcbd41cdf07921b`；
- `lk2nd.img` 的 SHA256 是 `c81b036c75028c3d5aa915c72c89e075bc044360fe964c2ec0afb1d4a6f5209b`。這是寫這份教程時上游的版本，上游以後更新了 lk2nd，以上游為準。

Windows 用 `Get-FileHash .\檔名 -Algorithm SHA256` 逐個算，和上面的值對比。

任何一個對不上：重新下載那個檔案，別用。

### 0.5 解壓本映像

```bash
xz -dk thinksmart-ubuntu-<日期>.img.xz
shasum -a 256 -c --ignore-missing SHA256SUMS
```

期望輸出：`.img.xz: OK` 和 `.img: OK` 兩行。解壓後的 `.img` 約 3.5 GB，每個版本的大小寫在 Release 說明裡。Windows 用 7-Zip 解壓，再用 `Get-FileHash` 和 `SHA256SUMS` 裡 `.img` 那一行對比。

`.img` 是整個 `system` 分割區的內容，裡面有啟動分割區和根分割區兩個小分割區。首次開機會自動把根分割區擴滿整個 `system` 分割區。

---

## 1. 進入 EDL 模式，判斷走哪條路線

### 1.1 進 EDL（使用者動手）

這臺裝置沒有電源鍵，插上電源就開機，拔掉電源就斷電。

1. 拔掉電源線。系統開著的話先關機（設定頁「關機」或 `sudo systemctl halt`），螢幕全黑後等 10 秒再拔。USB 線如果插著，也先拔掉。拔掉後等 30 秒再做下面幾步，剛關機馬上插電可能不通電，進不了 EDL。
2. 用 USB 線把裝置連到電腦。
3. **同時按住音量 + 和音量 −** 不放。
4. 按著不放，插上電源線。
5. 3～5 秒後鬆開音量鍵。

**螢幕保持黑屏是正常的**，EDL 模式沒有任何顯示。

檢查電腦認到了裝置：

- macOS：`ioreg -p IOUSB | grep -i -E "qhsusb|qusb|9008"`，期望看到 `QUSB__BULK` 或 `QHSUSB__BULK`。Apple Silicon 的 Mac 彈出「允許配件連線？」要點「允許」。
- Linux：`lsusb | grep -i 9008`，期望看到 `Qualcomm ... (QDL mode)` 或 `05c6:9008`。
- Windows（未實測）：裝置管理器裡出現 `QUSB__BULK`（多半帶黃色感嘆號）或 `Qualcomm HS-USB QDLoader 9008`。**第一次**要裝 WinUSB 驅動：開啟 Zadig → 選單 Options 勾選 List All Devices → 下拉框選 `QUSB__BULK`（USB ID 是 `05C6 9008`）→ 右邊驅動選 `WinUSB` → 點 Install Driver（已裝過別的驅動時按鈕叫 Replace Driver）。裝一次以後就不用再裝。

看不到：按[3.1 edl 找不到裝置](#31-edl-找不到裝置或者連上後馬上斷開)處理。

### 1.2 讀分割區表

```bash
cd ~/thinksmart
edl printgpt 2>&1 | tee gpt-before.txt
```

期望輸出（節選）：

```
main - Device detected :)
...
CPU detected:      "APQ8053"
...
firehose - TargetName=MSM8953
firehose - total_blocks:15269888
...
boot:                Offset 0x0000000018200000, Length 0x0000000002000000, ...
system:              Offset 0x000000001c300000, Length 0x…, ...
```

怎麼判斷成功：有 `Device detected :)`，並且列印出了分割區列表。`CPU detected` 不是 `APQ8053` 或 `total_blocks` 不是 `15269888`：**停止，這不是支援的裝置**。

### 1.3 選路線

看 `system:` 那一行的 `Length`：

| `system` 的 Length | 有沒有 `userdata:` 一行 | 說明 | 走哪條路線 |
| --- | --- | --- | --- |
| `0x0000000060000000`（1.5 GB） | 有 | 原廠分割區表 | [路線 A](#路線-a第一次刷裝置還是原廠系統) |
| `0x00000001b3cfbe00`（約 6.8 GB） | 沒有 | 已經改成 Ubuntu 分割區表 | [路線 B](#路線-b已經刷過本映像或上游-ubuntu-映像) |
| 其他值 | — | 不認識的分割區表 | **停止**，把輸出給使用者看，不要繼續 |

---

## 路線 A：第一次刷（裝置還是原廠系統）

> 實驗性：未經 Oh I'm Smart 在原廠裝置上實測。路線 A 照上游的做法寫成，Oh I'm Smart 的維護者還沒有在一臺原廠系統的裝置上從頭走過一遍。

順序和上游完全一致：

```
整盤備份 → 刷 lk2nd 到 boot → 刷 bootstrap 到 system → 開機進 bootstrap
→ SSH 進去改分割區表 → 關機 → 再進 EDL → 刷本映像到 system
```

為什麼要繞一圈：原廠 `system` 分割區只有 1.5 GB，裝不下 Ubuntu。要先刷一個臨時的小系統（bootstrap，postmarketOS），在裝置上把分割區表改成 `system` 約 6.8 GB 的佈局，再刷正式映像。

### A1. 進 EDL

同[1.1](#11-進-edl使用者動手)。如果剛做完第 1 步、裝置還連著、中間沒拔線，可以直接繼續。

### A2. 整盤備份原廠 eMMC（必做）

這是以後回到原廠系統的**唯一辦法**。

```bash
cd ~/thinksmart
ls -l stock-full-emmc.bin 2>/dev/null && echo "stock-full-emmc.bin exists: use another name, don't overwrite it"
edl rf stock-full-emmc.bin 2>&1 | tee backup.log
```

- 大約 10～20 分鐘，期間別動線。
- 期望輸出最後有一行：`Dumped flash with sector count 15269888 as stock-full-emmc.bin.`

驗證備份完整，三項都要對：

```bash
ls -l stock-full-emmc.bin
python3 -c "f=open('stock-full-emmc.bin','rb'); f.seek(512); print(f.read(8))"
shasum -a 256 stock-full-emmc.bin | tee stock-full-emmc.bin.sha256
```

1. 檔案大小正好是 `7818182656` 位元組，也就是 `15269888 × 512`；
2. 第二條列印 `b'EFI PART'`，說明開頭是完整的 GPT 分割區表；
3. 第三條把校驗和存進 `stock-full-emmc.bin.sha256`，以後用它確認備份沒壞。

（Windows：`(Get-Item .\stock-full-emmc.bin).Length` 看大小，`python -c …` 那條照用，`Get-FileHash` 算校驗和。）

備份放哪：

- 和 `gpt-before.txt` 一起放在 `~/thinksmart`，**再拷一份到行動硬碟或另一臺電腦**；
- 不要上傳到網盤或公開的地方：裡面有這臺裝置獨有的資料。

以後要回原廠：進 EDL 後執行 `edl wf stock-full-emmc.bin`，整盤寫回，要先得到使用者同意。

失敗了怎麼辦：

- 中途報錯或斷開：拔線，重新進 EDL，換線或換口，再跑一次（換個檔名）。
- 大小不對或不是 `EFI PART`：備份不完整，刪掉這個檔案重做。**備份沒做成之前，不要往下走。**

### A3. 刷 lk2nd 到 boot 分割區（先問使用者）

lk2nd 是一個二級 bootloader，負責從 `system` 分割區啟動 Linux。

```bash
edl w boot lk2nd.img 2>&1 | tee flash-lk2nd.log
```

期望輸出最後：`Wrote lk2nd.img to sector 790528.`

失敗了怎麼辦：

- `Couldn't detect partition: boot`：分割區表沒讀對，先重跑 `edl printgpt` 看看。
- 其他報錯：重新進 EDL 後重試一次，仍失敗就停下來。

### A4. 刷 bootstrap 到 system 分割區（先問使用者）

先選刷哪個 bootstrap 映像：

1. **只用 USB 線的話**，直接刷下載的 `bootstrap-pmos-ssh-generic-qcom-msm8953.img`，跳到下面的刷寫命令。
2. **想讓 bootstrap 也能用 WiFi（實驗性：未經 Oh I'm Smart 在原廠裝置上實測）**：USB 網路連不上時（比如 Windows 認不出來），bootstrap 可以改走 WiFi。用本倉庫的 `prepare.sh` 做一份改好的副本（要先裝 Docker，見 0.2）：

   ```bash
   git clone https://github.com/ohimsmart/oh-im-smart.git ~/oh-im-smart
   cd ~/thinksmart
   ~/oh-im-smart/bootstrap/prepare.sh bootstrap-pmos-ssh-generic-qcom-msm8953.img bootstrap-prepared.img
   ```

   它會問三件事，由使用者本人回答：
   - WiFi 名稱：留空表示只用 USB；最多 32 位元組。
   - WiFi 密碼：留空表示開放網路；否則是 8～63 個可列印 ASCII 字元，或 64 個十六進位數字。
   - bootstrap 的登入密碼：至少 8 個字元、最多 128 位元組，不能是 `thinksmart`，輸入兩次。

   密碼輸入時不顯示。成功時最後一行是 `prepare: wrote bootstrap-prepared.img. Delete it after flashing: it may hold your WiFi password, and holds a hash of your login password.`。下面的 `<bootstrap 映像>` 就用 `bootstrap-prepared.img`。Windows 未實測：要裝 Docker Desktop，並在 WSL 的 bash 裡執行。
3. 兩項提醒：
   - bootstrap 的 SSH 會在區域網上開著，直到刷入 Ubuntu 為止，所以登入密碼不能用公開的預設值（`prepare.sh` 已經拒絕 `thinksmart`）；
   - 刷完本映像（A8）後刪掉 `bootstrap-prepared.img`：裡面有 WiFi 密碼和登入密碼的雜湊。

刷寫（`<bootstrap 映像>` 是 `bootstrap-pmos-ssh-generic-qcom-msm8953.img` 或 `bootstrap-prepared.img`）：

```bash
edl w system <bootstrap 映像> 2>&1 | tee flash-bootstrap.log
edl reset
```

期望輸出：

- 第一條最後：`Wrote <bootstrap 映像> to sector 923648.`（edl 列印的是你刷的那個檔名）
- `edl reset` 輸出 `Reset succeeded.`

裝置會自己重啟：先短暫出現 lk2nd 的介面，再啟動 postmarketOS。**USB 線不要拔**，下一步要用它連 SSH。

### A5. SSH 登入 bootstrap

bootstrap 開機後會透過 USB 線提供一個網路：裝置是 `172.16.42.1`，電腦通常會自動拿到 `172.16.42.2`。A4 用了 `prepare.sh` 並填了 WiFi 的話，它同時也會連上 WiFi。按順序試三種辦法：先等 USB 網路（下面第 1～4 步）；兩分鐘內沒出現就改用 WiFi；兩者都不行就接鍵盤在裝置上手動連 WiFi。

登入密碼：用了 `prepare.sh` 的話是當時設的；沒用的話是 `thinksmart`，走過下面「兩者都不行」那一步的，是那一步設的。

**先等 USB 網路：**

1. 等 1～2 分鐘，讓裝置開完機。
2. 檢查電腦上多了一個網路介面：
   - macOS：「系統設定 → 網路」裡多出一個有線介面；
   - Linux：`ip -br addr` 裡多出一個 `usb0` 或 `enx…` 介面；
   - Windows（未實測）：「網路連線」裡多出一個乙太網介面卡。bootstrap 用的是 USB NCM 網路卡，Windows 11 自帶 NCM 驅動，一般能直接識別；Windows 10 自帶的 NCM 驅動和部分裝置不相容，可能認不出來。認不出來的話見下面「Windows 連不上 USB 網路」。
3. 沒有自動拿到 `172.16.42.x` 的地址，就手動設定這個介面：IP `172.16.42.2`，子網掩碼 `255.255.0.0`，路由器留空。
4. 登入：

```bash
ping -c 3 172.16.42.1
ssh -o StrictHostKeyChecking=accept-new pmos@172.16.42.1
```

**兩分鐘內沒出現 USB 網路，而且 A4 用了 `prepare.sh` 並填了 WiFi：** 改走 WiFi。在路由器的裝置列表裡找主機名 `thinksmarter`，或者掃區域網（bootstrap 只開 22 埠）：

```bash
nmap -p 22 --open <網段>
ssh -o StrictHostKeyChecking=accept-new pmos@<bootstrap IP>
```

**兩者都不行：** 接上 USB 鍵盤，按順序做：

1. 在裝置螢幕上以 `pmos` 登入。
2. **A4 沒用 `prepare.sh` 的話，先改密碼、鎖住 root，再連 WiFi。** 連上 WiFi 後 bootstrap 的 SSH 就在區域網上開著，而上游映像裡 `pmos` 和 `root` 的密碼都是公開的 `thinksmart`，SSH 也允許 root 用密碼登入。執行下面三行：第一行給 `pmos` 設自己的密碼（至少 8 個字元，不是 `thinksmart`；它會先問當前密碼 `thinksmart`），之後 A5、A6 都用它；第二行鎖住 `root`；第三行確認鎖住了，期望列印出以 `root:!` 開頭的一行：

   ```sh
   passwd
   doas passwd -l root
   doas grep '^root:!' /etc/shadow
   ```

   沒有列印出那一行就停下來，不要連 WiFi。
3. 執行下面四行，在 `nmtui` 裡連上 WiFi，再照上面「改走 WiFi」找 IP、登入：

   ```sh
   doas sh -c 'dbus-uuidgen > /etc/machine-id'
   doas rc-service dbus start
   doas rc-service networkmanager start
   doas nmtui
   ```

登入後先確認進對了系統：

```bash
cat /etc/hostname
ls /usr/local/sbin/apply-ubuntu-gpt.sh
```

期望輸出：`thinksmarter`，以及腳本路徑本身。

失敗了怎麼辦：

- ping 不通：確認螢幕上 postmarketOS 已經起來了；換個 USB 口；macOS 上按第 3 點手動設 IP；拔插一次 USB 線。
- 螢幕停在 lk2nd 的介面（寫著 fastboot）：bootstrap 沒刷好，回到 A1 重新進 EDL，重做 A4。
- Windows 連不上 USB 網路（未實測）：在 A4 用 `prepare.sh` 加上 WiFi（Windows 上的 Docker 未實測），回到 A1 重刷 A4，再照上面「改走 WiFi」；或者只在這一步借一臺 macOS 或 Linux 電腦。
- 以前 SSH 過 `172.16.42.1` 或這個 IP、提示主機金鑰變了：見[3.6](#36-ssh-提示主機金鑰變了)。

### A6. 改分割區表（先問使用者，不可逆）

在 bootstrap 的 SSH 裡執行：

```bash
sudo /usr/local/sbin/apply-ubuntu-gpt.sh
```

`sudo` 要密碼的話，就是 A5 登入用的那個密碼。期望輸出最後：

```
GPT rewrite complete.
Next steps:
1. Power off or reboot the device.
...
```

腳本列印的第 3 步提到上游映像的檔名，**不用管**，下一步刷的是本映像。

然後馬上關機：

```bash
sudo poweroff
```

這一步把 `system` 分割區擴到約 6.8 GB，刪掉原廠的 vendor、cache、userdata 等分割區，`persist` 移到磁碟末尾。

失敗了怎麼辦：腳本報錯就**不要關機、不要重試**，把完整輸出給使用者，停下來。

### A7. 再進 EDL，確認新分割區表

等螢幕黑下來（插著電的話它可能會自己重新亮起，沒關係），再按[1.1](#11-進-edl使用者動手)拔掉電源進 EDL，然後：

```bash
edl printgpt 2>&1 | tee gpt-after.txt
grep -E "^(system|userdata):" gpt-after.txt
```

期望輸出：只有一行 `system:`，`Length 0x00000001b3cfbe00`，沒有 `userdata:`。

如果 `system` 仍然是 `0x0000000060000000`：分割區表沒改成功，回到 A4 重來（lk2nd 已經刷過，A3 不用重做）。

### A8. 刷本映像（先問使用者）

```bash
edl w system thinksmart-ubuntu-<日期>.img 2>&1 | tee flash-system.log
edl reset
```

- 寫入要幾分鐘到二十分鐘，期間別動線。
- 期望輸出：最後有 `Wrote thinksmart-ubuntu-<日期>.img to sector 923648.`，然後是 `Reset succeeded.`

失敗了怎麼辦：

- `Error: … has N sectors but partition only has 3145728.`：分割區表還是原廠的，回 A7 檢查。
- 寫到一半報錯：重新進 EDL 重試一次；仍失敗就停下來，把 `flash-system.log` 給使用者。

寫完後拔掉 USB 線，進入[第 2 步：首次開機](#2-首次開機和設定)。

A4 用了 `prepare.sh` 的話，確認本映像開機之後刪掉改好的副本，它裡面有 WiFi 密碼和登入密碼的雜湊：

```bash
rm ~/thinksmart/bootstrap-prepared.img
```

---

## 路線 B：已經刷過本映像或上游 Ubuntu 映像

分割區表和 lk2nd 都已經就位，只需要重寫 `system` 分割區。

> 這會清掉舊系統裡的所有東西：聊天記錄、閘道器裡的 API Key 和管理員密碼、WiFi 配置、SSH 授權。只是想升級語音客戶端或閘道器的話，**不用重刷**，見[第 5 節](#5-以後的更新)。

### B1. （推薦）先備份使用者資料

舊系統是本映像、還想保留聊天記錄和設定的話，先按[4.1](#41-刷機前備份)備份，刷完再還原。舊系統是上游的 Plasma 映像就跳過這一步，裡面沒有這些資料。

### B2. 進 EDL 並確認分割區表

按[1.1](#11-進-edl使用者動手)、[1.2](#12-讀分割區表)做，確認 `system` 的 Length 是 `0x00000001b3cfbe00`。

### B3. 刷本映像（先問使用者）

和 [A8](#a8-刷本映像先問使用者) 完全一樣：

```bash
edl w system thinksmart-ubuntu-<日期>.img 2>&1 | tee flash-system.log
edl reset
```

拔掉 USB 線，進入第 2 步。

---

## 2. 首次開機和設定

### 2.1 首次開機

- 首次開機先出現介面語言選擇（繁體中文／简体中文／English），點一個之後才到歡迎頁。以後在語音客戶端的設定頁可以再改。
- 第一次開機比平時慢，大約 1～2 分鐘：系統會自動把根分割區擴滿整個 `system` 分割區，並生成這臺裝置自己的 SSH 主機金鑰。之後每次開機大約 20 秒。
- 螢幕上會出現**歡迎頁**（深色背景，有裝置地址和 WiFi 狀態）。

### 2.2 螢幕上連 WiFi（使用者動手）

1. 在歡迎頁點「連線 Wi‑Fi」按鈕，在「選擇 Wi‑Fi」列表裡點你的網路。
2. 用螢幕鍵盤輸入密碼，點「連線」。面板顯示「已連線 <WiFi 名稱>」並回到網路列表，就成功了。
3. 點面板右上角的 × 關掉面板。歡迎頁底部會顯示「裝置地址」，幾秒後介面自動切到語音助手。

連不上：見[3.3](#33-沒有-wifi螢幕配網不成功)。

### 2.3 找到裝置的 IP

後面用瀏覽器和 SSH 都要用到。刷完的系統目前**不能用 USB 線登入**（見[附錄](#刷完後的-usb-網路)），只能連上 WiFi 後用 WiFi 的地址。

AI 助手：**自己找，不要問使用者**。

1. 看電腦在哪個網段（電腦要和裝置連同一個路由器）：

   ```bash
   # macOS：列印本機 IP
   ipconfig getifaddr $(route -n get default | awk '/interface:/{print $2}')
   # Linux：輸出裡 src 後面是本機 IP
   ip -4 route get 1.1.1.1
   ```

   本機 IP 是 `192.168.1.23` 的話，網段一般就是 `192.168.1.0/24`。

2. 掃區域網裡同時開著 22（SSH）和 16688（閘道器後臺）埠的機器：

   ```bash
   nmap -p 22,16688 --open 192.168.1.0/24
   ```

   沒裝 nmap：macOS `brew install nmap`，Linux `sudo apt install nmap`。16688 沒掃到的話，可能是閘道器還在載入語音識別模型，等 1 分鐘再掃。

3. 確認候選地址：用瀏覽器開啟 `http://<IP>:16688/admin`，標籤頁上的標題是「小智 Hub 管理後臺」（英文瀏覽器上是「Xiaozhi Hub Admin」）就對了。在命令列看到的是網頁原文，不管瀏覽器是哪種語言都是 `小智 Hub 管理后台`：

   ```bash
   curl -s http://<IP>:16688/admin | grep -o '<title>[^<]*'
   ```

macOS 上 nmap 什麼都掃不到、`curl` 或 `ssh` 報 `No route to host`：終端程式沒有「本地網路」權限，見[3.8](#38-macos-上-ssh-報-no-route-to-host)。

不用 nmap 的辦法（Windows 也能用，Windows 上用 `ipconfig` 看本機 IP）：

- 路由器管理頁的 DHCP 客戶端列表（裝置列表），主機名是 `thinksmart`（`thinksmarter` 是 bootstrap 和上游映像的主機名）；
- 裝置螢幕：歡迎頁上的「裝置地址」（連上 WiFi 後介面很快切到語音助手，這個地址只閃一下），或者語音介面設定頁裡的「本機 IP」。這一項要請使用者看螢幕告訴你。

下面用 `<裝置IP>` 代表這個地址。

第一次 SSH 前：如果這個 IP 以前連過別的裝置或舊系統，先清掉舊記錄，否則會報主機金鑰變了：

```bash
ssh-keygen -R <裝置IP>
```

用 4.2 節專用記錄檔案的，再清一次：`ssh-keygen -R <裝置IP> -f ~/.ssh/known_hosts_thinksmart`。

### 2.4 閘道器管理後臺：設管理員密碼、填 API Key（使用者動手）

1. 用電腦瀏覽器開啟 `http://<裝置IP>:16688/admin`。開機後閘道器要大約 1 分鐘載入語音識別模型，打不開就等一會兒再重新整理。
2. **先設管理員密碼**。沒設之前，同一區域網裡任何人都能開啟這個後臺。
3. 填大模型的 API Key。預設用 Claude API；也可以換成 DeepSeek 等其他廠商，在後臺裡選。
4. 儲存。

沒填 Key 之前，語音助手能喚醒，但答不上來。

AI 助手注意：API Key 由使用者自己在瀏覽器裡填，不要替使用者填，也不要把 Key 寫進任何檔案或日誌。

### 2.5 改預設密碼（為了安全，刷完馬上改）

本映像只有一個能登入的帳號，**預設密碼是 `thinksmart`，而且 SSH 開著**；`root` 已經鎖住，不能登入：

| 帳號 | 預設密碼 | 說明 |
| --- | --- | --- |
| `ubuntu` | `thinksmart` | 日常用的帳號，可以免密 sudo |

`ubuntu` 用 `sudo` 不用輸密碼，這是有意的：更新和備份腳本靠它。所以 `ubuntu` 的密碼就等於這臺裝置的管理員密碼，同一個區域網裡的人知道預設密碼就能完全控制它，一定要改：

```bash
ssh ubuntu@<裝置IP>
passwd               # 改 ubuntu 的密碼
```

以前 SSH 過這臺裝置（包括 bootstrap 階段的 `172.16.42.1`）的話，主機金鑰變了，先清掉舊記錄：

```bash
ssh-keygen -R <裝置IP>
ssh-keygen -R 172.16.42.1
```

AI 助手注意：新密碼由使用者自己輸入，不要替使用者想密碼，也不要記錄下來。

### 2.6 設時區

本映像預設是 UTC。在 SSH 裡設成自己的時區，再確認：

```bash
sudo timedatectl set-timezone <時區>
timedatectl
```

常見的時區：`Asia/Shanghai`、`Asia/Hong_Kong`。完整列表用 `timedatectl list-timezones` 查。`timedatectl` 的輸出裡 `Time zone` 一行應該是你設的時區。

### 2.7 確認語音能用（使用者動手）

1. 對著裝置說「**小麥小麥**」（也認「哈囉小麥」「小麥同學」），螢幕會切到聆聽狀態，並響一聲提示音。
2. 問一句，比如「今天星期幾」，等它回答。喚醒詞只認中文；喚醒之後用閘道器管理後臺裡「說話語言」設的語言提問。

不靈的話，在 SSH 裡查服務狀態：

```bash
systemctl status thinksmart-client --no-pager | head -5    # 語音客戶端，應為 active (running)
systemctl --user status xiaozhi-hub --no-pager | head -5   # 閘道器，應為 active (running)
journalctl -u thinksmart-client -b --no-pager | tail -30
```

能喚醒、答不上來：多半是 API Key 沒填或填錯，回 2.4 檢查。不能喚醒或沒聲音：見[3.4](#34-沒有聲音或者喊了沒反應)。

---

## 3. 常見問題排查

### 3.1 edl 找不到裝置，或者連上後馬上斷開

表現：一直停在 `Waiting for the device`，或者報 `Couldn't detect the device`。

按順序試：

1. 確認裝置真在 EDL：螢幕全黑，電腦上能看到 `9008` / `QUSB__BULK`（見 1.1）。
2. 換一根**能傳資料**的線。很多充電線只能充電。
3. 直接插電腦本體，別經過擴充套件塢、Hub、顯示器上的口。
4. 拔掉 USB 線和電源線讓裝置斷電，再按 1.1 重新進 EDL。EDL 閒置一段時間或某條命令失敗後，常常要重進一次。
5. Linux：確認 ModemManager 已停（`systemctl status ModemManager`），udev 規則已裝；還不行就用 `sudo`。
6. Windows（未實測）：裝置管理器裡裝置還帶感嘆號，就按 1.1 用 Zadig 裝 WinUSB。裝過高通官方 9008 驅動的，edl 也可以加 `--serial` 走串列埠方式（`edl --serial printgpt`）。
7. Apple Silicon 的 Mac：確認點了「允許配件連線」。

### 3.2 開機停在 lk2nd 的 Fastboot 介面

表現：螢幕上是 lk2nd 的文字選單，寫著 `Fastboot mode`，不往下啟動。

原因：lk2nd 在 `system` 分割區裡沒找到能啟動的系統。常見於刷寫中斷、刷錯了檔案，或者分割區表沒改成功就刷了映像。

處理：

1. 拔掉電源線（停在 lk2nd 介面時登入不了，直接拔），再按 1.1 進 EDL。
2. `edl printgpt` 確認 `system` 是 `0x00000001b3cfbe00`。
3. 重新校驗 `.img`（0.5 節），然後重做 A8 / B3。

**別用 fastboot 刷任何東西。**

### 3.3 沒有 WiFi，螢幕配網不成功

- 歡迎頁會顯示附近的網路。看不到你的網路：確認路由器在 2.4 GHz 或 5 GHz 正常廣播（隱藏 SSID 要手動輸入名字）。
- 密碼對了但一直「正在獲取網路地址」：等 1 分鐘；仍然不行就重啟一次裝置。
- 刷完的系統目前不能用 USB 線登入（見[附錄](#刷完後的-usb-網路)）。螢幕配網一直不成功：重啟裝置再試；還不行就重刷（A8 / B3）後重新配網。
- 已經能透過 WiFi SSH 登入、想換到另一個網路時，可以用命令連：

  ```bash
  nmcli dev wifi list
  sudo nmcli dev wifi connect "<WiFi名>" password "<WiFi密碼>"
  ip -4 -br addr show wlan0
  ```

  也可以用文字介面 `sudo nmtui`。
- 連上後螢幕還停在歡迎頁：`sudo kiosk-mode restart` 重開展示介面。

### 3.4 沒有聲音，或者喊了沒反應

```bash
systemctl --user status pipewire wireplumber thinksmart-mic --no-pager | grep -E "●|Active"
wpctl status | sed -n '/Audio/,/Video/p'
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

- 三個服務都應是 `active (running)`。`wpctl status` 的 Sinks 裡應該有 `Built-in Audio Speaker`，Sources 裡應該有 `Microphone` 和 `Microphones (both)`。
- 音量太小：`wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`，或者按裝置上的音量鍵。
- 裝置上的麥克風開關（隱私開關）要開啟，關著的時候語音助手聽不到。
- 服務都正常但還是沒聲音：重啟裝置。這臺機器的音訊 DSP 偶爾會卡住，只有重啟能恢復。
- **不要直接操作音效卡硬體**（`speaker-test -D hw:…`、`aplay -D hw:…` 等），會讓音訊 DSP 卡死。所有聲音都走 PipeWire。
- 要單獨重啟 WirePlumber（比如改了它的配置），先停麥克風服務再重啟，否則麥克風服務佔著錄音口，WirePlumber 找不到音效卡，只剩一個 `Dummy Output`：

  ```bash
  systemctl --user stop thinksmart-mic && systemctl --user restart wireplumber && sleep 5 && systemctl --user start thinksmart-mic
  ```

  語音客戶端會發現聲音斷了、自己重啟（約 20 秒）。

### 3.5 開機進不了介面（黑屏、白屏、一直停在歡迎頁）

```bash
systemctl status thinksmart-kiosk thinksmart-client --no-pager | grep -E "●|Active"
journalctl -u thinksmart-kiosk -b --no-pager | tail -30
```

- `thinksmart-kiosk` 是螢幕上的展示介面，`thinksmart-client` 是語音客戶端（提供介面內容）。
- 重開展示介面：`sudo kiosk-mode restart`。
- 一直停在歡迎頁：說明裝置沒聯網，或者語音客戶端沒起來，先看 3.3 和上面 `thinksmart-client` 的狀態。
- 螢幕全黑但能 SSH：可能是熄屏了，碰一下螢幕或在裝置前揮揮手。
- SSH 也連不上：刷完的系統不能用 USB 線登入，先確認裝置連上了 WiFi（3.3）、IP 找對了（2.3）；macOS 上報 `No route to host` 見 3.8；都不行就重刷（A8 / B3）。

### 3.6 SSH 提示主機金鑰變了

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

每次刷機都會生成新的主機金鑰，這是正常的：

```bash
ssh-keygen -R <裝置IP>
ssh-keygen -R 172.16.42.1
```

如果你**沒有**重刷過卻看到這條警告，先別連，確認是不是 IP 被別的裝置佔了。

### 3.7 寫入時提示分割區太小

`Error: … has N sectors but partition only has 3145728.`：分割區表還是原廠的，要走路線 A，先改分割區表。

### 3.8 macOS 上 ssh 報 No route to host

```
ssh: connect to host <裝置IP> port 22: No route to host
```

裝置線上、IP 也對，Mac 上卻連不上區域網地址：多半是終端程式沒有「本地網路」權限。開啟「系統設定 → 隱私與安全性 → 本地網路」，把你用的終端程式（終端、iTerm、VS Code 等）的開關開啟，然後重開終端再試。瀏覽器打不開 `http://<裝置IP>:16688/admin` 也可能是同樣的原因，給瀏覽器開啟這個權限。

### 3.9 開機停在緊急模式（emergency mode）

現象：螢幕上是一屏英文，最後幾行是 `You are in emergency mode`，前面有 `Failed to start systemd-fsck…`、`Dependency failed for boot.mount - /boot`，往上還能看到 `I/O error, dev mmcblk0 … (WRITE)`。

原因：沒關機就直接拔了電，下次開機要修復啟動分割區 `/boot`，修復時往儲存裡寫入失敗，系統就停在這裡。你的資料在另一個分割區（根分割區），一般沒事。以後拔電前先關機（見[需要使用者本人動手的操作](#需要使用者本人動手的操作)），就能避免。

處理（只重寫啟動分割區，不動你的資料）：

1. 按 1.1 進 EDL。
2. 先把整個 `system` 分割區讀出來留底（約 6.8 GB，實測約 4 分鐘，慢的電腦可能要十幾分鍾，期間別動線）：

   ```bash
   edl r system system-backup.img
   ```

3. 從**你刷的那個版本**的映像裡取出啟動分割區（映像裡從第 2048 扇區開始，共 509952 個扇區）：

   ```bash
   dd if=thinksmart-ubuntu-<日期>.img of=boot-part.img bs=512 skip=2048 count=509952
   ```

   Windows 在 WSL 裡執行這條命令。
4. 算寫入位置：`edl printgpt` 輸出裡 `system` 那一行的 Offset（比如 `0x000000001c300000`）除以 512，再加 2048。按本教程改過分割區表的裝置是 `923648 + 2048 = 925696`。
5. 寫入（**先問使用者**），再重啟：

   ```bash
   edl ws 925696 boot-part.img
   edl reset
   ```

   正常的話會進語音介面。還是停在緊急模式，把螢幕照片和 `system-backup.img` 留好，按路線 B 重刷，再用 4.2 還原資料（之前沒有備份的話，可以從 `system-backup.img` 裡取回資料）。

---

## 4. 備份和還原使用者資料

本映像不帶任何個人資料。從舊版本映像重刷到新版本時，可以把下面這些先備份、刷完再還原：

- 閘道器的資料目錄：API Key、管理員密碼、Grok 登入、聊天記錄 `chat.db`；
- Claude Code 的登入（如果裝過）；
- 語音客戶端設定：裝置 ID、睡眠時段、亮度、熄屏；
- 展示介面的瀏覽器儲存；
- `~/.ssh/authorized_keys`；
- WiFi 配置、主機名、`/etc/thinksmart-kiosk.conf`；
- SSH 主機金鑰（可選，還原後電腦就不會提示主機金鑰變了）。

這些檔案裡有 API Key 和密碼，備份檔案只放在自己電腦上，別上傳。

### 4.1 刷機前備份

在電腦上執行（舊系統還在、能 SSH 時）：

```bash
ssh ubuntu@<裝置IP> 'systemctl --user stop xiaozhi-hub; cd / && sudo tar --numeric-owner --ignore-failed-read -cpf - \
  home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/data home/ubuntu/.claude home/ubuntu/.claude.json \
  home/ubuntu/.config/thinksmart-client home/ubuntu/.local/share/thinksmart-kiosk home/ubuntu/.ssh \
  etc/NetworkManager/system-connections etc/netplan etc/thinksmart-kiosk.conf etc/hostname \
  etc/ssh/ssh_host_ecdsa_key etc/ssh/ssh_host_ecdsa_key.pub etc/ssh/ssh_host_ed25519_key \
  etc/ssh/ssh_host_ed25519_key.pub etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub; \
  systemctl --user start xiaozhi-hub' > userdata.tar
chmod 600 userdata.tar
tar tf userdata.tar | head -20
```

- 打包前先停閘道器，聊天記錄資料庫不會寫到一半；打包完自動重新啟動。
- 不存在的路徑會跳過並列印一行提示，不影響結果。
- 最後一條應該能列出 `home/ubuntu/xiaozhi-hub-server/...`、`etc/NetworkManager/...` 等路徑。

### 4.2 刷機後還原

前提：刷完、螢幕上連好 WiFi、知道 `<裝置IP>`。還原腳本在本倉庫的 `image/restore-userdata.sh`，要在 macOS / Linux 上跑（Windows 用 WSL）。

1. 準備一把專用的 SSH 金鑰，並授權給裝置（會問一次 `ubuntu` 的密碼，剛刷完是 `thinksmart`）：

   ```bash
   [ -f ~/.ssh/thinksmart_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/thinksmart_ed25519
   ssh-copy-id -i ~/.ssh/thinksmart_ed25519 -o UserKnownHostsFile=~/.ssh/known_hosts_thinksmart ubuntu@<裝置IP>
   ```

2. 還原：

   ```bash
   TS_HOST=<裝置IP> image/restore-userdata.sh userdata.tar --host-keys
   ```

   - `--host-keys` 會把舊的 SSH 主機金鑰也還原回去，不想要就去掉。用了它之後，第 1 步記下的是新金鑰，要清掉：`ssh-keygen -R <裝置IP> -f ~/.ssh/known_hosts_thinksmart`。
   - 第 1 步提示主機金鑰變了（以前連過這個 IP），先執行上面這條 `ssh-keygen -R`，再重做第 1 步。
   - 期望輸出：先列出 `restoring: …`，最後是 `restored on the device` 和 `done; the hub needs about a minute to load its speech model`。
   - 腳本會先把整個備份解到裝置上的臨時目錄，全部成功才停服務、替換檔案；任何一步失敗都會報錯退出，裝置保持原樣，服務也會重新啟動。

3. 還原後閘道器裡的管理員密碼、API Key 都回到備份時的樣子。裝置密碼和時區不在備份裡，還原到剛刷好的裝置時，按 2.5、2.6 再做一次。

---

## 5. 以後的更新

- **語音客戶端**：設定頁「軟體更新」裡檢查，有新版本時點「更新」。更新來自 [ohimsmart/oh-im-smart-client](https://github.com/ohimsmart/oh-im-smart-client) 的 Release。更新包只從 HTTPS 下載，裝之前逐個檔案核對大小和 sha256，裝壞了自動退回舊版本。

  想自己發布客戶端更新（比如用自己改過的客戶端）：用本倉庫的 `update/make-release.py` 生成更新清單和安裝包，把生成的檔案傳到自己 GitHub 倉庫的 Release，再把裝置上 `/etc/thinksmart-update.conf` 裡 `SOURCES` 的地址改成自己倉庫的 Release 地址。不需要任何金鑰。更新沒有簽名，更新地址上放什麼，裝置就會以 root 身份裝什麼：`SOURCES` 只填你自己的、或你信任的地址，**不要填公共的 GitHub 加速映像或代理站**。用法見 `update/README.md`。
- **閘道器**：在閘道器管理後臺（`http://<裝置IP>:16688/admin`）側邊欄點「更新閘道器」，更新來自 [ohimsmart/oh-im-smart-gateway](https://github.com/ohimsmart/oh-im-smart-gateway)。頁面顯示當前版本的時間和短提交號，可以檢查有沒有新版本；只有你點了更新才會裝，裝失敗會自動退回舊版本。

  也可以用命令列，SSH 進裝置後執行：

  ```bash
  cd ~/xiaozhi-hub-server && bash scripts/update.sh
  ```

  它會拉新程式碼、補裝依賴、重啟閘道器。
- **系統軟體包**：`sudo apt update && sudo apt upgrade` 可以照常用。螢幕、聲音、網路依賴的 41 個包（補丁版 Mesa、WebKitGTK、Weston、PipeWire、NetworkManager 等，清單在 `image/held-packages.txt`）鎖在測過的版本上，不會被升級。核心和驅動不歸 apt 管，也不會變。
- **系統層**（展示屏外殼、歡迎頁、螢幕鍵盤、熄屏和接近感測器、麥克風服務、音訊和藍芽音箱配置、更新服務自己）：和語音客戶端在同一個「軟體更新」裡，有新版本時一起顯示，點一次「更新」先裝系統層再裝客戶端。裝之前把要換的檔案都備份下來，裝完重啟用到它們的服務（螢幕會閃一下）並自檢，沒通過就把備份放回去。系統層的更新包和客戶端放在同一個 Release 裡（客戶端倉庫），本倉庫的 Releases 只放刷機映像。只換本倉庫 `image/system-files.txt` 裡列的檔案：核心、驅動、boot 分割區和 apt 裝的軟體包不在裡面，這些要重刷；你自己改過的 `/etc/thinksmart-kiosk.conf` 等配置不會被覆蓋。
- **系統映像本身**：有新版映像時按[路線 B](#路線-b已經刷過本映像或上游-ubuntu-映像)重刷，記得先做[4.1 備份](#41-刷機前備份)。

---

## 附錄：分割區和映像結構

給想弄明白原理的人和 AI 助手參考。

| 分割區 | 作用 | 本教程會不會寫 |
| --- | --- | --- |
| `boot` | lk2nd 二級 bootloader | 路線 A 寫一次 |
| `system` | 整個 Linux 系統，改分割區表後約 6.8 GB（扇區 923648 起，14280671 個扇區） | 每次刷機都寫 |
| `modem`、`dsp`、`persist` 等 | 高通韌體和裝置資料 | 從不寫 |

本映像（`.img`）是 `system` 分割區的內容，裡面又是一張 MBR 小分割區表：

- 第 1 個分割區：`pmOS_boot`（ext2），核心、initramfs、裝置樹、啟動配置；
- 第 2 個分割區：`pmOS_root`（ext4），Ubuntu 24.04 根檔案系統。首次開機時 initramfs 會把它擴到 `system` 分割區末尾。

啟動順序：高通 PBL → 原廠 SBL/aboot → `boot` 分割區裡的 lk2nd → 讀 `system` 裡 `pmOS_boot` 的 extlinux 配置 → Linux。

### 刷完後的 USB 網路

**已知問題：刷完後的系統目前不能用 USB 線登入。** 映像裡的 USB 網路已經設成 NCM（裝置 `172.16.42.1`，上游裝置包預設是 macOS 不支援的 RNDIS），但系統起來後裝置的 USB 口不會被電腦識別（電腦的 USB 裝置列表裡看不到它），改回 RNDIS 也一樣，問題在 USB 口沒切到裝置模式，還沒修。

所以刷完後只能連上 WiFi 再用 WiFi 的地址登入。bootstrap 階段（[A5](#a5-ssh-登入-bootstrap)）的 USB 網路不受影響，照常能用。

### 映像裡的系統調整

和上游映像相比，除了去掉 Plasma 桌面、開機直接進語音介面，還做了這些調整（都有意為之）：

- 螢幕上不能雙指縮放：展示介面只接收第一根手指，免得誤觸把頁面放大。
- USB 網路設成 NCM 而不是上游的 RNDIS（不過目前刷完後的系統 USB 口不被電腦識別，見上一節）。
- WiFi 省電關閉：這塊 QCA9379 網路卡省電時會漏收 DHCP 回覆，開機後要等 1～3 分鐘才拿到 IP。
- 41 個關鍵軟體包鎖定版本（見[第 5 節](#5-以後的更新)）。
- 接近感測器直接讀 `/dev/i2c-0`（`ubuntu` 在 `i2c` 組裡），不再每秒呼叫 sudo 刷滿日誌。
- 時間同步用五個 NTP 伺服器，國內國外都連得上：`ntp.aliyun.com`、`ntp.tencent.com`、`cn.pool.ntp.org`、`pool.ntp.org`、`ntp.ubuntu.com`。時區預設是 UTC，見 [2.6](#26-設時區)。
- 主機名是 `thinksmart`；`root` 已經鎖住，只有 `ubuntu` 能登入（見 [2.5](#25-改預設密碼為了安全刷完馬上改)）。
- 日誌只存在 systemd 日誌裡（持久儲存，最多 64 MB、一個月），關掉了重複寫一份到 `/var/log` 的 rsyslog。查日誌用 `journalctl`。
- 不生成程式崩潰轉儲（core dump），省磁碟；開了 zram 壓縮記憶體。
- 停用了用不上的 ModemManager、avahi、udisks2。
- 螢幕鍵盤是系統鍵盤：展示屏外殼給每個頁面都裝上，點到輸入框就從螢幕下方彈出（`kiosk/keyboard.js`）。頁面只放普通輸入框，不用自帶鍵盤。
- 首次開機先選介面語言（繁體中文／简体中文／English），選好之前展示屏停在歡迎頁；從舊版本線上更新上來的裝置（包括展示自己網頁的）也會停下來選一次。選擇存在 `/home/ubuntu/.config/thinksmart-kiosk/lang`：歡迎頁、語音客戶端（外殼開啟本機 8090 埠的客戶端時加上 `?lang=`）和螢幕鍵盤都跟著它。客戶端設定頁換語言也寫進這個檔案；歡迎頁底部的語言按鈕可以重新選。
- 語音客戶端的設定頁也能切換 WiFi 和介面語言：外殼只接受兩種頁面的這些請求，一是本地歡迎頁，二是展示屏配置的地址恰好是本機（127.0.0.1/localhost，預設就是客戶端）。展示屏指向別人的服務時不放權，區域網裡的頁面也碰不到。
- 藍芽音箱：只開 A2DP 接收（手機放歌給它），關掉擴音（HFP/HSP），免得手機把通話聲音轉過來。手機的聲音不直接送喇叭，而是交給語音客戶端混進自己的輸出，這樣放歌時喚醒詞照樣能用（`bluetooth/`）。配對、開關、手機列表在客戶端設定頁，配對只在點了「新增手機」後的 3 分鐘內接受，不用輸密碼。

已知限制：

- 首次開機不連網也能用螢幕配網；語音識別在本機，大模型和語音合成（預設 Edge TTS）要聯網。
- 攝影機不能用（上游也還在研究）。
- 刷完後的系統不能用 USB 線登入，只能走 WiFi（見[刷完後的 USB 網路](#刷完後的-usb-網路)）。
- 為了禁止雙指縮放，螢幕只接收第一根手指。用螢幕鍵盤兩指交替快速打字時，第一根手指還沒抬起、第二根就按下，第二下會丟掉，少一個字。輸 WiFi 密碼時慢一點，一次一指。
- 映像裡帶的 GPU 韌體、WiFi/藍芽韌體來源和上游相同（照上游做法）。
- 手機用藍芽放歌時，語音客戶端一直在做回聲消除，佔一個核約 70%（不放歌時約 20%）。WiFi 和藍芽是同一顆晶片，藍芽放歌時 2.4 GHz WiFi 可能變慢。
- 藍芽在手機上顯示為平板圖示：裝置類別由 BlueZ 按機型自動設，`main.conf` 裡改不掉。

---

## 致謝和宣告

- Oh I'm Smart 是 [justhalfbit](https://github.com/justhalfbit) 的 [thinksmart-ubuntu-image](https://github.com/justhalfbit/thinksmart-ubuntu-image)、[xiaozhi-thinksmart-client](https://github.com/justhalfbit/xiaozhi-thinksmart-client) 和 [xiaozhi-hub-server](https://github.com/justhalfbit/xiaozhi-hub-server) 的延伸版本：映像、語音客戶端和閘道器都從它們出發。出處和授權見 [NOTICE](NOTICE) 和 [LICENSE](LICENSE)。
- 裝置移植、lk2nd、bootstrap 映像和分割區方案來自 [rickx/ubuntu-thinksmart](https://github.com/rickx/ubuntu-thinksmart)，沒有它就沒有這個專案。上游也感謝了 FelixKa 的 postmarketOS 裝置包和 TAS5782M 驅動，以及 postmarketOS 專案的核心。
- 刷機工具是 [bkerler/edl](https://github.com/bkerler/edl)。
- 映像由 Ubuntu 24.04 的軟體包構建。本專案是個人專案，與 Canonical、聯想（Lenovo）、高通（Qualcomm）沒有任何關係。「Ubuntu」「ThinkSmart」是各自所有者的商標。
- 刷機有風險，可能讓裝置無法啟動。請先做好整盤備份，風險自負。

## 倉庫裡有什麼

| 目錄 | 內容 |
| --- | --- |
| `image/` | 出映像（從裝置抓取、清理、打包）、備份還原使用者資料的腳本 |
| `bootstrap/` | 準備 bootstrap 映像（`prepare.sh`：WiFi、自己的登入密碼） |
| `tools/` | 三份教程的一致性檢查（`check-readmes.sh`） |
| `kiosk/` | 展示屏外殼（Weston + WebKitGTK 全屏頁面）、歡迎頁、螢幕鍵盤、GPU 看門狗、WiFi 省電和 NTP 設定 |
| `screen/` | 自動熄屏、接近感測器和加速度喚醒 |
| `xiaozhi/` | 麥克風服務和音訊配置（ALSA、PipeWire、WirePlumber） |
| `bluetooth/` | 藍芽音箱：WirePlumber 配置（只做 A2DP 接收，手機的聲音交給語音客戶端）、BlueZ 設定 |
| `update/` | 線上更新（語音客戶端和系統層） |
| `mesa/` | 補丁版 Mesa（GPU 白屏、卡死修復）的構建腳本和補丁 |
| `codec-dmic/`、`kernel/` | 第二顆麥克風的驅動和裝置樹補丁，以及構建它用的核心環境 |
| `zram/` | zram 壓縮記憶體 |

本倉庫以 MIT 許可發布，見 [LICENSE](LICENSE)。
