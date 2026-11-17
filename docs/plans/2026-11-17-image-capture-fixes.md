# 第一次擷取的檢查結果處理（計劃 5b Task 7 的補充） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 處理 5b（`docs/plans/2026-11-16-image-release.md`）Task 7 第一次測試打包時 `check-rootfs.sh` 和 sanitize 報出的每一項，讓測試映像通過，然後回到 5b Task 7 繼續。

**Architecture:** 先在母機上確認兩個被 sanitize 刪掉的音訊檔是否必要（維護者聽）；不必要就母機也拿掉它們，必要就停下（要進系統層，是 1.0.1，另寫計劃）。其餘各項都是 5b Global Constraints 例外 (a)、(b) 已允許的：本 repo `image/` 的允許清單，和母機上的帳號清理。最後重新擷取、打包。

**Tech Stack:** bash、ssh（UM → 母機）、Docker（經 `sg docker`）。

**Global Constraints:**
- 5b 的 Global Constraints 照用。這份計劃允許的母機動作全部列在這裏，此外不做別的：Task 1 的停用 `tas5782m-preinit.service`、把 `51-cd18781y-alsa.lua` 和 `~/.local/state/wireplumber` 移到 `~/audio-off`、冷關機再開機、成功後刪掉它們或失敗後還原；Task 3 的刪除四個只授權 `user` 的 sudoers 檔、刪除 `/etc/subuid`、`/etc/subgid` 的 `user:` 行。每個動作之前先把指令寫進 `~/tsimg/record.md`，改動前的原檔先存到 UM 的 `~/tsimg/mother-before/`（5b Task 9 會重刷母機，那是唯一的副本）。
- 只做寫明的動作；跟 Expected 不符就停下回報。
- 改的 repo 檔案只有 `image/allowlist.sh`（已改，未 commit）、`image/hub-ignored.txt`、`image/upstream-provenance.txt`（都不在 `SYSTEM_DIRS`），加上本計劃本身；Task 4 之後若照 5b 例外 (a) 還要改 `image/` 裏的別的檔案，一併列入。它們在 5b Task 7 的 Commit 步驟一起 commit（Task 4 寫明）：5b Task 8 和 `build-image.sh` 的正式打包要求 `git status --porcelain` 完全沒有輸出，未追蹤的計劃檔也不行。執行紀錄留在 `~/tsimg/record.md`，5b Task 10 才搬進計劃。

---

## 背景：第一次測試打包的結果（2026-11-17，`~/tsimg/build.log`）

- `docker build` 失敗：UM 本機的 `ubuntu:24.04` 內容缺失；`docker pull` 後正常（已處理）。
- sanitize：`/usr/lib/ssl/certs`、`/usr/lib/ssl/private` 是指向 `/etc/ssl/...` 的絕對目錄連結，`dpkg -S` 屬於 `openssl`，`image/` 沒有任何東西在它們底下刪改：照映像計劃失敗表「連結」那一行加入 `OUT_DIR_LINKS_OK`（已改，未 commit）。
- sanitize 刪掉、不在 `home-allowlist.txt` 上的：
  - `~/.config/systemd/user/tas5782m-preinit.service` 和它在 `default.target.wants/` 的連結（已啟用，oneshot：登入時播一段聲音讓 TAS5782M 功放晶片初始化；`image/device-setup.sh:105` 只刪它的 `.bak-*`）；
  - `~/.config/wireplumber/main.lua.d/51-cd18781y-alsa.lua`（2026-05-19 的舊規則：停用 playback 2.0、4.0 和 capture 4.0、所有 ALSA 節點 `disable-mmap`、period 1024、headroom 8192；系統層的 `xiaozhi/99-cd18781y-alsa.lua` 是後來的規則，已有 `node.pause-on-idle = false`，不完全相同）。
  - 映像不帶這兩個檔，喇叭是否照常沒有驗證過：Task 1。
  - 其餘刪除是預期的：`graphical-session.target.wants/vcnl4200-proximity-daemon.service`（5b 背景）、展示屏的 localstorage、cookies 和 salt、WirePlumber 的狀態檔。
