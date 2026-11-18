# 第一個 Oh I'm Smart 映像（v1 計劃 5b）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 照 spec §5.6 發佈第一個 Oh I'm Smart 版本：客戶端 1.0.0 和系統層 1.0.0 的線上更新 Release、母機經線上更新裝上它、§9 的線上更新回復測試、擷取並打包映像（映像計劃 Task 8）、以 pre-release 發佈映像、跑 §9 驗收，通過後改為 Latest。

**Architecture:** 先確認 spec §8 的發佈前條件；本 repo 的系統層升到 1.0.0 並 merge（客戶端 `main` 已是 1.0.0）；母機照 §5.3 第 6 點準備（更新來源、網關 checkout）；在 UM 用 `make-release.py` 產生線上更新，維護者同意後發佈到客戶端 repo；母機經頁面的「更新」一次裝上系統層和客戶端；然後在母機做回復測試，測試後清除更新器的狀態（spec §9 允許的做法）；擷取、打包、檢查；映像以 pre-release 發佈到 `ohimsmart/oh-im-smart`，附上 GPL 原始碼；維護者照繁中教學重刷驗收。

**Tech Stack:** bash、Docker（UM，legacy builder；這個 shell 不在 docker 群組，經 `sg docker -c '…'`；`sg` 用 `/bin/sh`（dash），所以要 bash 的指令先寫成腳本再 `sg docker -c 'bash 腳本'`；`sg` 會傳回指令的結束碼）、`gh`、Python 3.12、`image/pull-from-device.sh`、`image/build-image.sh`、`update/make-release.py`、`update/thinksmart-update`。

**Global Constraints:**
- 這是 v1 七份計劃第 5 份的後半。5a（三語教學）已 merge（`781f1d6`）。
- **母機：** `ubuntu@192.168.50.181`（同一部裝置也在 USB `172.16.42.1`，兩處的 ED25519 主機金鑰都是 `SHA256:Hmnq2rurIUXjHyvSs7ipwuhHdG79NF70HLlJY70f21s`）。UM 的 `~/.ssh/id_ed25519` 已授權。
- **會改動母機的步驟**（換設定、換網關 checkout、裝更新、回復測試）只做本計劃寫明的動作。Task 3 先把現狀記到 UM 的 `~/tsimg/mother-before/`；任何一步跟 Expected 不符就停下回報，不臨場發揮。
- **對外發佈**（客戶端 repo 的 Release、本 repo 的 pre-release、改為 Latest、推送標籤、改 repo 的保護規則）每一次都先把要做的事（標籤、標題、目標 commit、要上傳的檔案和說明，或規則內容）給維護者看，得到明確同意才執行。
- **版本只升不降（spec §5.2）：** 1.0.0 一旦發佈，之後的修正一律是新版本和新的 Release；不重新上傳、不改寫已發佈的 1.0.0。
- **這份計劃只走第一輪（1.0.0）。** Task 4 發佈之後，任何 Expected 不符（含 Task 7 要改 `SYSTEM_DIRS`、Task 9 驗收不通過）：停下，把情形記進 `~/tsimg/record.md`，回報維護者；修正和重做（新版本號、母機重新接上、網關前進、新的映像標籤）另寫一份計劃，經設計審閱後再做。不在這份計劃裏臨場重做。
- **唯一的例外是 Task 7 的擷取檢查**（映像計劃 Task 8 的失敗處理表，本來就是擷取的一部分）。允許的只有兩類：(a) 只改本 repo `image/` 裏不在 `SYSTEM_DIRS` 的檔案（`home-allowlist.txt`、`hub-ignored.txt`、`upstream-provenance.txt`、`allowlist.sh`、`sanitize-rootfs.sh`、`check-rootfs.sh`、`image/tests/`）；(b) 表格寫明在母機上做的那幾種動作：刪掉多出的 timesyncd drop-in、把權限和擁有者改成 `image/system-files.txt` 那一行、把母機自己做的連結換成實際的目錄或檔案、處理 `/home` 以外的帳號、把別的帳號從 sudoers 檔拿掉、改名或刪除帶維護者識別字串的檔案、處理沒有帳號的 uid/gid 的檔案、刪掉網關裏不在 `hub-ignored.txt` 上的被忽略檔案、秘密檔命中的那些檔案。母機上的每個動作先把指令寫進 `~/tsimg/record.md` 再做，做完重新擷取。**表格要求改系統層（`system layer differs`、系統層檔案裏的上游網址、`SYSTEM_DIRS` 的任何檔案）、改客戶端或網關的程式碼或 commit、或表格沒有列出的情形，都照上一條停下。**
- **標籤一律是簽署過的 annotated tag**（本 repo 的 git 設定 `tag.gpgsign=true`，SSH 格式）：`make-release.py` 打的是不帶訊息的 tag（`update/make-release.py:148`），簽署時要訊息，會失敗（映像計劃第 197 行記錄過），所以 `system-v<版本>` 在跑 `make-release.py` 之前用 `git tag -s -m …` 打好（`make-release.py` 看到已有的標籤就沿用）。**所有 Release 的標籤**（客戶端 repo 的 `c<客戶端>-s<系統層>`、本 repo 的 `image-…`）都先在本機簽署（客戶端 repo 也是 `tag.gpgsign=true`）、經維護者同意推送，再 `gh release create --verify-tag`，不讓 GitHub 建未簽署的標籤（Task 0 的規則生效後標籤不能再換）。簽署失敗就停下回報，不關掉簽署。
- `~/tsimg/secrets.txt` 由維護者自己寫，不進任何 repo，助手不讀它的內容（只把路徑交給 `build-image.sh`）。
- 各 repo 的分支 merge 到 `main` 只用 `git merge --no-ff`，不 rebase、不 force-push；每個 commit 先過 Litmus。測試一律 `GIT_CONFIG_GLOBAL=/dev/null`，不接 `| tail`。
- **實作中的紀錄**寫在 `~/tsimg/record.md`，Task 10 才搬進本計劃：`build-image.sh` 正式打包要求 repo 沒有未 commit 的改動（`git status --porcelain` 必須是空的），所以打包前不能改動已 commit 的計劃。
- 實機上要人做的事（看螢幕、點按鈕、刷機、說話、在瀏覽器確認、輸入密碼）標為「維護者」，助手不代做。

---

## 背景：已確認的事實（2026-11-16）

