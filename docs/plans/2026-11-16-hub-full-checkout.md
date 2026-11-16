# 母機網關改為完整 checkout（計劃 5b 的前置） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把母機 `~/xiaozhi-hub-server` 原地改成指向 `ohimsmart/oh-im-smart-gateway`、停在 `2d067d9`、不是 partial clone、不是 sparse checkout 的 checkout，讓計劃 5b（`docs/plans/2026-11-16-image-release.md`）Task 3 可以繼續，Task 7 打包時 `image/clean-hub-git.sh` 接受它。

**Architecture:** 一個在母機上跑的 `set -eu` 腳本：先做映像計劃 Task 8 那段網關指令（換 origin、fetch、祖先檢查、`checkout main`、`merge --ff-only`）和 spec §5.3 第 6 點的 `branch -u`，再 `git sparse-checkout disable`（git 從 origin 補下 `2d067d9` 缺的檔案內容），然後拿掉 worktree config 和 promisor 設定，逐項檢查，最後重啟網關。之後在母機上用 repo 裏真正的 `clean-hub-git.sh` 對一份副本試跑一次，證明 Task 7 不會因這個 checkout 失敗。全部在 5b Task 4（第一個公開發佈）之前。

**Tech Stack:** bash、git 2.43（母機）、ssh（UM → 母機，UM 的 `id_ed25519` 已授權）。

**Global Constraints:**
- 這份計劃取代 5b Task 3 的「網關」那一步（映像計劃 Task 8 的網關指令和 `branch -u` 都在這裏做）；5b Task 3 的其他步驟（記下現狀，已做；更新來源；最後的確認）照 5b 做。
- 只做這裏寫明的動作；任何一步跟 Expected 不符就停下回報，不臨場發揮。母機的 `data/`、`.venv`、模型留在原處，不搬動。
- 路線由維護者決定（5b Task 3 這樣要求）：2026-11-16 維護者選了「原地改為完整 checkout」，不用 spec §5.3 第 6 點第 2 步「在旁邊重新 clone、搬 `data/`」那條路。
- 不改本 repo 的程式、客戶端、網關 repo 的任何檔案。這份計劃本身在 Task 4 經 Litmus commit 進 `main` 並推送：5b Task 4、Task 8 和 `build-image.sh` 都要求 repo 沒有未 commit 或未追蹤的檔案。
- 紀錄寫進 UM 的 `~/tsimg/record.md`。

---

## 背景：已確認的事實（2026-11-16，SSH 唯讀）

- 母機網關 checkout：HEAD `6490e88`（分支 `device/language-6490e888ebc5`），本機 `main` 在 `4b6eec4`，`git status --porcelain` 沒有輸出。`.git/config`：`remote.origin.promisor = true`、`remote.origin.partialclonefilter = blob:none`、`extensions.worktreeConfig = true`；`.git/config.worktree`：`core.sparseCheckout = true`、`core.sparseCheckoutCone = true`；sparse 清單 `hub-docs`、`main/xiaozhi-server`、`scripts`；有 `.git/shallow`。上游 `bootstrap.sh` 以 `--depth 1 --filter=blob:none --sparse` clone（我們網關的 `scripts/bootstrap.sh:52` 也一樣）。
- `image/clean-hub-git.sh:21-22`：`.git/config` 有任何 `extensions.*` 就失敗。之後它用 `image/hub-git-config` 換掉整個 config（沒有 promisor），刪掉 index，`reset --hard` 指定的 commit，所以 `2d067d9` 每一個檔案的內容都必須已在母機的 `.git` 裏；`.git/shallow` 保留。
- 母機網關的 ref：`main`、`origin/main`、`origin/HEAD` 在 `4b6eec4`，四個 `device/*` 分支在 `6490e88`、`16d4391`、`77376bc`、`e4750c1`；`.git/shallow` 是 `6d8a05f`、`adb936d`；`remote.origin.fetch` 是 `+refs/heads/main:refs/remotes/origin/main`；reflog 5 行。**這些 commit 全都是 `2d067d9` 的祖先**（UM 上的網關 checkout 實測），所以任何 ref 或 reflog 用到的物件都在我們網關的歷史裏，可以從新的 origin 取得。現在缺 1322 個物件（`rev-list --objects --all --reflog --missing=print`）：partial clone 只在需要時才取檔案內容，舊版本的大多沒取過。
- 只取 `2d067d9` 本身的檔案不夠：`clean-hub-git.sh` 的 `gc` 會走 `main` 的整段歷史（到 shallow 邊界），缺物件就失敗；`objects/pack/*.promisor` 標記檔要刪掉，否則 `gc` 會再寫一個，`check-rootfs.sh` 拒絕 `.git` 裏 git 自己不寫的檔案（第 59–73 行）。設計審閱第 1 輪在 git 2.43 上用模擬的母機重現了這兩點，也驗證了下面的做法。`2d067d9` 的完整檔案樹 1734 個檔案、約 187 MB（最大的是 `main/digital-human` 的模型檔）。母機 `/` 剩 3.6 GB；`.venv` 506 MB、`models` 175 MB、`data` 104 KB；git 2.43.0；沒有 `rsync`。
- 被 git 忽略的檔案：`main/xiaozhi-server/.venv/`、各處 `__pycache__/` 等；`data/` 不在 git 裏。
- 映像裏網關的 checkout 一定是完整的（`clean-hub-git.sh` 的 `reset --hard`），所以映像會多出那些 sparse 沒有取出的檔案；這是映像計劃原有的設計，不是這份計劃的改動。

