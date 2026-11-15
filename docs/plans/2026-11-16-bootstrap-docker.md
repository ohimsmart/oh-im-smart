# Bootstrap prepare.sh 和 Docker（v1 計劃 4b）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 加上 `bootstrap/prepare.sh`：在 Docker 容器裏對 bootstrap 映像的私人副本執行 4a 的 `prepare-image.sh`，輸出權限 600 的新檔案，失敗、中斷或脫離容器時什麼都不留下；並在 macOS Docker Desktop 上跑一次 §7.4 的檢查。

**範圍：** 這是計劃 4（spec §7.3 `bootstrap/prepare.sh`）的後半。4a（`docs/plans/2026-11-15-bootstrap-prepare.md`，已 merge）做了改寫映像的 `prepare-image.sh`，並把 4b 要處理的問題列在它的「不在這份計劃裏」。這份計劃處理那張清單的每一項，滿足 §7.4 餘下的三項：主機上的輸出檔權限是 600、中斷後不留下未完成的檔案、macOS 上跑一次。**本計劃不改 README**（教學和映像 Release 計劃負責）。

**Architecture:** `prepare.sh <來源映像> <輸出映像>` 在主機上執行，只用 bash（macOS 的 bash 3.2 也能跑）、coreutils 和 `docker`。它在輸出位置旁邊建立權限 700 的暫存目錄，`docker build` 出一個只含 `prepare-image.sh` 和它所需工具的 Alpine 映像，把來源複製進暫存目錄，再以 `docker run`（不加 `--privileged`、沒有網絡、唯讀根目錄、用戶自己的 uid:gid）在容器裏執行 `prepare-image.sh`。問題在容器裏問，答案從 `prepare.sh` 的 stdin 直接交給 `docker` 用戶端，`prepare.sh` 自己從不讀取答案。容器結束後以 `docker inspect` 確認它以 0 結束，再把成品以硬連結放到輸出位置。

**Tech Stack:** bash 3.2+（主機）、Docker Engine 29（UM，舊版 builder，沒有 BuildKit）和 Docker Desktop（macOS，BuildKit）、`alpine:3.22`（固定 digest）加 `bash e2fsprogs e2fsprogs-extra sfdisk openssl`、pytest（`uv run --no-project --with pytest`）、`strace -f -v`、Python `pty`。

**Global Constraints:**
- 這是 v1 七份計劃中的第 4 份的後半。已完成：映像打包、更新器訊息鍵、客戶端英文、網關英文和網址、kiosk 語言選擇、4a。之後：教學和映像 Release。
- **密碼不經命令列參數，也不經環境變數交給任何程式**（4a 的約束不變）。`prepare.sh` 不讀答案，`docker run` 不帶 `-e`。
- **`prepare.sh` 只用 bash 3.2 有的功能**（macOS 的 `/bin/bash`）：不用 `mapfile`、`${var,,}`、`wait -n`、關聯陣列。`sleep 0.5`、`stty -g`、`mktemp -d <範本>`、`ln`、`cp` 在 macOS 和 Linux 上用法相同。
- **Dockerfile 不能用 BuildKit 專有的語法**（`COPY --chmod` 等）：UM 的 Docker 29.1.3 沒有 buildx，用的是舊版 builder（2026-11-15 實測，`COPY --chmod` 報錯 "requires BuildKit"）。
- 輸出、提示和錯誤訊息用英文。`prepare.sh` 自己的錯誤一律是 `prepare: <原因>`，結束碼非 0；`prepare-image.sh` 在容器裏拒絕時已經印出 `prepare: <原因>`，`prepare.sh` 不再重複。
- 主 repo 的改動在分支 `feat/bootstrap-docker` 上。merge 到 `main` 只用 merge commit（`git merge --no-ff`），不 rebase、不 force-push。
- 測試指令不接 `| tail`。主 repo 的測試一律以 `GIT_CONFIG_GLOBAL=/dev/null` 執行。這個 session 的處理程序還沒有 `docker` 群組（加入群組之後沒有重新登入），所以 Docker 相關的命令經 `sg docker -c '…'` 執行；重新登入之後不需要。

---

## 背景：已確認的事實（2026-11-15 在 UM 和 Mac 上實測）

- 主 repo `main` = `deeca95`。`GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk bootstrap`：124 passed。
- 維護者已把 `chris` 加進 `docker` 群組（`getent group docker` → `docker:x:124:umrunner,chris`）。`sg docker -c 'docker version'` → Server 29.1.3。
- **Alpine 的 `dumpe2fs` 不能用：** 容器裏 `dumpe2fs -h "<映像>?offset=255852544"` 印出 `dumpe2fs: Unable to resolve '-h'`（`-x` 也一樣），所以 4a 的 `prepare-image.sh` 在容器裏找不到根分區，原型第一次經 Docker 執行就以 "no ext4 pmOS_root partition" 失敗。同一個容器裏 `tune2fs -l` 和 `debugfs -R stats` 都正確印出 `Filesystem volume name: pmOS_root` 和 `Filesystem features: … extent …`。UM 的 `tune2fs -l` 也一樣。所以 `prepare-image.sh` 改用 `tune2fs -l`（同一個 e2fsprogs 套件，輸出格式跟 `dumpe2fs -h` 的這兩行相同）。
- 容器裏的工具：`debugfs 1.47.2`、`GNU bash 5.2.37`。
- 原型（4a 存在 `~/.cache/ohimsmart/4b-prototype/`）加上 `tune2fs` 的修正後，經 Docker 端對端成功：輸出 `-rw-------`，`/etc/machine-id` 是 32 位十六進位，`docker ps -a` 沒有留下容器。約 2 秒（映像已建好時）。
- 用 Python `pty` 驅動 `prepare.sh`（`docker run -t` 那條路）實測：
  - 正常回答：WiFi 名稱有回顯，兩個密碼沒有，結束碼 0。
  - 第一個問題時按 Ctrl-P Ctrl-Q：舊原型（`docker run --rm`，信 `wait` 的結束碼）以 0 結束，並把**沒有改過的副本**當作成品放到輸出位置（容器由它的清理刪掉）；本計劃的 `prepare.sh` 印出 `prepare: detached from the container before it finished; nothing was written`，結束碼 1，沒有輸出檔，沒有容器。
  - 第二個問題時按 Ctrl-C：結束碼 1，沒有輸出檔，沒有容器。