- `main`：`oh-im-smart` = `781f1d6`，`oh-im-smart-client` = `1282847`，`oh-im-smart-gateway` = `2d067d9`。三個 repo 都還沒有任何 Release。
- 版本：本 repo `VERSION` = `0.2.1`；客戶端 `main` 的 `thinksmart_client/__init__.py` 已是 `__version__ = '1.0.0'`。spec §5.2：兩者從 1.0.0 開始。`make-release.py` 的 Release 標籤是 `c<客戶端>-s<系統層>`，這次是 `c1.0.0-s1.0.0`。
- 已發佈 commit 的測試紀錄：客戶端 `1282847` pytest 179 passed、node 16 passed（`docs/plans/2026-11-14-updater-msg-keys.md`）；網關 `2d067d9` 765 passed、5 failed、5 skipped（`docs/plans/2026-11-13-gateway-english-and-urls.md` 第 29–34 行和實作記錄）：`tests/test_stt.py` 的 4 項需要本地語音辨識模型，`tests/admin/test_admin.py::test_missing_packages_real_providers` 檢查真實 provider 的套件，都來自測試環境。spec §9 沒有為這 5 個開例外，Task 4 問維護者時一併列出，由維護者接受或要求先處理。
- **母機現狀**（SSH 唯讀實測）：KDE neon 24.04 基底（上游映像的基底，Plasma 已停用）、主機名稱 `thinksmarter`；`status.json`：客戶端 `current` 0.1.6，`system.current` 0.1.0（`available` 是上游的 0.2.1）；`/usr/local/sbin/thinksmart-update` 的 sha256 等於本 repo commit `57e4138` 的版本（`UPDATER_VERSION = 2`，已能裝系統層，有「已更新到 系统层 {system} · 客户端 {client}」訊息，沒有 `msg_key` 和 `job.reboot`）；`/etc/thinksmart-update.conf` 的 `SOURCES` 指向 `justhalfbit/xiaozhi-thinksmart-client`；網關 checkout 在分支 `device/language-6490e888ebc5`（`6490e88`），origin 是 `justhalfbit/xiaozhi-hub-server`，本機還沒有 `2d067d94`（`git diff --stat 6490e88 2d067d9` 沒有依賴或安裝腳本的改動）；`usb0` 開着（`172.16.42.1`）。
- **接近感應服務：** 母機載入的服務檔是 `/etc/xdg/systemd/user/vcnl4200-proximity-daemon.service`（`systemctl --user show -p FragmentPath`）；`/etc/xdg/systemd/user` 是指向 `../../systemd/user` 的連結，所以它跟 `/etc/systemd/user/vcnl4200-proximity-daemon.service`（644 root）是同一個檔案（`readlink -f` 實測）。它由 `~/.config/systemd/user/graphical-session.target.wants/` 裏的連結 enable；`kiosk/thinksmart-kiosk-app` 每次啟動展示屏時也會 `systemctl --user start` 它。映像的 `image/home-allowlist.txt` 要求服務檔在 `~/.config/systemd/user/`（普通檔案）；那個 enable 連結不在允許清單上，`sanitize-rootfs.sh` 打包時會刪掉它，映像裏只靠展示屏啟動服務。所以這次把服務檔放進系統層，目的地 `~/.config/systemd/user/`（搜尋順序最先，蓋過 `/etc` 那份）；母機上的 enable 連結不動。
- **`make-release.py`**（`update/README.md`「發一個版本」）：`make-release.py <客戶端 checkout> <OUT> --system <本 repo> --note … --system-note …`。產物：`OUT/latest/download/latest.json`、`OUT/download/<標籤>/` 裏的客戶端包、依賴環境包、系統層包，和 `release-<標籤>.txt`（標籤、標題、要上傳的檔案的檔名、說明）。系統層檔案沒 commit 就報錯；已有 `system-v<版本>` 標籤而系統層跟它不同也報錯。依賴環境在 arm64 容器裏建。
- **頁面的「更新」**是 `requests/` 裏的 `{"action": "install", "version": <客戶端>, "system": <系統層>}`，由 `thinksmart-update-request.path` 觸發 `thinksmart-update run`；處理請求的是**母機上原本那份**更新器（`57e4138`），它先裝系統層，系統層沒裝成就停下，客戶端這次不裝。`requests/` 是 `root:ubuntu` 770，`ubuntu` 可以寫；以 `.` 開頭的檔名會被略過。更新器用 `/run/thinksmart-update.lock`（`fcntl.flock`）互斥。系統層缺少必要套件時清單的 `system.available` 帶 `missing`，`run` 不裝。
- 系統層自檢 90 秒，重啟過的服務 10 秒內沒再重啟才算過；不過就把備份逐個放回、重啟、複查，`job.state` 是 `rolled_back`、`component` 是 `system`。更新器記住看過最新的清單發佈時間，比它舊的清單不接受（spec §9）。
- 歡迎頁：母機沒有 `~/.config/thinksmart-kiosk/lang`，新的展示屏啟動後會停在三語選擇（spec §6.2.4，正常）；`sanitize-rootfs.sh` 打包前會刪掉這個選擇。
- **擷取：** `pull-from-device.sh` 經 `ts.sh` 連線，用 `~/.ssh/thinksmart_ed25519` 和 `~/.ssh/known_hosts_thinksmart`（README 4.2），UM 上兩者都還沒有。
- `build-image.sh` 的產物：`<name>.img.xz`、`SHA256SUMS`、`packages.txt`；`<name>` 預設 `thinksmart-ubuntu-<YYYYMMDD>`。`--test-image` 或 `ALLOW_UNRELEASED=1` 的產物名稱帶 `-TEST-DO-NOT-PUBLISH`；正式打包要 `RELEASE_MANIFEST=<latest.json>`、必填的 `SECRETS_FILE`、乾淨的 repo；映像裏的客戶端、系統層版本和檔案集合必須跟這次發佈一模一樣。
- 內核：`kernel/README.md`：`linux-postmarketos-qcom-msm8953` 6.19.5-r0，pmaports commit `ed3f995f`，`device/community/linux-postmarketos-qcom-msm8953/APKBUILD` 寫明 tarball（`linux-postmarketos-qcom-msm8953-v6.19.5-r0.tar.gz`）的網址和 sha512。
- spec §8：發佈帳號 `chris-yyau` 必須已開啟雙重驗證，release tag 和主分支受保護，在發佈第一個映像前確認。實測：`gh` 的 token 沒有 `user` scope，`gh api user` 的 `two_factor_authentication` 是 `null`，API 驗證不了；三個 repo 都沒有 ruleset；`main` 有傳統的 branch protection（`enforce_admins`、不准 force-push、不准刪）；**標籤沒有任何保護**。
- 映像計劃 Task 8（`docs/plans/2026-11-09-image-packaging.md`）的擷取、測試映像和失敗處理表照用，以下幾點不同：它的「母機裝上這個分支的系統層」（`device-setup.sh files`）**不做**，這次系統層經線上更新裝上；失敗表的 `system layer differs` 不照表回到 `device-setup.sh`，改為停下查明是哪個檔案被改過（`sudo thinksmart-update system-verify` 和 `git diff`），回報維護者；失敗表要求「把裝置需要的檔案放進 repo 和 `system-files.txt`」時，那是系統層的改動，照 Global Constraints 停下（另寫計劃）。
- 已知不穩定的測試：`screen/test_idle_blanker.py`（之前的計劃記錄過）。失敗時單獨重跑一次，第二次通過就記下、照常進行；兩次都失敗就停下。

## 決定

1. **回復測試在正式 Release 之後、在母機上做，測試後清除更新器的狀態**（spec §9 允許的第二種做法）。之前做不到：母機的系統層 0.1.0，正式清單之前沒有 1.0.0 可以退回到。測試用的系統層版本 `99.0.0`，故意讓 `screen-wake.service` 起不來，只放在本機的測試來源上，永不發佈。
2. **線上更新和映像都在 UM 產生**（spec 已定 UM 為打包主機）。
3. **映像的 Release** 以打包那一次的 `main` commit 為目標，標籤 `image-<ID>`（Task 8：日期，同一天第二個起加 `.2`…）在本機簽署後推送。說明用 Task 8 的模板；GPL 原始碼以附件上傳（內核 tarball、內核 config、`kernel/build.sh`、`kernel/Dockerfile`、`kernel/README.md`、`codec-dmic/` 打成一個 tar，tar 的 sha256 寫在 `SHA256SUMS`）；`packages.txt`。
4. **驗收用的裝置就是母機**：spec §9 要維護者的裝置先備份再照繁中教學以路線 B 重刷。映像產生之後母機的任務已完成；備份照教學 4.1。
5. **教學裏 C16 那句（Releases 頁面暫時是空的）在 pre-release 發佈後刪掉**（5a 計劃 C16 的約定）。**驗收通過才改為 Latest**；不通過就停下，修正另寫計劃（新版本、重新打包）。
6. **標籤保護（spec §8）由維護者決定**：建議三個 repo 各加一條 tag ruleset（Task 0 的指令）。這是帳號和安全設定，助手只在維護者同意後執行。

## 需要維護者決定或動手的事