---

### Task 1: 備份 `.git`

- [ ] 在 UM：

```bash
( set -euo pipefail; T=~/tsimg/mother-before/hub-git.tar
  ssh ubuntu@192.168.50.181 'tar -C ~/xiaozhi-hub-server -cf - .git' > $T.partial
  tar -tf $T.partial > /dev/null
  n=$(tar -tf $T.partial | grep -cx '.git/config'); test "$n" = 1
  mv $T.partial $T; echo backup-ok )
```

Expected：`backup-ok`（ssh 和 `tar` 的錯誤都會停下；沒印就不做 Task 2）。這份是母機改動前的 `.git`，出事時跟 5b Task 3 記下的 `gateway.txt` 一起用來回報和還原。

### Task 2: 改為完整 checkout

- [ ] 在 UM 寫腳本，經 ssh 在母機上跑：

```bash
cat > ~/tsimg/hub-full-checkout.sh <<'EOF'
set -euo pipefail
C=2d067d940370eebbf1f0460c32a51c7c02cc5ed7
# 每個檢查先把輸出存進變數：命令失敗時 set -e 停下，不會被當成空的
missing() { git rev-list --objects --all --reflog --missing=print | sed -n 's/^?//p'; }
cd ~/xiaozhi-hub-server
st=$(git status --porcelain); test -z "$st"
git remote set-url origin https://github.com/ohimsmart/oh-im-smart-gateway.git
git fetch origin +refs/heads/main:refs/remotes/origin/main
test "$(git rev-parse origin/main)" = "$C"
git merge-base --is-ancestor HEAD origin/main
git merge-base --is-ancestor main origin/main
git checkout -q main
git merge -q --ff-only origin/main
git branch -u origin/main main
# 取出全部檔案：缺的內容由 git 從 origin（我們的網關）補下
git sparse-checkout disable
# 任何 ref 和 reflog 用到、還沒有的物件，趁 origin 仍是 promisor 一次取回（跟 git 自己按需取用的指令相同）
m=$(missing)
if [ -n "$m" ]; then
    printf '%s\n' "$m" | git -c fetch.negotiationAlgorithm=noop fetch origin --no-tags --no-write-fetch-head \
        --recurse-submodules=no --filter=blob:none --stdin
fi
m=$(missing); test -z "$m"
# 物件齊了才拿掉 partial clone 和 sparse 的設定：之後缺物件就是錯誤
rm -f .git/objects/pack/*.promisor
git config --unset-all remote.origin.promisor || [ $? -eq 5 ]
git config --unset-all remote.origin.partialclonefilter || [ $? -eq 5 ]
git config --unset-all extensions.worktreeConfig || [ $? -eq 5 ]
rm -f .git/config.worktree
cfg=$(git config --get-regexp '^(extensions\.|core\.sparsecheckout|remote\.origin\.promisor|remote\.origin\.partialclonefilter)') || [ $? -eq 1 ]
test -z "${cfg:-}"
if compgen -G '.git/objects/pack/*.promisor' > /dev/null; then echo 'promisor marker left'; exit 1; fi
m=$(missing); test -z "$m"
git fsck --connectivity-only --no-dangling --no-progress
test "$(git rev-parse HEAD)" = "$C"
test "$(git rev-parse --abbrev-ref 'main@{upstream}')" = origin/main
st=$(git status --porcelain --untracked-files=all); test -z "$st"
systemctl --user restart xiaozhi-hub.service
echo hub-full-ok
EOF
ssh ubuntu@192.168.50.181 'bash -s' < ~/tsimg/hub-full-checkout.sh; echo "exit $?"
```

Expected：最後印 `hub-full-ok` 和 `exit 0`。取物件那一步（按物件 id 從 GitHub 取）失敗時腳本在拿掉 promisor 之前就停下，母機仍是原本那種 partial clone，網關照常運作。中途停下（沒有 `hub-full-ok`）：不再跑任何改動母機的指令，記下印出的最後幾行和 `ssh ubuntu@192.168.50.181 'cd ~/xiaozhi-hub-server; git status -sb | head; git config -l --show-origin | grep -v url'`，回報維護者。整段可以重跑（每一步在已完成時都是不改動或可重複的）；重跑只在維護者同意後做。