- `--log-driver none` 下 `docker run -i -t` 的問答正常（attach 不經 log driver）。
- 固定的 `alpine:3.22` digest 是多平台索引（OCI image index），包括 `amd64` 和 `arm64`，所以 Apple Silicon 的 Mac 原生執行，不經模擬。
- Mac（`ssh mac`，Darwin arm64）：`/bin/bash` 是 3.2.57；`/bin/bash -n` 讀本計劃的 `prepare.sh` 沒有語法錯誤。**Mac 上沒有 Docker 引擎：** 只有 Homebrew 的 `docker` 命令列（29.9.2），`/Applications` 裏沒有 Docker Desktop（`docker context ls` 還留着之前安裝過的 `desktop-linux`，它的 socket 不存在），也沒有 colima 或 OrbStack。所以 Task 2 要等維護者決定（見「需要維護者決定的事」）。
- 本計劃的程式碼已經在 scratchpad 寫好並在 UM 上跑過：`bootstrap/test_prepare.py` 59 個測試全部通過（4a 的 33 個加 26 個；也在 `CDPATH=/tmp:.` 下跑過），用時約 45 秒，跑完沒有留下容器。以下故意的破壞都讓對應的測試失敗：清理時先 `docker rm` 再刪暫存目錄（`docker rm` 卡住時被 `kill -9`）、清理開頭不忽略信號（連按兩次 Ctrl-C）、以容器名稱而不是 `--cidfile` 的 id 查詢（同名的舊容器）、拿掉輸出名稱以 `-` 開頭的處理、拿掉 `--network none`（`docker run` 參數的測試）、刪掉 `cp` 之後的 `chmod 600`（唯讀來源）、刪掉 Dockerfile 的 `RUN chmod`（私人 checkout）、把 `running*` 當作成功（detach）、拿掉輸出位置變成目錄的檢查、`tune2fs -l` 改回 `dumpe2fs -h`（所有經 Docker 的測試）。

## 決定

1. **以容器自己的結束狀態為準，不信 `docker run` 的結束碼。** 不用 `--rm`；`docker run` 以 `--cidfile` 把容器 id 寫進暫存目錄，結束後以那個 id（不是名稱：容器名稱來自處理程序 id，之前某次執行留下、剛好同 id 的舊容器可能佔着它，`docker run` 會因名稱衝突失敗，按名稱查詢卻會查到舊容器的 `exited 0`）`docker inspect -f '{{.State.Status}} {{.State.ExitCode}}'`：只有 `exited 0` 算成功；`exited 130` 印 "stopped"；`exited 1` 表示 `prepare-image.sh` 已經說明原因，不再重複；其他 `exited N`（例如被 `kill -9` 的 137）印出狀態；`running`／`paused`／`restarting` 表示用戶按了 detach 鍵；查不到表示容器沒有跑起來。容器一律在 `EXIT` trap 裏以 id 和名稱各 `docker rm -f` 一次（以名稱是為了用戶端已建立容器、還沒寫 id 就被殺掉的情況）。（4a 清單第 1 項。）
2. **清理有上限。** `INT`、`TERM` 和 `HUP`（關掉終端機視窗）都經 `trap 'exit 130'` 走到 `EXIT` trap。UM 的 bash 5 沒有 `HUP` trap 也會跑 `EXIT` trap（實測），但 macOS 的 bash 3.2 沒有確認過，所以明確寫上。`cleanup` 一開始就忽略這三個信號：清理要等用戶端最多 10 秒，這期間第二次 Ctrl-C 會讓 `trap 'exit 130'` 在清理途中結束腳本，留下容器和 1 GB、可能含 WiFi 密碼的副本（第 1 輪審閱以兩次 TERM 實測）。`EXIT` trap 先 `kill`（TERM）背景的 `docker` 用戶端（它把信號轉給容器，容器裏的 `prepare-image.sh` 有 `trap 'exit 130'`），最多等 10 秒，之後 `kill -9`，再 `wait`；然後先還原終端機、刪掉暫存目錄（含可能有 WiFi 密碼的副本），**最後**才 `docker rm -f`：Docker daemon 卡住時 `docker rm` 不會返回，信號又已被忽略，用戶只能 `kill -9`，那時副本必須已經不在（`test_a_hung_docker_rm_leaves_no_copy_behind` 用一個 `rm` 會卡住的假 `docker` 驗證）。容器那時可能還開着副本，刪掉目錄項目後，資料在容器結束時釋放。先停用戶端再刪容器，用戶端就不能在容器刪掉之後再建立它。用 `-t` 時先存 `stty -g`，清理時還原：`kill -9` 掉的用戶端不會把終端機改回來。（第 2 項。）殘留的情況：用戶端在送出「建立容器」請求之後、Docker 處理它之前被殺掉，`docker rm -f` 可能早於容器建立；那個容器沒有啟動過，掛載的暫存目錄已經刪掉，裏面沒有任何秘密。
3. **Dockerfile 用 `RUN chmod 0755`，不用 `COPY --chmod`。** 在 umask 077 下 checkout 的 `prepare-image.sh` 是 0700，`COPY` 保留這個權限，非 root 的 `--user` 就執行不了。`COPY --chmod` 需要 BuildKit，UM 沒有。（第 3 項。）
4. **複製後先 `chmod 600`。** 唯讀（0444）的來源在 umask 077 下複製出來是 0400，`prepare-image.sh` 會以「cannot read and write」拒絕。（第 4 項。）
5. **輸出位置在執行期間變成目錄或符號連結時，收回連結並拒絕。** `ln` 遇到目錄會把連結放進那個目錄裏。GNU 的 `ln -T` 在 macOS 沒有，所以 `ln` 之後檢查：`$OUT` 是符號連結，或跟暫存檔不是同一個檔案（`-ef`）時，刪掉 `$OUT/bootstrap.img`（如果它就是暫存檔），然後拒絕。開始時已經拒絕存在的 `$OUT`，這只處理執行期間才出現的情況。（第 5 項。）
6. **以 `-` 開頭的來源或輸出名稱前面加上 `./`**，否則 `cp`、`ln`、`dirname` 會把它當作選項（Linux 上 `ln` 會把含密碼的副本放成目前目錄裏的 `bootstrap.img`）。
7. **每個可能失敗的步驟都有 `prepare:` 開頭的訊息：** `mktemp`、`docker build`（失敗時先印出 build 的輸出）、`cp`、容器沒有跑起來。`docker build` 的 stderr 存進暫存目錄，成功時不顯示（UM 的舊版 builder 每次都印 DEPRECATED 警告）。（第 6 項。）
8. **`--log-driver none`：** 容器的輸出（問題和回顯的 WiFi 名稱）不存進 Docker 的日誌。密碼本來就不回顯，這只是不讓 WiFi 名稱留在 `/var/lib/docker`。
9. **測試：** 4a 的 §7.4 檢查（machine-id、keyfile、NetworkManager 對照、shadow、主機金鑰、改分區服務、`e2fsck`、洩漏）改為對 `prepare-image.sh` 和 `prepare.sh` 的輸出各跑一次（`prepared` fixture 加參數）。`prepare.sh` 的洩漏測試用 `strace -f -v` 記錄主機這一側每個程式的命令列和環境變數，包括 `docker run`；容器裏的程式不在 strace 底下，它們跑的就是同一個 `prepare-image.sh`，由原生那一次的洩漏測試覆蓋。回顯測試也對 `prepare.sh`（`docker run -t`）跑一次。在終端機上按的鍵另外測：Ctrl-P Ctrl-Q（detach）和 Ctrl-C（經容器的終端機送到 `prepare-image.sh`，跟送給處理程序群組的 SIGINT 是不同的路）。中斷測試有四種：SIGINT、連續兩次 SIGINT 和 SIGHUP 送給整個處理程序群組，SIGTERM 只送給 `prepare.sh`。`docker run` 的參數由 strace 記錄的命令列檢查：必須有 `--network none`、`--read-only`、`--log-driver none`、`--init`、`--user <uid>:<gid>`，不能有 `--privileged`、`--cap-add`、`--device`、`-e`／`--env`／`--env-file`、`-v`／`--volume`。（第 8 項。）
10. **macOS 的洩漏檢查用 `bash -x`**（Mac 沒有 strace）：`bash -x` 印出 `prepare.sh` 執行的每個命令，包括 `docker run` 的完整參數；檢查它和輸出裏都沒有測試密碼。Mac 做好的映像帶回 UM，以 `OHIMSMART_PREPARED_IMAGE` 跑同一組映像檢查。只用 USB 的那一次也在 Mac 上跑，同樣帶回 UM 檢查。（第 7 項。）
11. **不支援 rootless Docker、Podman、SELinux 主機的 `:z` 標籤和 Windows。** rootless Docker 下容器裏的 uid 對不上檔案擁有者，`prepare-image.sh` 開頭的讀寫檢查會以提到 rootless Docker 的訊息拒絕（4a 決定 1）。