- 確認 `chris-yyau` 的雙重驗證（Task 0）。
- 同意（或修改）Task 0 的標籤保護規則。
- 每一次對外發佈前的同意（Global Constraints）。
- 在母機的客戶端設定頁點「軟體更新」裏的「更新」，出現時確認「取代自訂版本」，裝完重啟一次（Task 5）。
- 寫 `~/tsimg/secrets.txt`（Task 7）。
- 驗收的實機操作（Task 9）。

---

### Task 0: 發佈前條件（spec §8）

- [ ] **維護者**在瀏覽器開 `https://github.com/settings/security`，確認 `chris-yyau` 的 Two-factor authentication 是 Enabled，在對話裏回覆「2FA 已開」。（`gh` 的 token 沒有 `user` scope，助手用 API 查不到。）沒開就停下。
- [ ] 讀三個 repo 的規則（唯讀）：

```bash
for r in oh-im-smart oh-im-smart-client oh-im-smart-gateway; do
  echo "== $r"
  for id in $(gh api "repos/ohimsmart/$r/rulesets" --jq '.[].id'); do
    gh api "repos/ohimsmart/$r/rulesets/$id" --jq '{name, target, enforcement, include: .conditions.ref_name.include, rules: [.rules[].type]}'
  done
  gh api "repos/ohimsmart/$r/branches/main/protection" --jq '{admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled, deletion: .allow_deletions.enabled}'
done
```

Expected：每個 repo 的 `main` 是 `{"admins":true,"force_push":false,"deletion":false}`，而且有一條 `target` 是 `tag`、`enforcement` 是 `active`、`include` 涵蓋所有標籤、`rules` 含 `deletion` 和 `update` 的 ruleset。
- [ ] 沒有標籤規則的話（2026-11-16 的現況）：**問維護者**，建議的規則如下（所有標籤不准刪除、不准移動，可以新增；沒有 bypass，連管理員也不行）。同意後執行，再跑一次上一步確認：

```bash
for r in oh-im-smart oh-im-smart-client oh-im-smart-gateway; do
  gh api -X POST "repos/ohimsmart/$r/rulesets" --input - <<'EOF'
{"name": "release tags", "target": "tag", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
 "rules": [{"type": "deletion"}, {"type": "update"}, {"type": "non_fast_forward"}]}
EOF
done
```

維護者不同意或要改規則：照維護者的決定做；不加任何保護就停下（spec §8 不成立）。

### Task 1: 本 repo：系統層 1.0.0、接近感應服務檔、計劃

**Files:**
- Modify: `VERSION`、`image/system-files.txt`
- Create: `screen/vcnl4200-proximity-daemon.service`（從母機取得）
- Commit: `docs/plans/2026-11-16-image-release.md`（本計劃，設計審閱通過後）

- [ ] 在分支 `release/image-v1` 上（寫計劃時已建立）。`mkdir -p ~/tsimg && chmod 700 ~/tsimg && touch ~/tsimg/record.md`。
- [ ] 取得服務檔，讀一遍，確認沒有 key、個人路徑或主機名稱：

```bash
ssh ubuntu@192.168.50.181 'readlink -f "$(systemctl --user show -p FragmentPath --value vcnl4200-proximity-daemon.service)"'   # /etc/systemd/user/vcnl4200-proximity-daemon.service，否則停下
scp ubuntu@192.168.50.181:/etc/systemd/user/vcnl4200-proximity-daemon.service screen/
chmod 644 screen/vcnl4200-proximity-daemon.service
cat screen/vcnl4200-proximity-daemon.service
```

- [ ] 在 `image/system-files.txt` 的 `screen/vcnl4200-proximity-daemon.py` 那一行之後加（目的地跟 `idle-blanker.service` 一樣在 `~/.config/systemd/user/`，符合 `image/home-allowlist.txt` 第 9 行；母機上這個位置還沒有檔案，所以更新時會照表設權限和擁有者）：

```
screen/vcnl4200-proximity-daemon.service /home/ubuntu/.config/systemd/user/vcnl4200-proximity-daemon.service 644 ubuntu user:vcnl4200-proximity-daemon.service
```

- [ ] `VERSION` 改為 `1.0.0`。
- [ ] 測試（`image/tests` 的腳本要 Docker，寫成腳本經 `sg` 跑）：

```bash
sg docker -c 'GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk bootstrap tools screen'
cat > ~/tsimg/image-tests.sh <<'EOF'
cd ~/Projects/ohimsmart || exit 1
fakeroot sh image/tests/test-sanitize.sh > /tmp/test-sanitize.out; echo "sanitize exit $?"
sh image/tests/test-image-privacy.sh > /tmp/test-privacy.out; echo "privacy exit $?"
sh image/tests/test-build-image.sh > /tmp/test-build.out; echo "build exit $?"
grep -h '^not ok' /tmp/test-sanitize.out /tmp/test-privacy.out /tmp/test-build.out
EOF
sg docker -c 'bash ~/tsimg/image-tests.sh'
```

Expected：pytest 全部通過（數字記進 `~/tsimg/record.md`）；三個 `exit 0`，沒有 `not ok` 行。
- [ ] Litmus 後兩個 commit：`git add VERSION image/system-files.txt screen/vcnl4200-proximity-daemon.service`，`git commit -m "System layer 1.0.0; the proximity unit joins the system layer"`；`git add docs/plans/2026-11-16-image-release.md`，`git commit -m "docs(plan): the first Oh I'm Smart image (plan 5b of 7)"`。
- [ ] `git switch main && git merge --no-ff release/image-v1`，再跑一次上面的 pytest，`git push origin main`；`git switch release/image-v1 && git merge --ff-only main`。
- [ ] 客戶端：`git -C ~/src/oh-im-smart-client switch main && git -C ~/src/oh-im-smart-client pull --ff-only`；`git -C ~/src/oh-im-smart-client rev-parse --short=7 main` 印 `1282847`（測試紀錄的那個 commit；不同就停下）；`grep -n "^__version__" ~/src/oh-im-smart-client/thinksmart_client/__init__.py` 印 `__version__ = '1.0.0'`；`git -C ~/src/oh-im-smart-client status --porcelain` 沒有輸出。

### Task 2: 擷取用的 SSH key

`pull-from-device.sh` 只用 README 4.2 的專用 key 和 known hosts。

- [ ] 建立並授權（UM 已能以 `id_ed25519` 登入母機，所以不需要密碼）：

```bash
[ -f ~/.ssh/thinksmart_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/thinksmart_ed25519
ssh ubuntu@192.168.50.181 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys' < ~/.ssh/thinksmart_ed25519.pub
ssh-keyscan -t ed25519 192.168.50.181 2>/dev/null > /tmp/ts.keyscan
ssh-keygen -lf /tmp/ts.keyscan | grep -q 'SHA256:Hmnq2rurIUXjHyvSs7ipwuhHdG79NF70HLlJY70f21s' && cat /tmp/ts.keyscan >> ~/.ssh/known_hosts_thinksmart
TS_HOST=192.168.50.181 sh ts.sh true && echo ts-ok
```

Expected：`ts-ok`。指紋不符就停下（不加入 known hosts）。擷取結果裏的 `authorized_keys` 由 sanitize 清除（spec §5.4），打包檢查會確認。

### Task 3: 母機準備（spec §5.3 第 6 點）

- [ ] **記下母機現狀**：