- `check-rootfs`：
  1. 網關被忽略的 `main/xiaozhi-server/models/sherpa-onnx-x-asr-zipformer-transducer-zh-en-punct-int8-2026-06-03/` 不在 `hub-ignored.txt`。網關 `2d067d9` 的 `scripts/config.template.yaml` 預設 `ASR: SherpaXASR`（本地 X-ASR，sherpa-onnx），映像的新 `data/` 用這個範本，所以模型要留：加入清單。
  2. 上游網址：客戶端 `README.md` 的出處說明一行；網關 `README.md`、`README.en.md` 的 GitHub Stars 徽章；`tests/scripts/test_bootstrap.py` 測試從上游 checkout 遷移的參數；`plugins_func/functions/get_weather.py` 的 `USER_AGENT`。`image/upstream-provenance.txt` 的說明寫明 `line` 條目就是給「README badge or the weather plugin's User-Agent」這類出處標示的：逐行加 `line` 條目，不改網關。
  3. `/etc/subuid`、`/etc/subgid` 第一行是 `user:100000:65536`，母機沒有 `user` 帳號（`getent passwd user` 沒有結果；UID 1000–59999 只有 `ubuntu`）。
  4. `/etc/sudoers.d/` 的 `i2c-prox`、`idle-blanker`、`proximity`、`user` 都只授權 `user`（不存在）；`ubuntu` 的免密碼 sudo 在 `ubuntu-nopasswd`（`ubuntu ALL=(ALL) NOPASSWD: ALL`），螢幕服務以 `ubuntu` 執行，不靠那四個檔。
- 第 3、4 項是 5b 例外 (b) 的「處理帳號」「把別的帳號從 sudoers 檔拿掉」；第 1、2 項和連結是例外 (a)。

---

### Task 1: 母機不帶那兩個音訊檔時，喇叭是否正常

映像裏三樣都沒有：這兩個檔，和 WirePlumber 記住的預設輸出（sanitize 刪掉 `~/.local/state/wireplumber`）。母機要在同樣的狀態下測，而且要冷開機（燒錄後的映像一定是冷開機，熱重啟可能保留功放晶片的狀態）。

- [ ] 先存原檔到 UM，再移開（可還原）：

整段一個 `set -euo pipefail` 腳本：備份沒有齊全就不會動母機。

```bash
cat > ~/tsimg/audio-off.sh <<'EOF'
set -euo pipefail
B=~/tsimg/mother-before/audio; M=ubuntu@192.168.50.181
mkdir -p "$B"
scp -rp $M:.config/systemd/user/tas5782m-preinit.service $M:.config/wireplumber/main.lua.d/51-cd18781y-alsa.lua \
    $M:.local/state/wireplumber "$B"/
test -s "$B/tas5782m-preinit.service"; test -s "$B/51-cd18781y-alsa.lua"; test -d "$B/wireplumber"
ssh $M 'wpctl get-volume @DEFAULT_AUDIO_SINK@; wpctl inspect @DEFAULT_AUDIO_SINK@ | grep node.name' > "$B/before-volume.txt"
cat "$B/before-volume.txt"
grep -q '^Volume: ' "$B/before-volume.txt"; grep -q 'node.name = ' "$B/before-volume.txt"
ssh $M 'set -e
test ! -e ~/audio-off
mkdir ~/audio-off
systemctl --user disable tas5782m-preinit.service
mv ~/.config/wireplumber/main.lua.d/51-cd18781y-alsa.lua ~/audio-off/
mv ~/.local/state/wireplumber ~/audio-off/wireplumber-state
test ! -e ~/.local/state/wireplumber
ls ~/audio-off; systemctl --user is-enabled tas5782m-preinit.service || true'
echo audio-off-ok
EOF
bash ~/tsimg/audio-off.sh
```