## 需要維護者決定的事

- **Mac 上的 Docker（Task 2 需要）。** Mac 上沒有 Docker 引擎。建議：維護者安裝 Docker Desktop（`brew install --cask docker-desktop`，安裝時要輸入 Mac 的管理員密碼，所以只能由維護者做），這跟 spec §7.4 和教學 §0.2 要求的環境相同。替代方案：我用 Homebrew 裝 colima（不需要管理員密碼），它也是 Linux 虛擬機裏的 Docker，能驗證 macOS 那一側（bash 3.2、BSD 工具、經虛擬機共享的檔案），但不是用戶會裝的 Docker Desktop，偏離 §7.4 的字面要求。Task 1 和 Task 3 不等這個決定。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `bootstrap/prepare.sh` | 新增（755） | 檢查參數、暫存目錄、`docker build`、複製、`docker run`、確認容器結果、放到輸出位置、清理 |
| `bootstrap/Dockerfile` | 新增 | 固定 digest 的 Alpine 和 `prepare-image.sh` 需要的工具 |
| `bootstrap/.dockerignore` | 新增 | build context 只送 `prepare-image.sh`，不送用戶可能存在 `bootstrap/` 的映像 |
| `bootstrap/prepare-image.sh` | 修改一行（加一行註解） | `dumpe2fs -h` 改為 `tune2fs -l` |
| `bootstrap/test_prepare.py` | 修改 | 映像檢查加上 `prepare.sh` 的參數；`prepare.sh` 自己的測試 |

---

### Task 1: `prepare.sh`、Dockerfile 和測試

**Files:**
- Create: `bootstrap/prepare.sh`、`bootstrap/Dockerfile`、`bootstrap/.dockerignore`
- Modify: `bootstrap/prepare-image.sh:31`、`bootstrap/test_prepare.py`

**Interfaces:**
- Consumes: 4a 的 `prepare-image.sh <image>`（stdin 讀四個答案，成功時結束碼 0，拒絕時印 `prepare: <原因>`、結束碼 1，`INT`/`TERM` 時 130）。
- Produces: `bootstrap/prepare.sh <來源> <輸出>`；教學計劃會引用它。

- [ ] **建立分支**

```bash
cd /home/chris/Projects/ohimsmart && git switch feat/bootstrap-docker    # 寫計劃時已建立
```

- [ ] **`prepare-image.sh`：`dumpe2fs -h` 改為 `tune2fs -l`**

```diff
 for start in $(sed -n 's/.*start= *\([0-9]*\),.*/\1/p' <<<"$table"); do
     dev="$IMG?offset=$((start * ${sector:-512}))"
-    head=$(dumpe2fs -h "$dev" 2>/dev/null) || continue
+    # tune2fs -l, not dumpe2fs -h: Alpine's dumpe2fs (in the Docker image) takes "-h" for the device.
+    head=$(tune2fs -l "$dev" 2>/dev/null) || continue
```

- [ ] **`bootstrap/Dockerfile`**

```dockerfile
# The tools prepare-image.sh needs: debugfs (e2fsprogs-extra), tune2fs and e2fsck 1.47+ (the image
# uses orphan_file), sfdisk, openssl. Built locally by prepare.sh; it never runs with network access.
FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
RUN apk add --no-cache bash e2fsprogs e2fsprogs-extra sfdisk openssl
COPY prepare-image.sh /usr/local/bin/prepare-image.sh
# Not COPY --chmod: that needs BuildKit. A checkout made under umask 077 leaves the script 0700.
RUN chmod 0755 /usr/local/bin/prepare-image.sh
ENTRYPOINT ["/usr/local/bin/prepare-image.sh"]
```

- [ ] **`bootstrap/.dockerignore`**

```
# The build needs only the script; never send images kept in bootstrap/ to the Docker daemon.
*
!prepare-image.sh
```

- [ ] **`bootstrap/prepare.sh`（`chmod 755`）**