```bash
mkdir -p ~/tsimg/mother-before && chmod 700 ~/tsimg/mother-before
ssh ubuntu@192.168.50.181 'sudo cat /etc/thinksmart-update.conf' > ~/tsimg/mother-before/thinksmart-update.conf
ssh ubuntu@192.168.50.181 'sudo cat /var/lib/thinksmart-update/status.json' > ~/tsimg/mother-before/status.json
ssh ubuntu@192.168.50.181 'git -C ~/xiaozhi-hub-server rev-parse HEAD; git -C ~/xiaozhi-hub-server status --porcelain | head -20' > ~/tsimg/mother-before/gateway.txt
ssh ubuntu@192.168.50.181 'git -C ~/xiaozhi-hub-server config --get-regexp "^(extensions\.|core\.sparsecheckout|remote\..*\.partialclonefilter|remote\..*\.promisor)"; git -C ~/xiaozhi-hub-server remote -v' > ~/tsimg/mother-before/gateway-git.txt
ssh ubuntu@192.168.50.181 'find ~/.config/systemd/user -type l -printf "%p -> %l\n"' > ~/tsimg/mother-before/user-units.txt
```

- [ ] **更新來源**（第 1 步）：

```bash
scp update/thinksmart-update.conf ubuntu@192.168.50.181:/tmp/thinksmart-update.conf
ssh ubuntu@192.168.50.181 'sudo install -m 644 -o root -g root /tmp/thinksmart-update.conf /etc/thinksmart-update.conf && rm /tmp/thinksmart-update.conf && grep ^SOURCES /etc/thinksmart-update.conf'
```

Expected：`SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"`。
- [ ] **網關**（第 2、3 步）：`gateway.txt` 的 `status --porcelain` 有輸出（未 commit 的改動）就停下回報。`gateway-git.txt` 有任何 `extensions.`、`core.sparsecheckout`、`partialclonefilter` 或 `promisor` 行也停下回報（Task 4 之前，安全）：上游 `bootstrap.sh` 用 `--filter=blob:none --sparse` clone，這種 checkout `image/clean-hub-git.sh` 會拒絕，打包要到 Task 7 才失敗；改用 spec §5.3 第 6 點第 2 步的另一條路（在旁邊重新完整 clone，搬 `data/`、`.venv`、模型）由維護者決定，另寫計劃。沒有的話，在母機上執行映像計劃 Task 8 那段網關指令（`set -e` 的子 shell：`set-url`、`fetch`、`merge-base --is-ancestor`、`checkout main`、`merge --ff-only`、比對 `HEAD`、重啟），之後補上 spec §5.3 第 6 點寫明、那段指令沒有的 `git -C ~/xiaozhi-hub-server branch -u origin/main main`。spec 的 `scripts/update.sh`（拉新版、裝依賴、重啟）這次不另外跑：手動 merge 之後它只會說已是最新；`git diff --stat 6490e88 2d067d9` 沒有依賴或安裝腳本的改動，所以沒有要裝的東西，重啟已由那段指令做了。Expected：印出 `gateway on origin/main`。`merge-base --is-ancestor` 失敗就停下回報，spec §5.3 第 6 點第 2 步的另一條路（在旁邊重新 clone、搬 `data/`）由維護者決定。
- [ ] 確認：網關 `git rev-parse HEAD` 等於 `oh-im-smart-gateway` 的 `main`（`2d067d9…`），`git rev-parse --abbrev-ref main@{upstream}` 印 `origin/main`；`systemctl --user is-enabled xiaozhi-hub.service` 印 `enabled`；一分鐘後 `curl -s http://192.168.50.181:16688/admin | grep -o '<title>[^<]*'` 印 `<title>小智 Hub 管理后台`。

### Task 4: 線上更新 Release（客戶端 1.0.0、系統層 1.0.0）

`CV=1.0.0 SV=1.0.0`，標籤 `TAG=c$CV-s$SV`（變數只為了指令好讀；這份計劃只發這一版）。

- [ ] 在 UM 先打簽署過的標籤（這一步中途停下再做時已有就沿用，並確認指向對的 commit），再產生發佈物（`main` 已含 Task 1）：

整段在 `( set -e … )` 裏跑：任何一個檢查不通過，後面都不做（沒有印 `tags-ok` 就停下）。

```bash
( set -e
CV=1.0.0 SV=1.0.0; TAG=c$CV-s$SV
cd ~/Projects/ohimsmart
git switch main
test -z "$(git status --porcelain)"
grep -qx "$SV" VERSION
grep -q "^__version__ = '$CV'" ~/src/oh-im-smart-client/thinksmart_client/__init__.py
rm -rf ~/tsimg/release
git rev-parse -q --verify "refs/tags/system-v$SV" >/dev/null || git tag -s -m "Oh I'm Smart system layer $SV" "system-v$SV" main
git tag -v "system-v$SV"
git -C ~/src/oh-im-smart-client rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
    || git -C ~/src/oh-im-smart-client tag -s -m "Oh I'm Smart client $CV, system layer $SV" "$TAG" main
git -C ~/src/oh-im-smart-client tag -v "$TAG"
test "$(git -C ~/src/oh-im-smart-client rev-parse "$TAG^{commit}")" = "$(git -C ~/src/oh-im-smart-client rev-parse main)"
test "$(git rev-parse "system-v$SV^{commit}")" = "$(git rev-parse main)"
echo tags-ok
cat > ~/tsimg/make-release.sh <<'EOF'
cd ~/Projects/ohimsmart || exit 1
python3 update/make-release.py ~/src/oh-im-smart-client ~/tsimg/release --system . \
    --note "Oh I'm Smart 1.0.0：繁體中文、简体中文、English 介面；更新來源改為 ohimsmart" \
    --system-note "Oh I'm Smart 系統層 1.0.0：三語歡迎頁和螢幕鍵盤、更新來源改為 ohimsmart、NTP 五個伺服器、接近感應服務檔"
EOF
sg docker -c 'bash ~/tsimg/make-release.sh'
echo "exit $?"
find ~/tsimg/release -type f | sort
cat ~/tsimg/release/release-$TAG.txt
)
```

- [ ] 確認：前面印出 `tags-ok`；`exit 0`；輸出沒有 `tagged … as system-v…`（沿用已簽署的標籤）；`~/tsimg/release/latest/download/latest.json` 的客戶端版本是 `$CV`、系統層版本是 `$SV`；`release-$TAG.txt` 的標籤是 `$TAG`，列出的每個檔名都在 `~/tsimg/release/download/$TAG/` 或 `~/tsimg/release/latest/download/`。
- [ ] **問維護者**：列出要推送的兩個標籤（客戶端 repo 的 `$TAG`、本 repo 的 `system-v$SV`，各自指向的 commit）、Release 的標題、說明、要上傳的檔案（完整路徑），以及背景裏網關那 5 個環境造成的測試失敗。同意後（說明存成 `~/tsimg/release/notes.md`）：

```bash
CV=1.0.0 SV=1.0.0; TAG=c$CV-s$SV   # 上一段的變數只在它的子 shell 裏
git -C ~/src/oh-im-smart-client push origin "$TAG"
git push origin "system-v$SV"
gh release create "$TAG" -R ohimsmart/oh-im-smart-client --verify-tag \
    --title "<release-$TAG.txt 的標題>" --notes-file ~/tsimg/release/notes.md --latest \
    ~/tsimg/release/download/$TAG/* ~/tsimg/release/latest/download/latest.json
```

（`system-v$SV` 已推送過的話 `git push` 印 `Everything up-to-date`。）
- [ ] `curl -sL https://github.com/ohimsmart/oh-im-smart-client/releases/latest/download/latest.json | cmp - ~/tsimg/release/latest/download/latest.json` 沒有輸出。

### Task 5: 母機經線上更新裝上這一版（spec §5.6 第 3 步）