- [ ] 確認網關正常：`ssh ubuntu@192.168.50.181 'systemctl --user is-active xiaozhi-hub.service; systemctl --user is-enabled xiaozhi-hub.service'` 印 `active`、`enabled`；一分鐘後 `curl -s http://192.168.50.181:16688/admin | grep -o '<title>[^<]*'` 印 `<title>小智 Hub 管理后台`。

### Task 3: 用真正的 `clean-hub-git.sh` 對副本試跑

- [ ] 在 UM（`.venv` 不複製：它整個被 git 忽略，跟這個檢查無關；其餘照原樣，含 `data/` 和模型。副本只在母機上；檢查通過才刪，不通過就留着給回報用，回報後刪）。檢查跟 `check-rootfs.sh` 對網關 `.git` 的檢查相同的幾項（第 59–83 行）：

```bash
cat > ~/tsimg/hub-trial.sh <<'EOF'
set -euo pipefail
C=2d067d940370eebbf1f0460c32a51c7c02cc5ed7
rm -rf ~/hubtest && mkdir ~/hubtest
tar -C ~/xiaozhi-hub-server --exclude=./main/xiaozhi-server/.venv -cf - . | tar -C ~/hubtest -xf -
sh /tmp/hubcheck/clean-hub-git.sh ~/hubtest "$C"
cd ~/hubtest
G() { git -c safe.directory='*' -c core.hooksPath=/dev/null "$@"; }
x=$(find .git/objects .git/refs ! -type d | grep -Ev '^\.git/(objects/pack/pack-[0-9a-f]{40}\.(pack|idx|rev|bitmap|mtimes)|objects/info/packs|objects/info/commit-graph|objects/info/commit-graphs/commit-graph-chain|objects/info/commit-graphs/graph-[0-9a-f]{40}\.graph|objects/[0-9a-f]{2}/[0-9a-f]{38}|refs/heads/main|refs/remotes/origin/main)$' || true)
test -z "$x" || { echo "files git does not write: $x"; exit 1; }
refs=$(G for-each-ref --format='%(refname)' | tr '\n' ' '); test "$refs" = "refs/heads/main refs/remotes/origin/main "
out=$(G fsck --unreachable --no-reflogs --no-progress 2>&1)
case $out in *unreachable*) echo "unreachable objects"; exit 1 ;; esac
cd && rm -rf ~/hubtest /tmp/hubcheck
echo trial-ok
EOF
ssh ubuntu@192.168.50.181 'rm -rf /tmp/hubcheck && mkdir -p /tmp/hubcheck'
scp -q image/clean-hub-git.sh image/hub-git-config ubuntu@192.168.50.181:/tmp/hubcheck/
ssh ubuntu@192.168.50.181 'bash -s' < ~/tsimg/hub-trial.sh; echo "exit $?"
```

Expected：輸出只有 `clean-hub-git: ignored: …` 行，最後印 `trial-ok` 和 `exit 0`（`exit` 是腳本的結束碼）。沒有 `trial-ok`：停下回報，附上最後幾行；母機的 checkout 本身不受影響，`~/hubtest` 回報後由助手刪掉（`ssh ubuntu@192.168.50.181 'rm -rf ~/hubtest /tmp/hubcheck'`）。

### Task 4: 記錄，回到 5b

- [ ] 把 Task 1–3 的結果（`hub-full-ok`、`trial-ok`、ignored 行的數目、網關標題）寫進 `~/tsimg/record.md`，註明 5b Task 3 的網關步驟由這份計劃代替。
- [ ] 在 `release/image-v1` 上：`git add docs/plans/2026-11-16-hub-full-checkout.md`，Litmus 後 `git commit -m "docs(plan): the mother's gateway becomes a full checkout (before plan 5b Task 3)"`；`git switch main && git merge --no-ff release/image-v1`，`git push origin main`；`release/image-v1` 跟上 `main`；`git status --porcelain` 沒有輸出。（`docs/reviews/` 的審閱狀態檔照 5a、5b 的做法不 commit：確認它被忽略或不存在，否則停下回報。）
- [ ] 接着做 5b Task 3 的「更新來源」和最後的確認。

## 不在這份計劃裏

- 我們網關的 `scripts/bootstrap.sh` 同樣以 partial、sparse 方式 clone：用它裝的裝置也會被 `clean-hub-git.sh` 拒絕。只影響「從那種裝置打包映像」，記為之後的事，不在這裏改。
- 映像裏網關檔案樹的大小（見背景）。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