```bash
#!/bin/bash
# Make a copy of the upstream bootstrap image that boots with a machine-id, your WiFi and your own
# login password (spec §7.3). Optional: the unchanged upstream image still works over USB.
# Usage: bootstrap/prepare.sh <bootstrap image> <output image>
# The work happens in a Docker container (no --privileged, no network, your own user id), so this
# runs the same on Linux and macOS (whose /bin/bash is 3.2: keep this script to what 3.2 has).
# The questions are asked inside the container; this script never sees the answers.
# Delete the output after flashing: it may hold your WiFi password.
set -euo pipefail
umask 077
unset CDPATH    # it would make `cd` print the directory, which `$(cd … && pwd)` would capture too

die() { printf 'prepare: %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || die "usage: prepare.sh <bootstrap image> <output image>"
SRC=$1 OUT=$2
# A name starting with "-" would be read as an option by cp, ln and dirname.
case $SRC in -*) SRC=./$SRC ;; esac
case $OUT in -*) OUT=./$OUT ;; esac
[ -f "$SRC" ] && [ -r "$SRC" ] || die "cannot read $SRC"
[ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die "$OUT already exists: choose another name or delete it first"
HERE=$(cd "$(dirname "$0")" && pwd) || die "cannot find the directory prepare.sh is in"
OUTDIR=$(cd "$(dirname "$OUT")" 2>/dev/null && pwd) || die "no such directory: $(dirname "$OUT")"
command -v docker >/dev/null 2>&1 || die "Docker is needed: install Docker Desktop (macOS) or Docker Engine (Linux)"
docker info >/dev/null 2>&1 || die "Docker is installed but not running, or this user may not use it"

NAME=ohimsmart-prepare-$$
WORK='' CLIENT='' TTYSAVE=''
cleanup() {
    trap '' INT TERM HUP     # a second Ctrl-C must not stop the cleanup halfway
    set +e                   # nor a failed step: every later step must still run
    # Stop the docker client before removing the container, so it cannot start one afterwards.
    # It passes the signal on to the container; if both are still there after 10 seconds, kill it.
    if [ -n "$CLIENT" ]; then
        kill "$CLIENT" 2>/dev/null || true
        i=0
        while kill -0 "$CLIENT" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
        kill -9 "$CLIENT" 2>/dev/null || true
        wait "$CLIENT" 2>/dev/null || true
    fi
    cid=''
    if [ -n "$WORK" ] && [ -s "$WORK/cid" ]; then cid=$(cat "$WORK/cid"); fi
    # The terminal and the copy (it may hold the WiFi password) before docker rm, which hangs with
    # a hung Docker daemon: then only kill -9 is left, and it must find nothing left to delete.
    if [ -n "$TTYSAVE" ]; then stty "$TTYSAVE" 2>/dev/null || true; fi   # a killed client leaves it raw
    if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
    if [ -n "$cid" ]; then docker rm -f "$cid" >/dev/null 2>&1 || true; fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true      # created, but killed before it wrote cid
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Private (700) and next to the output, so the finished file is linked, never copied, into place.
WORK=$(mktemp -d "$OUTDIR/.prepare.XXXXXX") || die "cannot write in $OUTDIR"
IMAGE=$(docker build -q "$HERE" 2>"$WORK/build.log") || {
    cat "$WORK/build.log" >&2
    die "could not build the container image (the first build needs the internet)"
}
cp "$SRC" "$WORK/bootstrap.img" || die "could not copy $SRC into $OUTDIR (is there room for 1 GB?)"
chmod 600 "$WORK/bootstrap.img"      # a read-only source would make a read-only copy
TTY=
if [ -t 0 ]; then TTY=-t; TTYSAVE=$(stty -g); fi
# In the background with `wait`, so a signal to this script runs its traps at once; `<&0` keeps the
# questions on this script's stdin. --mount, unlike -v, refuses a missing WORK instead of creating it.
# No --rm: the client's own exit status is not trusted (the detach keys, Ctrl-P Ctrl-Q, end it
# with 0 while the container runs on), so the container is asked how it ended, then removed.
# --log-driver none: the container's output (the questions, the WiFi name echoed) is kept nowhere.
# --cidfile: the container is asked about by its id, never by its name, which an old container
# left behind by an earlier run with the same process id could hold.
docker run -i $TTY --init --name "$NAME" --cidfile "$WORK/cid" --network none --read-only --tmpfs /tmp \
    --log-driver none --user "$(id -u):$(id -g)" --mount "type=bind,\"source=$WORK\",target=/work" \
    "$IMAGE" /work/bootstrap.img <&0 &
CLIENT=$!
wait "$CLIENT" || true
CLIENT=
state=
if [ -s "$WORK/cid" ]; then
    state=$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$(cat "$WORK/cid")" 2>/dev/null) || state=
fi
case $state in
    'exited 0') ;;
    'exited 130') die "stopped; nothing was written" ;;
    'exited 1') exit 1 ;;   # prepare-image.sh has said why
    exited\ *) die "the container ended with status ${state#exited }; nothing was written" ;;
    running*|paused*|restarting*) die "detached from the container before it finished; nothing was written" ;;
    *) die "the container did not run; nothing was written" ;;
esac
# A hard link, not mv: it fails instead of replacing a file that appeared at OUT meanwhile.
# A directory that appeared at OUT would take the link inside it: take it back out.
ln "$WORK/bootstrap.img" "$OUT" 2>/dev/null || die "could not create $OUT"
if [ -L "$OUT" ] || ! [ "$OUT" -ef "$WORK/bootstrap.img" ]; then
    if [ "$OUT/bootstrap.img" -ef "$WORK/bootstrap.img" ]; then rm -f "$OUT/bootstrap.img"; fi
    die "$OUT appeared while this ran: nothing was written"
fi
printf 'prepare: wrote %s. Delete it after flashing: it may hold your WiFi password, and holds a hash of your login password.\n' "$OUT" >&2
```

- [ ] **`bootstrap/test_prepare.py`：映像檢查加上 `prepare.sh`**

模組說明、import 和常數：

```python
"""bootstrap/prepare.sh and prepare-image.sh against the real upstream bootstrap image (spec §7.4).

The image (about 1 GB) is downloaded once into ~/.cache/ohimsmart and checked against the sha256
the README gives. prepare-image.sh runs natively here (UM has e2fsprogs 1.47, sfdisk and openssl);
prepare.sh runs it in Docker, which this user must be able to use: those tests fail without it.
OHIMSMART_PREPARED_IMAGE=<image> also checks an image prepare.sh made elsewhere (macOS, §7.4)
from a copy with planted host keys and the answers in ANSWERS.
"""
import hashlib
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest

HERE = Path(__file__).parent
INNER = HERE / 'prepare-image.sh'
WRAPPER = HERE / 'prepare.sh'
```

`_drop_images` 也刪子目錄裏的映像（`prepare.sh` 的輸出放在子目錄）：

```python
@pytest.fixture(autouse=True)
def _drop_images(tmp_path):
    """Each test copies the 1 GB image; delete the copies, or every run leaves tens of GB behind."""
    yield
    for img in tmp_path.rglob('*.img'):
        if img.is_file():
            img.unlink()
```

原來的 `prepared` fixture 換成以下內容。`planted` 是原來 fixture 裏放假主機金鑰的那幾行，抽出來給兩條路共用：

```python
@pytest.fixture(scope='module')
def docker():
    """prepare.sh needs Docker usable by this user. Its tests fail, not skip, without it (§7.4)."""
    r = subprocess.run(['docker', 'info'], capture_output=True, text=True)
    assert r.returncode == 0, 'Docker is not usable by this user: ' + r.stderr.strip()[-300:]


def wrap(src, out, answers, trace=None):
    return run(['bash', WRAPPER, src, out], answers, trace)


def containers():
    """prepare.sh's containers, running or not: every run must remove its own."""
    out = subprocess.run(['docker', 'ps', '-a', '--filter', 'name=ohimsmart-prepare-', '--format', '{{.Names}}'],
                         capture_output=True, text=True, check=True).stdout
    return out.split()


def planted(upstream, tmp):
    """A copy holding SSH host keys, so their removal is tested: the upstream image ships none."""
    img = copy(upstream, tmp, 'source.img')
    for name in ('ssh_host_ed25519_key', 'ssh_host_ed25519_key.pub'):
        plant(img, f'/etc/ssh/{name}', 'not a real key\n', tmp)
    assert 'ssh_host_ed25519_key' in dfs(img, 'ls /etc/ssh')
    return img


@pytest.fixture(scope='module')
def wrapped(docker, upstream, tmp_path_factory):
    """prepare.sh end to end. The trace sees the host side, docker run included; the container
    runs prepare-image.sh, which the native run of `prepared` traces."""
    tmp = tmp_path_factory.mktemp('wrapped')
    out = tmp / 'out' / 'prepared.img'
    out.parent.mkdir()
    try:
        r = wrap(planted(upstream, tmp), out, ANSWERS, trace=tmp / 'trace')
        assert r.returncode == 0, r.stderr
        yield out, r, (tmp / 'trace').read_text()
    finally:
        (tmp / 'source.img').unlink(missing_ok=True)
        out.unlink(missing_ok=True)


GIVEN = os.environ.get('OHIMSMART_PREPARED_IMAGE')


@pytest.fixture(scope='module', params=['prepare-image.sh', 'prepare.sh'] + (['given'] if GIVEN else []))
def prepared(request, upstream, tmp_path_factory):
    if request.param == 'prepare.sh':
        yield request.getfixturevalue('wrapped')
        return
    if request.param == 'given':
        yield Path(GIVEN), None, None
        return
    tmp = tmp_path_factory.mktemp('prepared')
    try:
        img = planted(upstream, tmp)
        r = prepare(img, *ANSWERS, trace=tmp / 'trace')
        assert r.returncode == 0, r.stderr
        yield img, r, (tmp / 'trace').read_text()
    finally:
        (tmp / 'source.img').unlink(missing_ok=True)
```