- [ ] 母機 `sudo thinksmart-update check`；`status.json` 的 `available.version` 是 `1.0.0`、`system.available.version` 是 `1.0.0`；`system.available` 沒有 `missing`（有的話停下回報缺哪些套件）；沒有 `check_error`。記下當時 `job` 的 `state` 和 `version`（上一次的結果）。
- [ ] **維護者**在客戶端設定頁「軟體更新」點「更新」，出現「取代自訂版本」時確認。助手每 30 秒看一次 `sudo cat /var/lib/thinksmart-update/status.json` 的 `job`，等它換成這一次的工作（跟上一步記下的不同）且 `state` 不再是進行中。
- [ ] Expected：`job.state` 是 `done`；`current` 是 `$CV`、`system.current` 是 `$SV`；`sudo thinksmart-update system-verify` 的版本是 `$SV`、檔案集合 id 等於 `latest.json` 的系統層 `tree`；`sudo thinksmart-update selftest` 印 `thinksmart-update 3`。處理請求的是母機原本的 `57e4138` 更新器：訊息是「已更新到 系统层 1.0.0 · 客户端 1.0.0」，沒有 `msg_key`。
- [ ] **維護者**重啟母機一次（舊更新器不寫 `job.reboot`，所以一律重啟，讓只在開機讀的檔案生效）。重啟後展示屏停在三語選擇（背景：正常），維護者點任一語言。
- [ ] **維護者**在實機確認：歡迎頁、客戶端、螢幕鍵盤正常；喚醒和一輪對話正常。助手確認：`journalctl -u thinksmart-client -b --no-pager -p warning` 沒有新的錯誤；`systemctl --user is-active vcnl4200-proximity-daemon.service` 是 `active`，`systemctl --user show -p FragmentPath vcnl4200-proximity-daemon.service` 是 `/home/ubuntu/.config/systemd/user/vcnl4200-proximity-daemon.service`；`sudo thinksmart-update system-verify` 仍是 `$SV`、同一個 `tree`。
- [ ] `/var/lib/thinksmart-update/` 裏沒有 `pending.json`、`system-pending.json`。

### Task 6: 線上更新回復測試（spec §9）

固定的工作目錄 `~/tsimg/rb`，每一步可以單獨重做；中途停下時照最後兩步（記錄、還原）做。

- [ ] **測試用發佈物**（永不發佈）：

寫成 `set -eu` 的腳本，重做時先拆掉上一次的 worktree 和標籤；改檔之前確認目前目錄是測試 worktree，不是本 repo：

```bash
mkdir -p ~/tsimg/rb-scripts
cat > ~/tsimg/rb-scripts/setup.sh <<'EOF'
set -eu
REPO=$HOME/Projects/ohimsmart WT=$HOME/tsimg/rb/src
git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true
git -C "$REPO" worktree prune
git -C "$REPO" tag -d system-v99.0.0 2>/dev/null || true
rm -rf "$HOME/tsimg/rb" && mkdir -p "$HOME/tsimg/rb"
git -C "$REPO" worktree add --detach "$WT" main
cd "$WT"
test "$(git rev-parse --show-toplevel)" = "$WT"
test "$(git rev-parse --abbrev-ref HEAD)" = HEAD
echo 99.0.0 > VERSION
sed -i 's|^\[Service\]$|[Service]\nExecStartPre=/bin/false|' screen/screen-wake.service
[ "$(grep -c '^ExecStartPre=/bin/false$' screen/screen-wake.service)" = 1 ]
git -c user.name=test -c user.email=test@invalid -c commit.gpgsign=false commit -qam "TEST ONLY: a system layer that fails its self-test"
git tag -s -m "TEST ONLY, never pushed" system-v99.0.0
python3 update/make-release.py "$HOME/src/oh-im-smart-client" "$HOME/tsimg/rb/out" --system . --note test --system-note test
echo setup-ok
EOF
sg docker -c 'bash ~/tsimg/rb-scripts/setup.sh'; echo "exit $?"
git -C ~/Projects/ohimsmart log -1 --format=%s main   # 不是 TEST ONLY 那個 commit
```

Expected：`setup-ok`、`exit 0`；本 repo 的 `main` 沒有動。這個 commit 只在分離的 worktree 上，不推送；標籤 `system-v99.0.0` 在本 repo 的標籤裏（worktree 共用），還原時刪掉，永不推送。
- [ ] **接上測試來源**（兩個都用 `setsid nohup` 脫離目前的 shell，PID 寫進檔案；重做這一步時先停掉上一次的；兩端都確認拿得到清單才往下）：

```bash
for p in ~/tsimg/rb/http.pid ~/tsimg/rb/tunnel.pid; do [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
setsid nohup python3 -m http.server 8765 --bind 127.0.0.1 --directory ~/tsimg/rb/out > ~/tsimg/rb/http.log 2>&1 < /dev/null & echo $! > ~/tsimg/rb/http.pid
setsid nohup ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -R 8765:127.0.0.1:8765 ubuntu@192.168.50.181 > ~/tsimg/rb/tunnel.log 2>&1 < /dev/null & echo $! > ~/tsimg/rb/tunnel.pid
for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf http://127.0.0.1:8765/latest/download/latest.json > /dev/null && break; sleep 1; done
ssh ubuntu@192.168.50.181 'for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf http://127.0.0.1:8765/latest/download/latest.json > /dev/null && echo tunnel-ok && break; sleep 1; done'
ssh ubuntu@192.168.50.181 'sudo thinksmart-update system-verify' > ~/tsimg/rb/verify-before.txt
ssh ubuntu@192.168.50.181 'sudo sed -i "s|^SOURCES=.*|SOURCES=\"http://127.0.0.1:8765/\"|" /etc/thinksmart-update.conf && sudo thinksmart-update check && sudo python3 -c "import json; s=json.load(open(\"/var/lib/thinksmart-update/status.json\")); print(s[\"system\"][\"available\"])"'
```

Expected：印出 `tunnel-ok`（沒印就停下，看兩個 log）；最後印出的 `available` 的 `version` 是 `99.0.0`，沒有 `missing`。
- [ ] **安裝**（跟頁面一樣放一個請求檔；先寫成 `.` 開頭的暫存檔再改名）：

```bash
ssh ubuntu@192.168.50.181 'cd /var/lib/thinksmart-update/requests && printf "{\"action\": \"install\", \"system\": \"99.0.0\"}" > .rb.tmp && mv .rb.tmp rb.json'
```

助手每 15 秒看一次 `status.json` 的 `system` 和 `job`，等 `job.version` 變成 `99.0.0`（Task 5 留下的 `done`/1.0.0 不算），而且 `state` 不再是進行中（最多 5 分鐘）。
- [ ] Expected：`job.state` 是 `rolled_back`、`component` 是 `system`，訊息說系統層 99.0.0 沒裝成功、`screen-wake.service` 沒有正常運行、已退回 1.0.0；`sudo thinksmart-update system-verify` 的輸出跟 `verify-before.txt` 相同；`systemctl is-active screen-wake.service` 是 `active`；`grep -c ExecStartPre=/bin/false /etc/systemd/system/screen-wake.service` 是 `0`；`system.current` 仍是 `1.0.0`。
- [ ] **記錄**（清除狀態之前）：`ssh ubuntu@192.168.50.181 'sudo cat /var/lib/thinksmart-update/status.json' > ~/tsimg/rb/status-after.json`，`ssh ubuntu@192.168.50.181 'sudo thinksmart-update system-verify' > ~/tsimg/rb/verify-after.txt`；把 `job` 和兩次 `system-verify` 寫進 `~/tsimg/record.md`。
- [ ] **還原和清理**（中途停下時也做這一步）。次序有關係：更新器開始安裝時把 `/etc/thinksmart-update.conf`（`system-files.txt` 的 keep 行）連同其他檔案一起備份，那時它指向測試來源；中斷的安裝由 `recover()` 在鎖底下退回，會把這份備份放回去；而且 `main()` 在拿鎖之前就讀了設定。所以先讓退回做完（測試來源和隧道仍在），再換設定，最後才拆隧道：