Expected：`audio-off-ok`；`before-volume.txt` 記下改動前的音量和預設輸出；母機 `~/audio-off` 有 `51-cd18781y-alsa.lua` 和 `wireplumber-state`；`is-enabled` 印 `disabled`。
- [ ] **冷開機**：助手 `ssh ubuntu@192.168.50.181 'test ! -e ~/.local/state/wireplumber && echo COLD-HALT && sudo systemctl halt'`（ssh 可能因連線斷開回報錯誤，正常；不用 `poweroff`：插着電會馬上重開）。**維護者**等螢幕變黑再等 10 秒，拔電源線，等 30 秒，再插上（README.zh-Hant.md 第 84 行的做法）。
- [ ] 開機後，助手先記錄（不改）：`wpctl get-volume @DEFAULT_AUDIO_SINK@`（沒有記住的狀態時 WirePlumber 的預設約 -24 dB，母機原本記住的是 `before-volume.txt` 的值；新刷的裝置也是這樣，教學 README.zh-Hant.md 第 800 行已寫「音量太小：`wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5`，或者按裝置上的音量鍵」），`wpctl status`，`wpctl inspect @DEFAULT_AUDIO_SINK@ | grep node.name`。然後把音量調回 `before-volume.txt` 的值：`ssh ubuntu@192.168.50.181 'wpctl set-volume @DEFAULT_AUDIO_SINK@ <before-volume.txt 的 Volume 數字>'`（這也是本計劃允許的母機動作；它會寫進 WirePlumber 的狀態，跟使用者照教學調音量一樣）。
- [ ] 音量調回之後，**維護者**確認並說出聽到的情形：說喚醒詞，喚醒提示音正常；對話一輪，回覆從喇叭播出，沒有沒聲、破音、第一聲被吃掉；麥克風聽得到（對話成立）。助手確認：`systemctl --user is-active pipewire wireplumber thinksmart-mic.service` 都是 `active`；預設輸出的 `node.name` 跟 `before-volume.txt` 記下的相同（2026-11-17 唯讀實測是 `alsa_output.platform-c051000.sound-card.HiFi__Speaker__sink`，UCM 的 HiFi 設定；不是 `playback.0.0`）；`journalctl --user -b --no-pager -p warning -u wireplumber -u pipewire | tail -20` 沒有新的錯誤。預設音量偏小這件事記進 `~/tsimg/record.md`，作為已知、教學已寫的情形，回報時讓維護者決定要不要之後在系統層設預設音量；它不算這一步不正常。
- [ ] **全部正常：** `ssh ubuntu@192.168.50.181 'rm -rf ~/audio-off ~/.config/systemd/user/tas5782m-preinit.service'`（母機跟映像一致；原檔在 UM），記錄。
- [ ] **任何一項不正常：** 一個指令停 WirePlumber（它執行中會把記憶中的狀態寫回去）、還原、確認、關機，不用上面那個「狀態目錄不存在」的檢查：

```bash
ssh ubuntu@192.168.50.181 'set -e
systemctl --user stop wireplumber.service
mv ~/audio-off/51-cd18781y-alsa.lua ~/.config/wireplumber/main.lua.d/
rm -rf ~/.local/state/wireplumber
mv ~/audio-off/wireplumber-state ~/.local/state/wireplumber
test -s ~/.config/wireplumber/main.lua.d/51-cd18781y-alsa.lua
test -s ~/.local/state/wireplumber/default-routes
systemctl --user enable tas5782m-preinit.service
echo RECOVERY-HALT
sudo systemctl halt'
```

印出 `RECOVERY-HALT` 後**維護者**照上面冷開機的做法拔電、等 30 秒、插上，確認聲音恢復。記錄症狀、音量和預設輸出，停下回報：映像的音訊要在系統層處理，以 1.0.1 發佈，另寫計劃找出原因；不在這裏斷定是不是這兩個檔。

### Task 2: 允許清單（本 repo `image/`）

- [ ] `image/hub-ignored.txt` 末尾加：

```
# the default ASR (config.template.yaml: SherpaXASR) loads this model; the gateway downloads it at install
main/xiaozhi-server/models/sherpa-onnx-x-asr-zipformer-transducer-zh-en-punct-int8-2026-06-03/
```

- [ ] `image/upstream-provenance.txt`：`check-rootfs: upstream URLs:` 之後印出的每一行是 `/<路徑>:<整行內容>`，逐行轉成 `line<TAB>/<路徑><TAB><整行內容>`，內容一字不改，用腳本從 `~/tsimg/build.log` 取（路徑裏沒有 `:`，所以在第一個 `:` 分開）：