洩漏測試的開頭（其餘不變）：

```python
def test_no_secret_reaches_a_command_line_an_environment_or_the_output(prepared):
    _, r, trace = prepared
    if trace is None:
        pytest.skip('an image prepared elsewhere comes without a trace: see the macOS steps in the plan')
    # The trace saw the programs: debugfs for prepare-image.sh, docker run for prepare.sh.
    assert re.search(r'execve\("[^"]*/(debugfs|docker)", \[[^]]*"(-w|run)"', trace)
```

原來的 `test_hidden_answers_are_not_echoed_on_a_terminal` 換成 `converse` 和加了參數的版本（最後三個 `assert` 不變）：

```python
def converse(cmd, steps):
    """Run cmd on a terminal (a pty); for each (prompt, keys) wait for the prompt, then type the keys.
    Returns (exit status, everything the terminal showed)."""
    master, slave = pty.openpty()
    p = subprocess.Popen([str(c) for c in cmd], stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    seen = b''

    def read_more(timeout=1):
        nonlocal seen
        if select.select([master], [], [], timeout)[0]:
            try:
                chunk = os.read(master, 4096)
            except OSError:          # the script ended: Linux reports EIO on the master
                return False
            seen += chunk
            return bool(chunk)
        return True

    try:
        # Type each answer only after its question: a terminal echoes type-ahead before read -s runs.
        for prompt, keys in steps:
            deadline = time.time() + 60
            while prompt not in seen:
                assert time.time() < deadline and read_more(), seen
            os.write(master, keys)
        deadline = time.time() + 60
        while read_more(1) and p.poll() is None:
            assert time.time() < deadline, seen
        status = p.wait(timeout=60)
        # What the child printed just before it ended may still be waiting in the pty.
        while select.select([master], [], [], 0.5)[0]:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            seen += chunk
        return status, seen
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)


@pytest.mark.parametrize('script', ['prepare-image.sh', 'prepare.sh'])
def test_hidden_answers_are_not_echoed_on_a_terminal(upstream, tmp_path, script, request):
    if script == 'prepare-image.sh':
        cmd = ['bash', INNER, copy(upstream, tmp_path)]
    else:
        request.getfixturevalue('docker')
        cmd = ['bash', WRAPPER, upstream, tmp_path / 'prepared.img']      # docker run -t
    status, seen = converse(cmd, [(b'WiFi name', b'home\n'), (b'WiFi password', b'wifi-Secret-9\n'),
                                  (b'password for pmos', PASSWORD.encode() + b'\n'),
                                  (b'same password again', PASSWORD.encode() + b'\n')])
    assert status == 0, seen
    assert b'home' in seen                        # the WiFi name is echoed: it is not a secret
```

- [ ] **`bootstrap/test_prepare.py`：`prepare.sh` 自己的測試（加在檔案最後）**