```bash
# 1. 刪請求（鎖底下，等正在跑的更新器做完），再跑一次 check 讓 recover() 做完任何中斷的工作
ssh ubuntu@192.168.50.181 'sudo flock /run/thinksmart-update.lock rm -f /var/lib/thinksmart-update/requests/rb.json && sudo thinksmart-update check; sudo test ! -e /var/lib/thinksmart-update/system-pending.json && sudo test ! -e /var/lib/thinksmart-update/pending.json && echo recovered'
# 2. 印了 recovered 才做：鎖底下換回正式來源、刪狀態檔；放開鎖之後 check，再確認磁碟上的來源
scp ~/Projects/ohimsmart/update/thinksmart-update.conf ubuntu@192.168.50.181:/tmp/thinksmart-update.conf
ssh ubuntu@192.168.50.181 'sudo flock /run/thinksmart-update.lock sh -c "install -m 644 -o root -g root /tmp/thinksmart-update.conf /etc/thinksmart-update.conf && rm -f /var/lib/thinksmart-update/status.json" && rm /tmp/thinksmart-update.conf && sudo thinksmart-update check; grep ^SOURCES /etc/thinksmart-update.conf; sudo cat /var/lib/thinksmart-update/status.json'
# 3. 上一步的 SOURCES 是 ohimsmart 那一行才拆測試來源
kill "$(cat ~/tsimg/rb/http.pid)" "$(cat ~/tsimg/rb/tunnel.pid)" 2>/dev/null
git -C ~/Projects/ohimsmart worktree remove --force ~/tsimg/rb/src; git -C ~/Projects/ohimsmart worktree prune; git -C ~/Projects/ohimsmart tag -d system-v99.0.0
```

第 1 步沒印 `recovered`：停下回報（不換設定、不拆隧道）。第 2 步的 `SOURCES` 不是 `SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"`：重做第 2 步，不拆隧道。

Expected：母機 `status.json` 的 `current` 和 `system.current` 都是 `1.0.0`，`available` 和 `system.available` 都是 `null`，沒有 `check_error`（正式清單沒有被當成「比較舊」）；`git tag -l 'system-v99*'` 沒有輸出；`git worktree list` 只有本 repo。

### Task 7: 擷取、測試映像、允許清單（映像計劃 Task 8）

- [ ] **維護者**寫 `~/tsimg/secrets.txt`（權限 600）：維護者的電郵、母機用過的 WiFi 名稱、網關後台設定過的每一個 API key、母機原本的主機名稱 `thinksmarter`。助手不讀這個檔。
- [ ] 先 `git switch release/image-v1 && git merge --ff-only main`（任何 repo 改動都在這個分支上做）。
- [ ] 照映像計劃 Task 8 的「擷取和打包測試映像」做，`TS_HOST=192.168.50.181`、`--test-image`；再做「逐行看 sanitize 刪掉了甚麼」，照失敗處理表（加上背景裏寫明的不同）處理。用到 Docker 的指令（含 `set -o pipefail` 和 `tee`）照抄進 `~/tsimg/test-image.sh`，以 `sg docker -c 'bash ~/tsimg/test-image.sh'` 跑。
- [ ] **Commit（不用映像計劃 Task 8 的 Commit 區塊**：它 `git add` 的服務檔和 `system-files.txt` 已在本計劃 Task 1 commit 過）：`git status --porcelain` 沒有輸出就跳過；否則 `git add` 列出的那些檔案（清單、sanitize、check-rootfs、測試），Litmus 後 `git commit -m "Image allowlists and sanitize: what the first capture needed"`（訊息照實寫改了甚麼）。需要改 `SYSTEM_DIRS` 的話照 Global Constraints 停下（不 commit，另寫計劃）。
- [ ] 照 Task 8「用正式的秘密檔再跑一次」，指令不變（`ALLOW_UNRELEASED=1`，產物仍是 `-TEST-DO-NOT-PUBLISH`，只用來檢查秘密檔），同樣寫成腳本經 `sg` 跑；每一項計數 0。
- [ ] 跑 Task 1 的測試（pytest 和 `~/tsimg/image-tests.sh`），全部通過。
- [ ] 有 commit 的話：merge 到 `main`（`--no-ff`），測試，`git push origin main`；`release/image-v1` 跟上 `main`。
- [ ] 把整個映像的私人資料掃描花的時間寫進 `~/tsimg/record.md`。

### Task 8: 正式映像，pre-release（spec §5.6 第 4 步）

**名稱：** `<ID>` 是 `<YYYYMMDD>`；同一天已有 `image-<YYYYMMDD>` 標籤（`git ls-remote --tags origin "image-<YYYYMMDD>*"`，本機 `git tag -l` 也看），就用第一個沒用過的 `<YYYYMMDD>.2`、`<YYYYMMDD>.3`…。下文的檔名和標籤都用 `<ID>`。

- [ ] `git switch main && [ -z "$(git status --porcelain)" ] && echo clean` 印 `clean`。母機在 Task 7 之後沒有改動的話直接用那次擷取（`~/tsimg/work`），否則重新擷取。正式打包（唯一一次不帶 `TEST` 的建置）：

```bash
rm -rf ~/tsimg/final
cat > ~/tsimg/final.sh <<'EOF'
cd ~/Projects/ohimsmart || exit 1
IMAGE_NAME=thinksmart-ubuntu-<ID> RELEASE_MANIFEST=$HOME/tsimg/release/latest/download/latest.json image/build-image.sh \
    ~/tsimg/work ~/tsimg/final ~/src/oh-im-smart-gateway ~/tsimg/secrets.txt
EOF
sg docker -c 'bash ~/tsimg/final.sh > ~/tsimg/final.log 2>&1'; echo "exit $?"
tail -20 ~/tsimg/final.log
```

Expected：`exit 0`；`~/tsimg/final/` 有 `thinksmart-ubuntu-<ID>.img.xz`（名稱沒有 `TEST`）、`SHA256SUMS`、`packages.txt`；`cd ~/tsimg/final && sha256sum -c --ignore-missing SHA256SUMS` 對 `.img.xz` 印 `OK`（`SHA256SUMS` 也有解壓後 `.img` 那一行，那個檔不在這裏，`build-image.sh:257` 和教學都用 `--ignore-missing`）。
- [ ] **GPL 原始碼：** 從 `https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/ed3f995f/device/community/linux-postmarketos-qcom-msm8953/APKBUILD` 取得 tarball 的網址和 sha512，下載到 `~/tsimg/gpl/`；`sha512sum` 跟 APKBUILD 相同才用。打包：

```bash
cd ~/Projects/ohimsmart
tar -cf ~/tsimg/gpl/oh-im-smart-gpl-sources-<ID>.tar --owner=0 --group=0 --numeric-owner --exclude=codec-dmic/out \
    -C ~/tsimg/gpl linux-postmarketos-qcom-msm8953-v6.19.5-r0.tar.gz \
    -C ~/Projects/ohimsmart kernel/config-postmarketos-qcom-msm8953.aarch64 kernel/build.sh kernel/Dockerfile kernel/README.md \
    kernel/alpine-minirootfs-3.22.7-aarch64.tar.gz.sha256 codec-dmic
cp ~/tsimg/gpl/oh-im-smart-gpl-sources-<ID>.tar ~/tsimg/final/
# build-image.sh 的 SHA256SUMS 是 Docker 以 root 寫的，不能附加；目錄是自己的，所以寫一份新的再換上。
# head -n 2 留下 build-image.sh 寫的兩行（.img.xz 和 .img），重做時不會重複。
{ head -n 2 ~/tsimg/final/SHA256SUMS
  ( cd ~/tsimg/gpl && sha256sum linux-postmarketos-qcom-msm8953-v6.19.5-r0.tar.gz )
  ( cd ~/tsimg/final && sha256sum oh-im-smart-gpl-sources-<ID>.tar packages.txt ); } > ~/tsimg/final/SHA256SUMS.new
mv -f ~/tsimg/final/SHA256SUMS.new ~/tsimg/final/SHA256SUMS
( cd ~/tsimg/final && sha256sum -c --ignore-missing SHA256SUMS )
```