```bash
( set -euo pipefail
awk 'f && !/^\//{f=0} f{print} /^check-rootfs: upstream URLs:$/{f=1}' ~/tsimg/build.log > ~/tsimg/prov-hits.txt
test "$(wc -l < ~/tsimg/prov-hits.txt)" = 5
while IFS= read -r h; do printf 'line\t%s\t%s\n' "${h%%:*}" "${h#*:}"; done < ~/tsimg/prov-hits.txt >> image/upstream-provenance.txt
tail -5 image/upstream-provenance.txt | cut -c1-120 )
```

只收背景第 2 項列出的五行；重新打包後若再印出別的上游網址或維護者識別字串，屬於徽章、User-Agent、出處說明或遷移測試的照樣加，其他的（安裝或 clone 指令、系統層檔案）照 5b 停下。
- [ ] 經 `sg docker -c 'bash ~/tsimg/image-tests.sh'` 跑三個 image 測試（5b Task 1 的腳本），三個 `exit 0`，沒有 `not ok`；`shellcheck image/allowlist.sh` 沒有新的警告。

### Task 3: 母機的帳號清理

- [ ] 指令先寫進 `~/tsimg/record.md`；先把原檔存到 UM，再執行：

```bash
cat > ~/tsimg/accounts.sh <<'EOF'
set -euo pipefail
T=~/tsimg/mother-before/accounts.tar
ssh ubuntu@192.168.50.181 'sudo tar -C / -cf - etc/sudoers.d etc/subuid etc/subgid' > $T.partial
tar -tf $T.partial > /dev/null
n=$(tar -tf $T.partial | grep -cx -e etc/sudoers.d/user -e etc/sudoers.d/i2c-prox -e etc/sudoers.d/idle-blanker \
    -e etc/sudoers.d/proximity -e etc/subuid -e etc/subgid)
test "$n" = 6
mv $T.partial $T
ssh ubuntu@192.168.50.181 'set -e
sudo rm /etc/sudoers.d/user /etc/sudoers.d/i2c-prox /etc/sudoers.d/idle-blanker /etc/sudoers.d/proximity
sudo visudo -c
sudo sed -i "/^user:/d" /etc/subuid /etc/subgid
grep -c "^user:" /etc/subuid /etc/subgid || true
sudo -n true && echo sudo-ok'
EOF
bash ~/tsimg/accounts.sh
```

Expected：`visudo -c` 各檔 `parsed OK`；兩個計數 `0`；`sudo-ok`（`ubuntu` 仍可免密碼 sudo）。`visudo -c` 失敗就停下（`sudo` 仍由 `ubuntu-nopasswd` 給，不要再刪別的）。

### Task 4: 重新擷取、打包，回到 5b

- [ ] 照 5b Task 7 用 `~/tsimg/test-image.sh`（重新擷取再打包）經 `sg docker` 跑；Expected 照映像計劃 Task 8：`check-rootfs: ok`、四次 `privacy check ok`、產生 `-TEST-DO-NOT-PUBLISH.img.xz`；`grep -e 'removed /home/' -e 'clean-hub-git: ignored:' ~/tsimg/build.log` 的每一行能說出是甚麼。
- [ ] 還有失敗：照 5b 例外 (a)、(b) 能處理的就處理後重做這一步；不能的停下。
- [ ] 通過後回到 5b Task 7 的 **Commit** 步驟（不是它後面的「用正式的秘密檔再跑一次」）：在 `release/image-v1` 上 `git add image/allowlist.sh image/hub-ignored.txt image/upstream-provenance.txt docs/plans/2026-11-17-image-capture-fixes.md`（Task 4 中照例外 (a) 改過的其他 `image/` 檔案也加上），Litmus 後 commit；然後照 5b Task 7 的順序做下去：秘密檔那次打包、Task 1 的測試、merge 到 `main`（`--no-ff`）並推送、`release/image-v1` 跟上 `main`、`git status --porcelain` 沒有輸出。

## 不在這份計劃裏

- 網關 README 的徽章和天氣外掛的 User-Agent 改指向 ohimsmart：`upstream-provenance.txt` 的設計允許它們留着，要改是網關的事，之後另議。
- `hub-ignored.txt` 的模型目錄名稱帶日期：網關換模型時要一起更新。
- 客戶端 README 那個 `line` 條目的路徑帶版本號（`/opt/thinksmart/client/1.0.0/README.md`）：下一個客戶端版本的映像要更新它。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