```python
# prepare.sh's own work: the image checks above already ran on its output through `prepared`.

def test_prepare_sh_leaves_one_private_file(wrapped):
    out, _, _ = wrapped
    assert (out.stat().st_mode & 0o777) == 0o600
    assert os.listdir(out.parent) == ['prepared.img']
    assert containers() == []


def test_prepare_sh_refuses_to_overwrite(upstream, tmp_path):
    out = tmp_path / 'prepared.img'
    out.write_text('mine')
    r = wrap(upstream, out, ())
    assert r.returncode != 0 and 'already exists' in r.stderr
    assert out.read_text() == 'mine'


@pytest.mark.parametrize('answers, why', [
    (('', '', ''), 'needs 8 or more characters'),
    (('', 'thinksmart', 'thinksmart'), 'published default'),
    ((), 'no answer'),
])
def test_prepare_sh_refuses_bad_answers_and_leaves_nothing(docker, upstream, tmp_path, answers, why):
    r = wrap(upstream, tmp_path / 'prepared.img', answers)
    assert r.returncode != 0
    assert why in r.stderr
    assert list(tmp_path.iterdir()) == [] and containers() == []
    assert sha256(upstream) == SHA256, 'prepare.sh changed its source image'


def test_prepare_sh_works_from_a_private_checkout_on_a_read_only_source(docker, upstream, tmp_path):
    # A checkout made under umask 077 leaves prepare-image.sh 0700; a downloaded image may be 0444.
    here = tmp_path / 'bootstrap'
    here.mkdir()
    for name in ('prepare.sh', 'prepare-image.sh', 'Dockerfile', '.dockerignore'):
        shutil.copyfile(HERE / name, here / name)
        (here / name).chmod(0o700 if name.endswith('.sh') else 0o600)
    src = copy(upstream, tmp_path, 'source.img')
    src.chmod(0o444)
    out = tmp_path / 'prepared.img'
    r = run(['bash', here / 'prepare.sh', src, out], ('', PASSWORD, PASSWORD))
    assert r.returncode == 0, r.stderr
    assert (out.stat().st_mode & 0o777) == 0o600
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(out, 'cat /etc/machine-id'))
    assert sha256(src) == SHA256


def start(src, out):
    """prepare.sh in its own process group, and the name of its container once that is running."""
    p = subprocess.Popen(['bash', WRAPPER, src, out], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, start_new_session=True)
    name = f'ohimsmart-prepare-{p.pid}'
    deadline = time.time() + 120
    while subprocess.run(['docker', 'inspect', '-f', '{{.State.Running}}', name],
                         capture_output=True, text=True).stdout.strip() != 'true':
        if p.poll() is not None:
            pytest.fail(f'prepare.sh ended early ({p.returncode}): {p.communicate()[1]}')
        if time.time() > deadline:
            pytest.fail('the container never started')
        time.sleep(0.5)
    return p, name


def stop(p, name):
    if p.poll() is None:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
    subprocess.run(['docker', 'rm', '-f', name], capture_output=True)


@pytest.mark.parametrize('how', ['SIGINT', 'SIGINT twice', 'kill', 'hangup'])
def test_an_interrupted_prepare_sh_leaves_nothing(docker, upstream, tmp_path, how):
    p, name = start(upstream, tmp_path / 'prepared.img')
    try:
        # SIGINT and SIGHUP (the terminal closed) go to the whole process group; kill is SIGTERM
        # to prepare.sh alone. A second Ctrl-C lands while the cleanup waits for the docker client.
        if how == 'kill':
            p.terminate()
        else:
            os.killpg(p.pid, signal.SIGHUP if how == 'hangup' else signal.SIGINT)
        if how == 'SIGINT twice':
            time.sleep(0.3)
            os.killpg(p.pid, signal.SIGINT)
        p.communicate(timeout=60)
        assert p.returncode != 0
        assert list(tmp_path.iterdir()) == [] and containers() == []
    finally:
        stop(p, name)


@pytest.mark.parametrize('keys, why', [
    pytest.param(b'\x10\x11', b'detached from the container', id='detach'),  # docker run ends with 0
    pytest.param(b'\x03', b'stopped', id='ctrl-c'),        # typed into the container's terminal
])
def test_keys_that_end_the_run_on_a_terminal_leave_nothing(docker, upstream, tmp_path, keys, why):
    status, seen = converse(['bash', WRAPPER, upstream, tmp_path / 'prepared.img'],
                            [(b'WiFi name', b'home\n'), (b'WiFi password', keys)])
    assert status != 0 and why in seen, seen
    assert list(tmp_path.iterdir()) == [] and containers() == []


def test_an_output_that_appears_meanwhile_is_left_alone(docker, upstream, tmp_path):
    out = tmp_path / 'prepared'                  # not *.img: the cleanup fixture would take it for a copy
    p, name = start(upstream, out)
    try:
        out.mkdir()                              # a directory would take the link inside it
        _, err = p.communicate(''.join(a + '\n' for a in ('', PASSWORD, PASSWORD)), timeout=120)
        assert p.returncode != 0 and 'appeared while this ran' in err, err
        assert list(out.iterdir()) == []
        assert list(tmp_path.iterdir()) == [out] and containers() == []
    finally:
        stop(p, name)


def test_prepare_sh_runs_its_container_without_network_privileges_or_secrets(wrapped):
    _, _, trace = wrapped
    runs = re.findall(r'execve\("[^"]*/docker", \["docker", "run", (.*?)\], \[', trace)
    assert len(runs) == 1, runs
    args = re.findall(r'"((?:[^"\\]|\\.)*)"', runs[0])
    for flag in (['--network', 'none'], ['--read-only'], ['--log-driver', 'none'], ['--init'],
                 ['--user', f'{os.getuid()}:{os.getgid()}']):
        assert any(args[i:i + len(flag)] == flag for i in range(len(args))), flag
    for flag in ('--privileged', '--cap-add', '--device', '-e', '--env', '--env-file', '-v', '--volume'):
        assert flag not in args, flag


def test_an_old_container_with_the_same_name_is_not_taken_for_this_run(docker, upstream, tmp_path):
    # The container is named after the process id, which an earlier run's leftover could share.
    out = tmp_path / 'prepared.img'
    p = subprocess.Popen(['bash', '-c', 'read -r _ && exec bash "$0" "$1" "$2"', WRAPPER, upstream, out],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    name = f'ohimsmart-prepare-{p.pid}'
    try:
        image = subprocess.run(['docker', 'build', '-q', HERE], capture_output=True, text=True,
                               check=True).stdout.strip()
        subprocess.run(['docker', 'run', '--name', name, '--entrypoint', 'true', image],
                       capture_output=True, check=True)          # exited 0, like a finished run
        _, err = p.communicate('go\n' + ''.join(a + '\n' for a in ('', PASSWORD, PASSWORD)), timeout=120)
        assert p.returncode != 0 and 'did not run' in err, err
        assert list(tmp_path.iterdir()) == []
    finally:
        stop(p, name)


def test_an_output_name_starting_with_a_dash_is_a_file_name(docker, upstream, tmp_path):
    r = subprocess.run(['bash', WRAPPER, upstream, '-f.img'], input='\n' + PASSWORD + '\n' + PASSWORD + '\n',
                       capture_output=True, text=True, cwd=tmp_path)
    assert r.returncode == 0, r.stderr
    assert [x.name for x in tmp_path.iterdir()] == ['-f.img']
    assert ((tmp_path / '-f.img').stat().st_mode & 0o777) == 0o600


def test_a_hung_docker_rm_leaves_no_copy_behind(docker, upstream, tmp_path):
    # With the Docker daemon hung, docker rm never returns and only kill -9 ends prepare.sh: the
    # copy, which may hold the WiFi password, must be gone by then.
    bin_ = tmp_path / 'bin'
    bin_.mkdir()
    real = shutil.which('docker')
    (bin_ / 'docker').write_text(f'#!/bin/sh\n[ "$1" = rm ] && exec sleep 300\nexec {real} "$@"\n')
    (bin_ / 'docker').chmod(0o755)
    out_dir = tmp_path / 'out'
    out_dir.mkdir()
    p = subprocess.Popen(['bash', WRAPPER, upstream, out_dir / 'prepared.img'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
                         env=dict(os.environ, PATH=f'{bin_}:{os.environ["PATH"]}'))
    try:
        p.stdin.write('\n\n\n')          # refused: prepare.sh ends and cleans up
        p.stdin.close()
        deadline = time.time() + 120
        while p.poll() is None and time.time() < deadline:
            if subprocess.run(['pgrep', '-s', str(p.pid), '-f', 'sleep 300'], capture_output=True).returncode == 0:
                break                    # cleanup has reached docker rm
            time.sleep(0.2)
        assert p.poll() is None, 'prepare.sh ended without calling docker rm'
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        assert list(out_dir.iterdir()) == []
    finally:
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
        for name in containers():
            subprocess.run(['docker', 'rm', '-f', name], capture_output=True)
```

- [ ] **跑測試**

```bash
sg docker -c 'GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider bootstrap'
```

Expected: `59 passed`。再跑全部：

```bash
sg docker -c 'GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk bootstrap'
```

Expected: `150 passed`（124 + 26）。

- [ ] **故意破壞，確認對應的測試會失敗**（在 scratchpad 的副本上做，`-k` 選對應的測試，每一項都要看到 `1 failed` 或 `1 error`，然後復原）：
  1. 刪掉 `chmod 600 "$WORK/bootstrap.img"` → `-k read_only` 失敗；
  2. 刪掉 Dockerfile 的 `RUN chmod 0755 …` → `-k read_only` 失敗；
  3. `running*|paused*|restarting*) die …` 改成 `running*) ;;` → `-k 'keys_that and detach'` 失敗；
  4. `if [ -L "$OUT" ] || ! [ "$OUT" -ef …` 改成 `if false` → `-k appears` 失敗；
  5. `tune2fs -l` 改回 `dumpe2fs -h` → `-k 'prepare_sh and leaves_one'` 出錯；
  6. 刪掉 `cleanup` 開頭的 `trap '' INT TERM HUP` → `-k 'interrupted and twice'` 失敗；
  7. 不論有沒有 `cid` 檔案都以 `"$NAME"` 查詢 → `-k old_container` 失敗；
  8. 刪掉 `case $OUT in -*) …` → `-k starting_with_a` 失敗；
  9. 拿掉 `--network none` → `-k container_without` 失敗；
  10. 刪掉 `cleanup` 裏 `docker rm` 之前的 `rm -rf "$WORK"` → `-k hung` 失敗。
  （`-k` 也比對目錄名稱：放破壞副本的目錄名稱不要含這些字。）