Expected：`SHA256SUMS` 五行（第一行是 `.img.xz`、第二行是 `.img`，打包前先 `head -n 2` 看一次確認）；`.img.xz`、GPL tar、`packages.txt` 三行 `OK`。內核 tarball 那一行（spec §5.6 要的 sha256）在 tar 裏面，解開後同樣可用 `sha256sum -c --ignore-missing` 驗；它的 sha256 也寫進說明。

- [ ] **說明**存成 `~/tsimg/final/notes.md`：

```markdown
Oh I'm Smart <CV> (<ID>) — pre-release, acceptance in progress

- Client <CV> (ohimsmart/oh-im-smart-client, release c<CV>-s<SV>)
- Gateway ohimsmart/oh-im-smart-gateway @ <commit>
- System layer <SV> (tag system-v<SV>)
- Packed from ohimsmart/oh-im-smart @ <commit>
- <bytes> bytes unpacked, <bytes> bytes compressed
- Kernel linux-postmarketos-qcom-msm8953 6.19.5-r0 (GPL-2.0): the source tarball linux-postmarketos-qcom-msm8953-v6.19.5-r0.tar.gz (sha256 <sha256>), the kernel config, kernel/build.sh, kernel/Dockerfile and codec-dmic/ are attached as oh-im-smart-gpl-sources-<ID>.tar; both sha256 are in SHA256SUMS
- packages.txt: the packages in the image

Check the download with `sha256sum -c --ignore-missing SHA256SUMS`.
Flashing guide: README.md (简体中文), README.zh-Hant.md (繁體中文), README.en.md (English).
```

- [ ] **問維護者**（標籤 `image-<ID>`、目標 commit、標題、說明、四個檔案）。同意後，先簽署並推送標籤，再建 Release：

```bash
git tag -s -m "Oh I'm Smart <CV> (<ID>)" image-<ID> main && git tag -v image-<ID>
git push origin image-<ID>
gh release create image-<ID> -R ohimsmart/oh-im-smart --verify-tag --prerelease \
    --title "Oh I'm Smart <CV> (<ID>)" --notes-file ~/tsimg/final/notes.md \
    ~/tsimg/final/thinksmart-ubuntu-<ID>.img.xz ~/tsimg/final/SHA256SUMS ~/tsimg/final/packages.txt ~/tsimg/final/oh-im-smart-gpl-sources-<ID>.tar
```

- [ ] 從 Release 下載四個檔案到新的空目錄，`sha256sum -c --ignore-missing SHA256SUMS` 的 `.img.xz`、GPL tar、`packages.txt` 三行都是 `OK`。
- [ ] **刪掉 C16 那句**（5a 約定：pre-release 發佈後）：三份教學各刪一句（简中「第一个 Oh I'm Smart 镜像还在准备中，Releases 页面暂时是空的；发布后这句会删掉。」、繁中「第一個 Oh I'm Smart 映像還在準備中，Releases 頁面暫時是空的；發布後這句會刪掉。」、英文 “The first Oh I'm Smart image is still being prepared, so the Releases page is empty for now; this sentence goes once it is published.”），`tools/check-readmes.sh` 通過；在 `release/image-v1` 上 Litmus 後 commit，merge 到 `main`（`--no-ff`），`git push origin main`。（只改 README，不在 `SYSTEM_DIRS` 裏，已發佈的映像和系統層不受影響。）

### Task 9: 驗收（spec §9），改為 Latest

- [ ] **維護者**照**繁中教學** 4.1 備份母機（`userdata.tar`）。重刷之前，助手在存放備份的那部電腦上確認備份完整（教學那行指令用 `--ignore-failed-read`，`tar` 讀不到的檔案會默默略過，所以要逐項查）：

```bash
tar -tf userdata.tar > userdata-list.txt && echo readable
grep -c thinksmart-client userdata-list.txt
grep -qx 'home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/data/.config.yaml' userdata-list.txt && echo gateway-config
grep -q '^etc/NetworkManager/system-connections/.' userdata-list.txt && echo wifi
grep -qx 'etc/ssh/ssh_host_ed25519_key' userdata-list.txt && echo hostkeys
```

Expected：印 `readable`、`gateway-config`、`wifi`、`hostkeys`，計數大於 0。缺任何一項就不重刷，停下回報。另外 Task 7 的擷取 `~/tsimg/work` 留到驗收通過才刪，是重刷前母機的第二份完整副本。
- [ ] **維護者**照繁中教學路線 B（B2、B3）刷 Task 8 那個 pre-release 的映像（教學說「最新版」，但改為 Latest 之前 Releases 的最新版指的就是這個 pre-release 頁面，用它的檔案和下載地址）；然後做第 2 節首次設定。助手照教學的「給 AI 助手的說明」陪同，寫入步驟照教學先問。
- [ ] 下列各項在首次設定**進行到那一步時**當場確認（第 1、7 項是一次性的，做過就沒法重來），每項在 `~/tsimg/record.md` 寫「通過」或失敗的情形：
  1. 第 2.1 節開機出現三語選擇；選 English 後歡迎頁、客戶端、螢幕鍵盤都是英文；（全部設定完後）重開機仍是英文。
  2. 網關後台在英文瀏覽器上以英文顯示。
  3. ASR 和 TTS 分別用不同的 API key 和網址儲存。
  4. 說話語言切換為 `yue-HK` 對話一輪；再切換為 `en` 對話一輪。
  5. 在英文後台新增一個 MCP server，顯示正常。
  6. 後台檢查更新顯示「已是最新」；`/etc/thinksmart-update.conf` 的來源和網關的 remote 都指向 `ohimsmart`。
  7. 第 2.5 節：`ubuntu` 用預設密碼登入，可以改密碼；之後 `sudo grep '^root:' /etc/shadow` 的第二欄以 `!` 開頭；`timedatectl` 可以設時區。
- [ ] 全部通過：把 `~/tsimg/final/notes.md` 第一行的 “pre-release, acceptance in progress” 改成 “acceptance passed (spec §9)”；**問維護者**，同意後 `gh release edit image-<ID> -R ohimsmart/oh-im-smart --prerelease=false --latest --notes-file ~/tsimg/final/notes.md`。
- [ ] 任何一項不通過：不改 Latest，pre-release 留着；記錄情形，照 Global Constraints 停下回報。修正寫成新的計劃，它要處理：以新版本號發佈、重刷過的母機重新接上（新的主機金鑰、清空的 `authorized_keys`、首次設定存的新 API key 和 WiFi 要加進 `secrets.txt`）、網關修正怎樣到母機、新映像的 `<ID>`。

### Task 10: 實作記錄、merge、push

- [ ] 把 `~/tsimg/record.md` 整理成本計劃末尾的「實作記錄」：每個 repo 的 commit、Release 的標籤和網址、標籤保護的決定、測試數字、回復測試的結果、映像大小和私人資料掃描的時間、驗收結果、偏離計劃的地方。
- [ ] plan doc 單獨 commit（Litmus），merge 到 `main`（`--no-ff`），再跑一次 Task 1 的 pytest，`git push origin main`。

## 實作記錄

2026-11-16 至 2026-11-19。

**Commit**
- ohimsmart（本 repo，`main`）：`bb69fa2` 測試修正、`6892d92` 系統層 1.0.0、`a439a8c` 本計劃，merge `02a4503`；`b2ce750` 網關完整 checkout 計劃，merge `27debd2`；`c56f67f` 擷取修正、`577b793` 私人資料掃描不算 GnuTLS 自測 key，merge `2edeada`；`e2d161a` README 拿掉「Releases 頁是空的」，merge `bc37f8f`。
- 客戶端 `ohimsmart/oh-im-smart-client`：`1282847`（1.0.0）。網關 `ohimsmart/oh-im-smart-gateway`：`main` = `2d067d94`，母機和映像都是這個 commit。