- [ ] **`shellcheck -s bash bootstrap/prepare.sh`**：只允許 SC2015（`A && B || die` 是刻意的寫法，4a 相同）。

- [ ] **Litmus 審閱後 commit**

```bash
git add bootstrap/prepare.sh bootstrap/Dockerfile bootstrap/.dockerignore bootstrap/prepare-image.sh bootstrap/test_prepare.py
git commit -m "feat(bootstrap): prepare.sh runs prepare-image.sh in Docker and leaves one private file or nothing"
```

### Task 2: macOS Docker Desktop

§7.4：「macOS Docker Desktop 上至少要跑一次相同的檢查」。在 UM 上準備材料，經 `ssh mac` 在 Mac 上執行，成品帶回 UM 檢查。

- [ ] **在 UM 準備：** 一份放了假主機金鑰的來源副本（跟 `planted` 相同）和答案檔（`ANSWERS`，測試用的假密碼，不是秘密）。

```bash
M=$(mktemp -d)        # UM 上的暫存目錄
cp ~/.cache/ohimsmart/bootstrap-pmos-ssh-generic-qcom-msm8953.img "$M/source.img"
printf 'not a real key\n' >"$M/key"
for k in ssh_host_ed25519_key ssh_host_ed25519_key.pub; do
    debugfs -w -R "write $M/key /etc/ssh/$k" "$M/source.img?offset=255852544"
done
debugfs -R 'ls /etc/ssh' "$M/source.img?offset=255852544" | grep -c ssh_host_ed25519_key   # 2
python3 -c 'import sys; sys.stdout.write("".join(a + "\n" for a in ("a b\\c;d 家", " p\\a;s s ", "Sekret-pw 1", "Sekret-pw 1")))' >"$M/answers"
printf '\nSekret-pw 1\nSekret-pw 1\n' >"$M/answers-usb"
```

- [ ] **在 Mac 上啟動 Docker Desktop**（維護者裝好之後）：`ssh mac 'open -a Docker'`，再輪詢 `ssh mac 'docker info'` 直到成功（最多 3 分鐘；超過就停下來回報，Docker Desktop 可能在等一個對話框）。

- [ ] **複製到 Mac**：`ssh mac 'mktemp -d'` 得到 Mac 上的目錄 `$R`；`scp` 四個 bootstrap 檔案（`prepare.sh`、`prepare-image.sh`、`Dockerfile`、`.dockerignore`）、`source.img`、`answers`、`answers-usb` 到 `$R`。

- [ ] **在 Mac 上執行（從檔案讀答案）**，全部用 `/bin/bash`，即 3.2：

```bash
cd "$R" && mkdir out
/bin/bash -x ./prepare.sh source.img out/wifi.img <answers >wifi.log 2>&1 ; echo "wifi=$?"   # 0
/bin/bash -x ./prepare.sh source.img out/usb.img <answers-usb >usb.log 2>&1 ; echo "usb=$?"   # 0
printf '\n\n\n' | /bin/bash ./prepare.sh source.img out/empty.img ; echo "empty=$?"     # 1, "8 or more characters"
printf '\nthinksmart\nthinksmart\n' | /bin/bash ./prepare.sh source.img out/default.img ; echo "default=$?"   # 1, "published default"
stat -f '%Lp %N' out/*        # 兩個都是 600
ls -A out                     # 只有 usb.img 和 wifi.img
docker ps -a --filter name=ohimsmart-prepare- -q | wc -l   # 0
for s in 'Sekret-pw 1' 'p\a;s s' 'p\\a;s s'; do grep -cF -- "$s" wifi.log usb.log; done   # 全部 0
grep -c 'docker run' wifi.log                               # 1：bash -x 看到了 docker run 的參數
```

  中斷：`sleep 60 | /bin/bash ./prepare.sh source.img out/int.img &`，等 `docker ps --filter name=ohimsmart-prepare-` 出現容器後 `kill -TERM` 那個 `prepare.sh`，確認結束碼非 0、`out/` 沒有多出檔案（也沒有 `.prepare.*`）、沒有容器。

- [ ] **在 Mac 上執行（終端機那條路：`docker run -t`、`stty`、隱藏輸入、detach、Ctrl-C）。** 在 UM 上把以下內容存成 scratchpad 的 `mac_tty.py`，以 `GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -I mac_tty.py /home/chris/Projects/ohimsmart/bootstrap "$R"` 執行。它用測試檔的 `converse` 經 `ssh -tt mac` 驅動；`ssh -tt` 在 Mac 上配一個真正的終端機，所以 `prepare.sh` 的 `[ -t 0 ]` 成立：

```python
import sys
sys.path.insert(0, sys.argv[1])
from test_prepare import converse, PASSWORD

R = sys.argv[2]


def mac(out):
    # After prepare.sh: its status, whether the terminal echoes again (stty restored), what is in out/.
    return ['ssh', '-tt', 'mac', f'cd {R} && /bin/bash ./prepare.sh source.img {out}; '
            'echo status=$?; stty -a | grep -o " echo "; ls -A out; echo end-of-listing']


_, seen = converse(mac('out/tty.img'), [
    (b'WiFi name', b'home\n'), (b'WiFi password', b'wifi-Secret-9\n'),
    (b'password for pmos', PASSWORD.encode() + b'\n'), (b'same password again', PASSWORD.encode() + b'\n')])
print(seen.decode(errors='replace'))
assert b'status=0' in seen and b' echo ' in seen and b'tty.img' in seen and b'end-of-listing' in seen
assert b'wifi-Secret-9' not in seen and PASSWORD.encode() not in seen
for keys, why in ((b'\x10\x11', b'detached from the container'), (b'\x03', b'stopped')):
    _, seen = converse(mac('out/x.img'), [(b'WiFi name', b'home\n'), (b'WiFi password', keys)])
    print(seen.decode(errors='replace'))
    assert why in seen and b'status=1' in seen and b' echo ' in seen
    assert b'end-of-listing' in seen      # the listing below was seen, so its absences mean something
    assert b'x.img' not in seen and b'.prepare.' not in seen
```

  最後在 Mac 上 `rm out/tty.img`，`docker ps -a --filter name=ohimsmart-prepare- -q` 是空的。

- [ ] **帶回 UM 檢查：** `scp` `out/wifi.img` 和 `out/usb.img` 回 UM 的 `$M`，然後：

```bash
sg docker -c "OHIMSMART_PREPARED_IMAGE=$M/wifi.img GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider bootstrap -k given"
```