**Release 和標籤**
- 線上更新：標籤 `system-v1.0.0` → `27debd2`、`c1.0.0-s1.0.0` → 客戶端 `1282847`，都有簽名；https://github.com/ohimsmart/oh-im-smart-client/releases/tag/c1.0.0-s1.0.0 ，`latest.json` 和本機建出的逐位元組相同。
- 映像：簽名標籤 `image-20261118` → `2edeada`（ED25519，`git tag -v` 通過）；https://github.com/ohimsmart/oh-im-smart/releases/tag/image-20261118 。先以 pre-release 發佈，驗收全部通過後經維護者同意改為正式版並設為 Latest（`/releases/latest` 指向它）。四個檔案：`thinksmart-ubuntu-20261118.img.xz` 966092768 bytes（解壓後 3804233728 bytes）、`oh-im-smart-gpl-sources-20261118.tar` 258232320 bytes、`packages.txt`（780 個套件）、`SHA256SUMS`；從 Release 重新下載後 `sha256sum -c --ignore-missing SHA256SUMS` 3 個 OK（清單另外列了解壓後的 `.img` 和 GPL 包裏的 kernel 原始碼，只下載四個檔案時這兩項不在）。
- 標籤保護（Task 0）：維護者開了 2FA，同意三個 ruleset（27385950、27385951、27385953），啟用，bypass 清單為空。

**測試**
- 本 repo：pytest 175 passed（update、kiosk、bootstrap、tools、screen）；映像測試 sanitize / privacy / build 都 exit 0；`test-image-privacy` 54/54。
- 已發佈的客戶端 `1282847`：pytest 179 passed、node 16 passed。網關 `2d067d9`：765 passed、5 failed、5 skipped，5 個失敗都來自測試環境（`tests/test_stt.py` 4 項要本地語音辨識模型，`test_missing_packages_real_providers` 要真實 provider 的套件）；Task 0 / Task 4 列給維護者，維護者同意連同這 5 個一起發佈（spec §9 沒有例外，這是維護者的決定）。驗收第 3、4 項在母機上用真實的語音 API 對話通過。
- `test_idle_blanker` 偶發失敗兩次（假背光檔在 truncate 和寫入之間讀到空值），修在測試 harness（`bb69fa2`），之後連續 3 次乾淨。

**線上更新與回復（Task 5、6）**
- 母機從 0.1.6 線上更新到客戶端 1.0.0、系統層 1.0.0；`system-verify` 的 tree hash 和 `latest.json` 相同；重開機後沒有失敗的 unit，維護者確認歡迎頁、客戶端、鍵盤、喚醒、對話正常。
- 回復測試：只在本機的系統層 99.0.0（`screen-wake.service` 故意起不來）裝上後自動退回 1.0.0，訊息「系统层 99.0.0 没装成功（screen-wake.service 没有正常运行），已退回 1.0.0」，前後 `system-verify` 相同，不需要重開機。99.0.0 的標籤只在本機，已刪除，沒有推送。

**映像建置與私人資料掃描（Task 7、8）**
- 擷取母機（root 1.2G、boot 28M，zstd）後建置。root 檔案系統 3378 MB、200000 inodes，剩 527 MB；保留 2 個 capability（`ping`、`gst-ptp-helper`）。
- 四次私人資料掃描（檔案樹、boot 檔、initramfs、整個 disk.img）都通過；ssh key、PEM 私鑰、`sk-` / `xai-` key 都是 0，`secrets.txt` 的每一行（Wi-Fi 名稱和密碼、網關 key、維護者 e-mail、舊主機名）在每次掃描都是 0。GnuTLS 內建的 10 個自測 key 以整塊 sha256 列在 `image/known-pem-blocks.txt`，不計入。整個映像掃描 31 秒。

**驗收（Task 9，spec §9）**
- 刷機前備份（教學 4.1）通過：`userdata.tar` 39 個項目，有網關設定、主機金鑰和 Wi-Fi（netplan 檔，見下面的偏離）。
- 維護者照教學路線 B 用 edl 3.62（bkerler/edl `1cda1a6`）刷入從 Release 下載的映像：寫在 sector 923648（`system` 分割區 0x1c300000），0x716000 sectors，等於映像大小。
- 七項都通過：
  1. 三語選擇，選 English 後歡迎頁、客戶端、螢幕鍵盤都是英文；全部設定完重開機仍是英文。
  2. 網關後台在英文瀏覽器上是英文。
  3. ASR 和 TTS 用不同的 key 和網址儲存並使用。
  4. `yue-HK`、`en` 各對話一輪。
  5. 英文後台新增 MCP server（預填的 JSON）後正常顯示，之後刪除。
  6. 後台檢查更新顯示 “Already up to date”；裝置上 `SOURCES` 是 `https://github.com/ohimsmart/oh-im-smart-client/releases/`，網關 remote 是 `https://github.com/ohimsmart/oh-im-smart-gateway.git`。
  7. `ubuntu` 用預設密碼登入並改了密碼；root 的 shadow 第二欄以 `!` 開頭；`timedatectl` 設成 `Asia/Hong_Kong`。

**偏離計劃的地方**
- Task 3：母機的網關原本是 shallow / partial / sparse clone，`clean-hub-git.sh` 拒絕；另寫 `docs/plans/2026-11-16-hub-full-checkout.md`，在母機上原地改成完整 checkout，取代本計劃 Task 3 的網關步驟。
- Task 7：第一次建置發現的問題（`/usr/lib/ssl` 的目錄連結、預設 ASR 模型目錄、上游網址、帳號殘留、音訊檔）寫成 `docs/plans/2026-11-17-image-capture-fixes.md` 處理；GnuTLS 自測 key 寫成 `docs/plans/2026-11-18-privacy-known-pem.md`，經維護者同意。
- `secrets.txt`：維護者請助手產生；腳本從母機的 netplan 和網關設定（跟範本不同的 key）讀出，加上 git e-mail 和舊主機名，全程沒有印出任何值。
- Task 9 Wi-Fi 檢查：母機的 `system-connections/` 是空的，Wi-Fi 在 `etc/netplan/90-NM-*.yaml`，照設計審查記下的 medium 接受它。
- 刷機用的 edl：在 UM 上由維護者自己安裝（助手的安裝被分類器拒絕）；只裝了 `51-edl.rules`，沒有封鎖 `cdc_acm` / `qcserial`；ModemManager 只停止，沒有停用。

**驗收時發現、留待之後處理**
- 教學缺漏：Linux 路線要先 `apt install python3-dev` 等套件才能裝 edl；`edl reset` 會印 `USBError(5, 'Input/Output Error')`，裝置有重開就沒事；網關 ASR / TTS 頁要按 “Save and use”，只按 “Save” 不會切換；`timedatectl set-timezone` 會要 `ubuntu` 的密碼。
- 網關 MCP 頁要手寫 JSON，維護者覺得不好用：發佈後改成欄位式表單，透過網關線上更新送出，不用重做映像。

## 不在這份計劃裏

- 「刷完後的系統不能用 USB 線登入」：母機（上游映像、系統層 0.1.0）的 `usb0` 是開着的（`172.16.42.1`，2026-11-16 實測），跟 README 附錄的已知問題不符；驗收後在新映像上確認現況，另開議題。
- 母機 `/etc/systemd/user/vcnl4200-proximity-daemon.service` 那份舊檔（`/etc/xdg/systemd/user/` 是同一個）：不在系統層裏，留在映像中，被 `~/.config/systemd/user/` 那份（從它複製來的，內容相同）蓋過，不另外處理。
- 網關後台一鍵設時區（spec §5.5 留待 v1 之後）。
- Windows 上的 Docker 和 `prepare.sh`。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