Expected: 7 passed、1 skipped（洩漏測試：沒有 trace，Mac 那一側由上面的 `bash -x` 檢查覆蓋）。`usb.img`：`debugfs -R 'ls /etc/NetworkManager/system-connections'` 沒有 `.nmconnection`，`machine-id` 是 32 位十六進位，`root` 是 `!`，`e2fsck -fn` 乾淨。

- [ ] **清理：** 刪掉 Mac 上的 `$R`（內有映像副本）、UM 上的 `$M`；`ssh mac 'osascript -e "quit app \"Docker\""'` 關掉 Docker Desktop（它原本沒有在執行）。

- [ ] **把結果寫進本計劃的「實作記錄」。**

### Task 3: merge 和 push

- [ ] 實作記錄寫完後，plan doc 跟 code 分開 commit（Litmus 審閱）。
- [ ] `git switch main && git merge --no-ff feat/bootstrap-docker`，再跑一次全部測試（150 passed），`git push origin main`。Task 2 若還在等 Mac 上的 Docker，就在它完成後另外 commit 實作記錄。

## 實作記錄

**Task 1：完成**（2026-11-16，commit `0a7a9d6`，分支 `feat/bootstrap-docker`）。`update kiosk bootstrap` 共 151 passed（bootstrap 60 個）；跑完沒有留下 `ohimsmart-prepare-` 容器。

**設計審閱：** 第 1 輪 6 個 medium（第二次 Ctrl-C 中斷清理、以名稱查詢容器、以 `-` 開頭的名稱、Mac 沒跑終端機那條路、Mac 沒跑拒絕的答案、沒有測試鎖住 `docker run` 的參數），全部修正並各有一個會失敗的測試。第 2 輪 Grok 逾時（覆蓋不足，不能通過），1 個 medium（清理先 `docker rm` 再刪副本），修正並加測試。重跑的第 2 輪三位審閱者都在，1 個 medium（`converse()` 在子程序結束後可能漏讀最後的輸出），審閱流程把它歸為測試可以發現的問題而延後，標記 PASS；仍然修正了（`converse()` 結束後讀完 pty，Mac 的 `mac_tty.py` 要求看到 `end-of-listing`）。

**PASS 之後的改動（未經設計審閱，經 Litmus 審閱）：**
1. `cleanup` 開頭加 `set +e`：`EXIT` trap 裏一個失敗的指令不會讓後面的步驟被略過（第 3 輪的 low）。
2. **只刪這次執行的容器：** 容器加上 `--label ohimsmart.run=<pid>-<暫存目錄的亂數>`，清理時以這個 label 找容器並刪除，不再以名稱 `docker rm -f "$NAME"`（Litmus high：同名的容器可能是別人的）。`test_an_old_container_with_the_same_name_is_not_taken_for_this_run` 加上「舊容器還在」的檢查。
3. **`docker inspect` 也在背景執行並 `wait`**（Litmus medium：daemon 卡住時，同步的 `inspect` 會讓 SIGTERM 等到它結束）。`test_a_hung_docker_daemon_leaves_no_copy_behind` 加上 `inspect` 參數（SIGTERM 30 秒內結束、不留副本）。
4. **發佈結果的幾步忽略信號**（`ln` 到檢查之間被中斷，會留下清理不知道的連結；Litmus medium）。
5. 測試的 `start()` 在等容器時失敗也會停掉 `prepare.sh` 和它的容器；`hung` 測試只刪自己的容器（Litmus high／medium）。
6. Dockerfile 加 `USER 65534:65534`（沒有 `--user` 時以 nobody 執行）和 `HEALTHCHECK NONE`：commit 前的 checkov 檢查（CKV_DOCKER_3、CKV_DOCKER_2）要求，修正後 41 項通過、0 項失敗。`prepare.sh` 一直以 `--user` 覆蓋。

**故意破壞（在 scratchpad 的副本上，每一項都看到對應的測試失敗）：** 計劃列的 10 項，加上：`inspect` 改回同步執行（`hung` 的 `inspect` 參數失敗）、清理時另外以名稱刪容器（同名舊容器的測試失敗）。

**Task 2（macOS）：完成**（2026-11-16）。維護者安裝了 Docker Desktop（4.99，引擎 29.9.3 linux/arm64）。我經 `ssh mac` 啟動它，跑完後關掉。全部用 `/bin/bash` 3.2.57，`prepare.sh` 等四個檔案是 `0a7a9d6` 的版本：
- 從檔案讀答案：WiFi `wifi=0`（約 8 秒，包括第一次以 BuildKit 建構映像）、只用 USB `usb=0`、空白密碼 `empty=1`（"needs 8 or more characters"）、`thinksmart` `default=1`（"published default"）。兩個輸出檔都是 `600`，`out/` 只有 `usb.img` 和 `wifi.img`，沒有容器。
- `bash -x` 的記錄：四種寫法的測試密碼（原樣、`\` 寫成 `\\`、寫成 `\\\\`）都是 0 次（正向對照：同一組字串在答案檔裏找到 3 次）；`docker run` 帶 `--network none`、`--read-only`、`--log-driver none`、`--user 501:20`。
- 中斷：容器跑起來後 `kill -TERM` `prepare.sh`，結束碼 130，`out/` 沒有多出檔案，沒有容器。
- 終端機那條路（`mac_tty.py` 經 `ssh -tt`）：正常回答 `status=0`，WiFi 名稱回顯、兩個密碼沒有，終端機的 echo 已還原；Ctrl-P Ctrl-Q 印出 "detached from the container…"、Ctrl-C 印出 "stopped"，都是 `status=1`、沒有留下檔案、終端機已還原。
- 帶回 UM：`OHIMSMART_PREPARED_IMAGE=wifi.img … -k given` 7 passed、1 skipped（洩漏測試，由上面的 `bash -x` 檢查覆蓋）。`usb.img`：沒有 `.nmconnection`，machine-id 是 32 位十六進位，`root` 是 `!`，沒有主機金鑰，`e2fsck -fn` 乾淨。
- Mac 上的暫存目錄和 UM 上的副本都已刪除。

Mac 上發現一個小問題：Ctrl-C 之後 Docker Desktop 的用戶端印出一段廣告（"What's next: Debug this container error with Gordon…"）。之後的 commit 以 `DOCKER_CLI_HINTS=false docker run …` 關掉（只設在 `docker` 用戶端的環境，不傳進容器）。

**Task 3：** merge 和 push 不等 Task 2。

## 不在這份計劃裏

- **macOS 用 colima 或其他非 Docker Desktop 的引擎**（除非維護者選了上面的替代方案）。
- 教學（README）：§0.2 加入 Docker、A5 的三步、兩項提醒、「實驗性」標示、「給 AI 助手的說明」只掃 port 22，以及 spec §7.3 第 4 點和 `sfdisk -J` 的文字更新（教學和映像 Release 計劃）。
- rootless Docker、Podman、SELinux 主機（bind mount 需要 `:z`）和 Windows。
- 在真實裝置上開機驗證 WiFi（§10：v1 驗收不包括路線 A 和 bootstrap WiFi）。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
