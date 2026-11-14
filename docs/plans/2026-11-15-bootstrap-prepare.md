# bootstrap `prepare-image.sh` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `bootstrap/prepare-image.sh`：把上游 postmarketOS bootstrap 映像的一份副本就地改成開機後 D-Bus 和 NetworkManager 都起得來、可以經 WiFi 連上、登入密碼由用戶自己設定（spec §7.3 的四件事），並按 §7.4 用真實的 bootstrap 映像測試。

**Spec:** `docs/specs/2026-11-09-oh-im-smart-v1-design.md` §7.2、§7.3、§7.4、§8 最後一點、§9「bootstrap」一行、§10 第一點。

**範圍：** spec §7.3 的 `bootstrap/prepare.sh` 分成兩份計劃。**這一份（4a）**只做改寫映像的部分：`prepare-image.sh` 和它在 UM 上直接執行的測試。**下一份（4b）**做 `prepare.sh`（在 Docker 容器裏執行 `prepare-image.sh`、暫存目錄、輸出權限、中斷清理）、`Dockerfile` 和 macOS Docker Desktop 的驗收；它要等 UM 能用 Docker 才能真正執行，見「需要維護者決定的事」和「不在這份計劃裏」。所以 **§7.4 裏「主機上的輸出檔權限是 600、中斷後不留下未完成的檔案」和「macOS 上跑一次」這幾項，這份計劃不滿足**，由 4b 負責。

**Architecture:** `bootstrap/prepare-image.sh <image>` 就地改寫一個映像檔，只用 `sfdisk`、`dumpe2fs`、`debugfs`、`e2fsck`、`openssl` 和 coreutils，從 stdin 讀問題的答案。它不知道自己在不在容器裏：4b 的 `prepare.sh` 會在 Alpine 容器裏對一份私人副本執行它。測試在 UM 上直接執行它（UM 有 e2fsprogs 1.47.0、sfdisk、openssl、strace、nmcli）。

**Tech Stack:** bash、e2fsprogs 1.47+（`debugfs -w`，以 `檔案?offset=位元組` 指定分區，不用 loop 裝置）、util-linux `sfdisk`、OpenSSL 3（`openssl passwd -6 -stdin`）、pytest（`uv run --no-project --with pytest`）、`nmcli --offline`（測試裏當 NetworkManager keyfile 的對照）、`strace -f -v`（測試裏記錄每個子程序的命令列和環境變數）、Python `pty`（測試隱藏輸入）。

**Global Constraints:**
- 這是 v1 七份計劃中的第 4 份的前半。已完成：映像打包、更新器訊息鍵、客戶端英文、網關英文和網址、kiosk 語言選擇。之後：4b（`prepare.sh` 和 Docker）、教學和映像 Release（包括 bootstrap 的教學部分：§0.2 加入 Docker、A5 的三步、兩項提醒、「實驗性」標示，以及「給 AI 助手的說明」只掃 port 22）。**本計劃不改 README。**
- **密碼不經命令列參數，也不經環境變數交給任何程式。** 答案只經 stdin 進入 `prepare-image.sh`；`printf` 是 bash 內建指令，不會產生新的處理程序。
- **`debugfs` 的結束碼不可信**（spec §7.3）：每次寫入都讀回內容、類型、mode、uid、gid 比對，最後整個檔案系統跑 `e2fsck -fn`。`debugfs` 的輸出也先整段存進變數再搜尋，不接 `| grep -q`：在 `pipefail` 下，`! debugfs … | grep -q X || die` 遇到 `debugfs` 失敗時不會 `die`。目錄清單一律經 `listdir`，它要求清單裏有目錄自己的 `.`：`debugfs` 列一個不存在的目錄時什麼都不印、結束碼 0，空的結果不能當作「沒有那個檔案」的證據。
- **用 `debugfs` 設 mode 時要帶檔案類型位元：** 普通檔案是 `0100600`、`0100644`。只寫 `0600` 會把 inode 變成 "bad type"，`e2fsck` 報錯（2026-11-15 在真實映像的副本上試過）。
- **問題全部問完、檢查完，才開始寫入映像。** 被拒絕的答案不會改動映像。
- 輸出、提示和錯誤訊息用英文（教學會解釋）。錯誤一律是 `prepare: <原因>`，結束碼非 0。
- 主 repo 的改動在分支 `feat/bootstrap-prepare` 上。merge 到 `main` 只用 merge commit（`git merge --no-ff`），不 rebase、不 force-push。
- 測試指令不接 `| tail`。主 repo 的測試一律以 `GIT_CONFIG_GLOBAL=/dev/null` 執行。

---

## 背景：基準和真實映像

- 主 repo `main` = `da2f1b6`。`GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk`：91 passed。
- 上游映像 `bootstrap-pmos-ssh-generic-qcom-msm8953.img`（Release `bootstrap-2026-05-22`），sha256 `7d79db19…7921b`，跟 README 寫的相同。已下載到 UM 的 `~/.cache/ohimsmart/`。
- 用 `sfdisk -J` 和 `debugfs`（唯讀）看過的內容：
  - DOS 分區表，扇區 512 位元組。分區 1：起點 2048，類型 `ef`（boot）。分區 2：起點 499712（位元組偏移 255852544），類型 `83`，ext4，卷名 `pmOS_root`，功能包括 `orphan_file`（所以要 e2fsprogs 1.47 以上）。
  - `/etc/machine-id` 存在，但是 0 位元組。`/etc/init.d/machine-id` 這個 OpenRC 服務存在，卻不在任何 runlevel 裏，所以開機時沒有人產生 machine-id。這就是 §7.2 D-Bus 和 NetworkManager 起不來的原因。
  - `/etc/ssh/` 沒有主機金鑰。`/etc/init.d/sshd` 在 `start_pre` 執行 `ssh-keygen -A`，除非 `sshd_disable_keygen`（或大寫的 `SSHD_DISABLE_KEYGEN`）是 yes；`/etc/conf.d/sshd` 沒有設定它（全部是註解）。
  - `/etc/NetworkManager/system-connections/` 存在，是空的，權限 755。
  - `/etc/shadow`（0:0，0600）：`root` 和 `pmos` 都有 `$6$` 雜湊。`pmos` 的 uid 是 10000，shell 是 `/bin/ash`。
  - `/etc/init.d/bootstrap-apply-ubuntu-gpt`（rickx 的自動改分區服務）存在，但 `sysinit`、`boot`、`default`、`shutdown`、`nonetwork` 五個 runlevel 都沒有它的連結。
  - 主機名稱已經是 `thinksmarter`。防火牆接受所有介面上的 port 22，`root` 和 `pmos` 都沒有 `authorized_keys`（第 3 輪審閱時確認），所以鎖定 `root` 的密碼就足夠，WiFi 那條路也不會被防火牆擋住。
- 用 UM 的 `nmcli --offline`（NetworkManager 1.46）試過：SSID 含非 ASCII 字元時，NetworkManager 自己就把 `ssid=` 寫成以 `;` 分隔的十進位位元組；讀回時也接受這種寫法。
- `openssl passwd -6 -stdin` 只用密碼的前 256 位元組（審閱時在 UM 上確認），所以登入密碼設上限 128 位元組。
- **UM 上這個帳號目前不能用 Docker**（`/var/run/docker.sock` 屬於 `docker` 群組，帳號不在群組裏），所以 4b 還不能執行。
- 本計劃的程式碼已經在 scratchpad 寫好並在 UM 上跑過：31 個測試全部通過，用時約 20 秒。以下故意的破壞都讓對應的測試失敗：把登入密碼放進 `openssl` 的命令列、`export PASS`、`export PSK`（洩漏測試；strace 把反斜線記成 `\\`，所以測試同時找原樣、strace 的寫法和 keyfile 的寫法，否則含反斜線的 WiFi 密碼洩漏了也找不到）；`read -rsp` 改成 `read -rp`（回顯測試）；sshd 檢查改成只認小寫（`SSHD_DISABLE_KEYGEN` 那一個參數）；刪掉 `unset`（export 過同名變數的測試）；runlevel 清單不經 `listdir`（缺少 runlevel 目錄的測試）。

## 決定

1. **只用改寫映像需要的工具，不用 loop 裝置和 root。** `prepare-image.sh` 不知道自己在不在容器裏，所以可以在 UM 上直接測試，不必等 Docker；4b 的 `prepare.sh` 只負責 Docker、暫存目錄和權限。腳本開頭檢查映像檔能不能讀寫，失敗時的訊息提到 rootless Docker（4b 不支援它，那時就會出現這個錯誤），不會讓用戶以為是映像有問題。
2. **找根分區：** 逐一檢查 `sfdisk -d` 列出的分區，選卷名是 `pmOS_root` 的那一個；它不是 ext4（沒有 `extent` 功能）就拒絕；找不到、多於一個、或檔案根本沒有分區表也拒絕。spec 寫的是 `sfdisk -J`；改用 `sfdisk -d` 的文字輸出，因為 4b 的 Alpine 容器裏沒有 JSON 解析工具，為此加裝 `jq` 不值得。判斷依據是檔案系統本身的卷名和功能，比分區類型可靠。
3. **WiFi 名稱寫成位元組清單**（`ssid=97;32;98;…;`），這是 NetworkManager 自己寫非純文字名稱的格式。這樣任何字元都不用跳脫，也不會跟 NetworkManager 對 `;` 的特殊處理（`\\;`）衝突。密碼按 GLib keyfile 字串的規則跳脫：反斜線寫成 `\\`，開頭的空格寫成 `\s`。測試直接用 NetworkManager 讀我們寫的檔案，再跟它自己為同一組輸入寫出的結果比對。連線名稱固定為 `bootstrap-wifi`，檔名固定為 `bootstrap-wifi.nmconnection`，所以 `debugfs` 的指令裏不會出現用戶輸入的文字。WiFi 名稱留空時，刪掉之前那次執行留下的 `bootstrap-wifi.nmconnection`（對已經改過的映像再跑一次「只用 USB」，不會留下舊的 WiFi 密碼）。
4. **輸入檢查（spec 沒寫，加上是因為不檢查的話，WiFi 會靜靜地連不上，或密碼被靜靜地截短）：** WiFi 名稱最多 32 位元組；WiFi 密碼不是空的話，必須是 8 到 63 個可列印 ASCII 字元，或 64 個十六進位數字（WPA 的規定）。登入密碼至少 8 個**字元**（用 `C.UTF-8` 計算，7 個中文字不算夠）、最多 128 位元組，要輸入兩次，兩次不同就拒絕：密碼是隱藏輸入的，打錯就只能重刷 bootstrap。
5. **隱藏輸入：** stdin 是終端機時用 `IFS= read -rsp "<問題>"`，跟 spec 的 `read -s` 相同，再加 `-p`：bash 先關掉回顯再印出問題，所以問題一出現就輸入或貼上的答案也不會回顯（先 `printf` 問題再 `read -s` 的寫法，第 4 輪審閱在 pty 上量到 300 次裏回顯了 31 次；`-rsp` 是 0 次）。stdin 不是終端機時（管線），先印問題再 `read -r`。bash 的 `read -s` 在被中斷時會自己恢復終端機的回顯。`test_hidden_answers_are_not_echoed_on_a_terminal` 用一個真正的虛擬終端機（pty）檢查：WiFi 名稱會回顯（正向對照），兩個密碼不會；它在 UM 上連續跑 25 次都通過。腳本開頭先 `unset` 所有存放答案的變數：bash 的 `read` 寫入一個從外面繼承、已經 export 的變數時，它仍然是 export 的，答案就會進入每個子程序的環境變數。
6. **中斷：** 腳本有 `trap 'exit 130' INT TERM`。沒有 trap 的 bash 腳本，若信號只送到 bash、沒有送到它正在等的程式，會在那個程式結束後繼續執行，然後停在下一個問題上。
7. **不加開機時執行 `ssh-keygen -A` 的腳本（偏離 spec §7.3 第 4 點）：** 映像的 sshd 服務每次啟動都會自己產生缺少的金鑰，`conf.d` 也沒有關掉。再加一個腳本只是重複。這個前提由腳本本身檢查：`/etc/init.d/sshd` 沒有 `ssh-keygen -A`，或 `/etc/conf.d/sshd` 有一行未註解、不分大小寫含 `keygen` 的設定時，**拒絕執行**（`test_an_image_whose_sshd_makes_no_host_keys_is_refused`，大小寫兩種寫法各一個參數）。仍然會刪除映像裏的所有主機金鑰（上游映像目前沒有，測試先放兩個假金鑰再驗證它們被刪掉）。spec 的文字留給「教學和映像 Release」計劃一起更新。
8. **自動改分區服務：** 腳本不啟用它。映像的任何 runlevel 已經有它的連結時，**拒絕執行**，不替用戶刪掉：那表示這不是 README 指定的上游映像。
9. **`root` 鎖定**的寫法是把 shadow 的第二欄改成 `!`。

## 需要維護者決定的事

- **UM 的 Docker 權限（4b 需要）。** `chris` 需要能用 Docker：`sudo usermod -aG docker chris`，再重新登入。加入 `docker` 群組等於取得 root 權限，所以由維護者決定。4b 的程式碼原型已經在 scratchpad，但從未在 Docker 裏執行過；三輪審閱在它身上找到的問題都是推理出來的，要有 Docker 才能驗證。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `bootstrap/prepare-image.sh` | 新增（755） | 檢查映像、問問題、寫入改動、逐項讀回、`e2fsck` |
| `bootstrap/test_prepare.py` | 新增 | §7.4 裏跟改寫映像有關的檢查，對真實映像執行 |

---

### Task 1: `prepare-image.sh` 和它的測試

**Files:**
- Create: `bootstrap/prepare-image.sh`
- Create: `bootstrap/test_prepare.py`

**Interfaces:**
- Produces: `bootstrap/prepare-image.sh <image>`：就地改寫；從 stdin 依序讀 WiFi 名稱、（名稱不是空的話）WiFi 密碼、登入密碼、再一次登入密碼；成功結束碼 0，拒絕時非 0 並在 stderr 印出 `prepare: <原因>`。4b 的 `prepare.sh` 依賴這個介面。
- Produces: 映像裏的 `/etc/NetworkManager/system-connections/bootstrap-wifi.nmconnection`（只在有 WiFi 名稱時）。
- Produces（測試）：`copy`、`root`、`dfs`、`stat`、`run`、`prepare`、`plant`、`nm`、`shadow`、常數 `ANSWERS`；4b 會加上經 Docker 執行的參數。

- [ ] **Step 1: 建立分支**

```bash
cd /home/chris/Projects/ohimsmart && git checkout -b feat/bootstrap-prepare
```

- [ ] **Step 2: 寫 `bootstrap/prepare-image.sh`**

```bash
#!/bin/bash
# Make a copy of the upstream postmarketOS bootstrap image ready to boot and reach (spec §7.3).
# Usage: prepare-image.sh <image>   -- changes <image> in place, so run it on a copy.
# Asks for the WiFi name and password and the bootstrap login password on stdin; none of them
# is ever given to another program as an argument or in its environment. Every write is checked
# by reading it back, because debugfs exits 0 even when one of its commands fails.
set -euo pipefail
umask 077
export LC_ALL=C

unset SSID PSK psk PASS PASS2 HASH    # an inherited export would carry the answers to every program
die() { printf 'prepare: %s\n' "$*" >&2; exit 1; }
[ $# -eq 1 ] || die "usage: prepare-image.sh <bootstrap image>"
[ -f "$1" ] && [ -r "$1" ] && [ -w "$1" ] ||
    die "cannot read and write $1 (under Docker: rootless Docker is not supported)"
IMG=$1

ver=$(debugfs -V 2>&1 | sed -n 's/^debugfs \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
read -r major minor <<<"${ver:-0 0}"
[ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 47 ]; } ||
    die "e2fsprogs 1.47 or newer is needed (the image's filesystem uses orphan_file)"

# The root filesystem: the one partition whose ext4 volume is called pmOS_root.
trap 'exit 130' INT TERM    # a trap makes bash stop even when the signal reached only bash itself
FS=
table=$(sfdisk -d "$IMG" 2>/dev/null) || die "no partition table in $IMG: is this the bootstrap image?"
sector=$(sed -n 's/^sector-size: *\([0-9]*\)$/\1/p' <<<"$table")
for start in $(sed -n 's/.*start= *\([0-9]*\),.*/\1/p' <<<"$table"); do
    dev="$IMG?offset=$((start * ${sector:-512}))"
    head=$(dumpe2fs -h "$dev" 2>/dev/null) || continue
    grep -q '^Filesystem volume name: *pmOS_root$' <<<"$head" || continue
    [ -z "$FS" ] || die "more than one pmOS_root partition"
    grep -q '^Filesystem features:.* extent' <<<"$head" || die "pmOS_root is not ext4"
    FS=$dev
done
[ -n "$FS" ] || die "no ext4 pmOS_root partition in $IMG: is this the bootstrap image?"

# Read debugfs output whole, then search it: "debugfs | grep -q" could pass when debugfs failed.
dfs() { debugfs -R "$1" "$FS" 2>/dev/null; }
has() { local out; out=$(dfs "$1") || return 1; grep -q -- "$2" <<<"$out"; }
# A listing that proves the directory was read: debugfs prints nothing and exits 0 for a missing one.
listdir() {
    local out; out=$(dfs "ls -p $1") || return 1
    grep -q '^/[0-9]*/040[0-7]*/[0-9]*/[0-9]*/\./' <<<"$out" || return 1
    printf '%s\n' "$out"
}
has 'cat /etc/shadow' '^pmos:' || die "no pmos account in the image"
has 'cat /etc/shadow' '^root:' || die "no root account in the image"
has 'stat /etc/NetworkManager/system-connections' 'Type: directory' ||
    die "no /etc/NetworkManager/system-connections in the image"
# The host keys are deleted below because sshd makes new ones when it starts, unless conf.d sets
# sshd_disable_keygen or SSHD_DISABLE_KEYGEN (the init script reads both spellings).
has 'cat /etc/init.d/sshd' 'ssh-keygen -A' && ! has 'cat /etc/conf.d/sshd' '^[^#]*[Kk][Ee][Yy][Gg][Ee][Nn]' ||
    die "this image's sshd would not make its own host keys; use the upstream image"
for level in sysinit boot default shutdown nonetwork; do
    listing=$(listdir "/etc/runlevels/$level") || die "cannot read /etc/runlevels/$level"
    ! grep -q 'bootstrap-apply-ubuntu-gpt' <<<"$listing" ||
        die "the image starts the automatic partition rewrite on boot; use the upstream image"
done

# Questions first, so a refusal leaves the image untouched.
ask() { printf '%s' "$1" >&2; IFS= read -r "$2" || die "no answer"; }
ask_secret() {
    if [ -t 0 ]; then
        # -p: bash prints the question after turning echo off, so an answer typed at once stays hidden.
        IFS= read -rsp "$1" "$2" || die "no answer"
        printf '\n' >&2
    else
        printf '%s' "$1" >&2
        IFS= read -r "$2" || die "no answer"
    fi
}
chars() { local LC_ALL=C.UTF-8; printf '%s' "${#1}"; }
ask 'WiFi name (leave empty for USB only): ' SSID
PSK=
if [ -n "$SSID" ]; then
    [ "${#SSID}" -le 32 ] || die "a WiFi name is at most 32 bytes"
    ask_secret 'WiFi password (leave empty for an open network): ' PSK
    if [ -n "$PSK" ]; then
        [[ $PSK =~ ^[\ -~]{8,63}$ || $PSK =~ ^[0-9A-Fa-f]{64}$ ]] ||
            die "a WPA password is 8 to 63 printable ASCII characters, or 64 hex digits"
    fi
fi
ask_secret 'Bootstrap login password for pmos (8 or more characters): ' PASS
[ "$(chars "$PASS")" -ge 8 ] || die "the login password needs 8 or more characters"
[ "${#PASS}" -le 128 ] || die "the login password may be at most 128 bytes"
[ "$PASS" != thinksmart ] || die "the login password must not be the published default"
ask_secret 'The same password again: ' PASS2
[ "$PASS" = "$PASS2" ] || die "the two passwords differ"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# put SRC DEST MODE: replace DEST with SRC, owned 0:0, then prove it by reading it back.
put() {
    printf 'rm "%s"\nwrite "%s" "%s"\nset_inode_field "%s" mode %s\nset_inode_field "%s" uid 0\nset_inode_field "%s" gid 0\n' \
        "$2" "$1" "$2" "$2" "$3" "$2" "$2" | debugfs -w -f - "$FS" >/dev/null 2>&1
    debugfs -R "dump \"$2\" \"$WORK/check\"" "$FS" >/dev/null 2>&1 && cmp -s "$1" "$WORK/check" ||
        die "writing $2 did not take"
    local st; st=$(dfs "stat \"$2\"")
    grep -q "Type: regular *Mode: *0${3: -3} " <<<"$st" && grep -q 'User: *0 *Group: *0 ' <<<"$st" ||
        die "$2 has the wrong owner or mode"
}

# 1. A machine-id of its own: the upstream image ships it empty, so D-Bus and NetworkManager stop.
od -An -tx1 -N16 /dev/urandom | tr -d ' \n' >"$WORK/machine-id"
printf '\n' >>"$WORK/machine-id"
put "$WORK/machine-id" /etc/machine-id 0100644

# 2. WiFi, as a NetworkManager keyfile. The name is written as bytes ("115;115;"), the form
# NetworkManager itself uses for names that are not plain text, so no character needs escaping.
# The password is a GLib keyfile string: backslash doubled, a leading space as \s.
KEYFILE=/etc/NetworkManager/system-connections/bootstrap-wifi.nmconnection
if [ -n "$SSID" ]; then
    ssid_bytes=$(printf '%s' "$SSID" | od -An -tu1 -v | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/ /;/g')
    {
        printf '[connection]\nid=bootstrap-wifi\nuuid=%s\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n\n' \
            "$(cat /proc/sys/kernel/random/uuid)"
        printf '[wifi]\nmode=infrastructure\nssid=%s;\n' "$ssid_bytes"
        if [ -n "$PSK" ]; then
            psk=${PSK//\\/\\\\}
            [ "${psk:0:1}" != ' ' ] || psk="\\s${psk:1}"
            printf '\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$psk"
        fi
        printf '\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
    } >"$WORK/wifi"
    put "$WORK/wifi" "$KEYFILE" 0100600
else
    # USB only: an image prepared before keeps no WiFi settings (or password) from that run.
    debugfs -w -R "rm $KEYFILE" "$FS" >/dev/null 2>&1 || true
    listing=$(listdir /etc/NetworkManager/system-connections) || die "cannot read the WiFi settings"
    ! grep -q 'bootstrap-wifi\.nmconnection' <<<"$listing" || die "could not remove the old WiFi settings"
fi

# 3. The login password, for pmos only; root is locked.
HASH=$(printf '%s\n' "$PASS" | openssl passwd -6 -stdin)
debugfs -R "dump /etc/shadow \"$WORK/shadow.old\"" "$FS" >/dev/null 2>&1
HASH=$HASH awk -F: -v OFS=: '$1 == "pmos" { $2 = ENVIRON["HASH"] } $1 == "root" { $2 = "!" } { print }' \
    "$WORK/shadow.old" >"$WORK/shadow"
grep -q '^pmos:' "$WORK/shadow.old" && grep -q '^pmos:\$6\$' "$WORK/shadow" && grep -q '^root:!:' "$WORK/shadow" &&
    [ "$(wc -l <"$WORK/shadow")" = "$(wc -l <"$WORK/shadow.old")" ] || die "could not rewrite /etc/shadow"
put "$WORK/shadow" /etc/shadow 0100600

# 4. No SSH host keys: sshd makes its own on first start (checked above).
listing=$(listdir /etc/ssh) || die "cannot read /etc/ssh"
for key in $(awk -F/ '$6 ~ /^ssh_host_[a-z0-9_]+_key(\.pub)?$/ { print $6 }' <<<"$listing"); do
    debugfs -w -R "rm /etc/ssh/$key" "$FS" >/dev/null 2>&1
done
listing=$(listdir /etc/ssh) || die "cannot read /etc/ssh"
! grep -q '/ssh_host_' <<<"$listing" || die "an SSH host key is still in the image"

e2fsck -fn "$FS" >/dev/null 2>&1 || die "the filesystem does not check clean after the changes"
if [ -n "$SSID" ]; then printf 'prepare: done (USB and WiFi)\n' >&2; else printf 'prepare: done (USB only)\n' >&2; fi
```

`chmod 755 bootstrap/prepare-image.sh`。

說明：

- `HASH=$HASH awk …` 把雜湊經環境變數交給 `awk`，雜湊裏的 `$` 不會被 `awk -v` 當作跳脫字元處理。雜湊不是密碼；密碼本身只經 `printf`（內建）的管線進入 `openssl` 的 stdin。
- `${#SSID}` 和 `${#PASS}` 在 `LC_ALL=C` 下算的是位元組數；`chars` 在函式裏把 `LC_ALL` 暫時改成 `C.UTF-8`，算的是字元數。它在 `$(…)` 子 shell 裏執行，不產生新程式，密碼不會出現在任何命令列。
- `put` 先 `rm` 再 `write`：`debugfs` 的 `write` 不會覆寫已有的檔案。目標不存在時，`rm` 那一行失敗，這是預期的，讀回時才判斷成敗。
- 第 3 項寫入前檢查新舊 shadow：舊檔有 `pmos`、新檔的 `pmos` 是 `$6$` 雜湊、`root` 是 `!`、行數相同。`dump` 失敗時舊檔是空的，這個檢查讓腳本停下，不會寫入一個空的 shadow。

- [ ] **Step 3: 寫 `bootstrap/test_prepare.py`**

```python
"""bootstrap/prepare-image.sh against the real upstream bootstrap image (spec §7.4).

The image (about 1 GB) is downloaded once into ~/.cache/ohimsmart and checked against the sha256
the README gives. prepare-image.sh runs natively here (UM has e2fsprogs 1.47, sfdisk and openssl).
"""
import hashlib
import json
import os
import pty
import re
import select
import shutil
import subprocess
import time
from pathlib import Path

import pytest

HERE = Path(__file__).parent
INNER = HERE / 'prepare-image.sh'
NAME = 'bootstrap-pmos-ssh-generic-qcom-msm8953.img'
URL = f'https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/{NAME}'
SHA256 = '7d79db19b0911647bf6ab0a9a2924ef5cf83b4674798a54acdcbd41cdf07921b'
CACHE = Path(os.environ.get('OHIMSMART_CACHE', Path.home() / '.cache' / 'ohimsmart'))

SSID = 'a b\\c;d 家'          # a space, a backslash, a semicolon and a non-ASCII character
PSK = ' p\\a;s s '            # leading and trailing spaces too
PASSWORD = 'Sekret-pw 1'
ANSWERS = (SSID, PSK, PASSWORD, PASSWORD)
KEYFILE = '/etc/NetworkManager/system-connections/bootstrap-wifi.nmconnection'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


@pytest.fixture(scope='session')
def upstream():
    path = CACHE / NAME
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        part = path.with_suffix('.part')
        subprocess.run(['curl', '-fsSL', '-o', part, URL], check=True)
        part.rename(path)
    assert sha256(path) == SHA256, f'{path} is not the upstream bootstrap image: delete it to download again'
    return path


def copy(upstream, tmp_path, name='bootstrap.img'):
    out = tmp_path / name
    shutil.copyfile(upstream, out)
    return out


def root(img):
    """debugfs's name for the image's ext4 root partition."""
    table = json.loads(subprocess.run(['sfdisk', '-J', img], capture_output=True, text=True, check=True).stdout)
    part = table['partitiontable']['partitions'][1]
    assert part['type'] == '83'
    return f"{img}?offset={part['start'] * table['partitiontable'].get('sectorsize', 512)}"


def dfs(img, cmd, write=False):
    args = ['debugfs'] + (['-w'] if write else []) + ['-R', cmd, root(img)]
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def stat(img, path):
    out = dfs(img, f'stat "{path}"')
    m = re.search(r'Type: (\w+)\s+Mode:\s+(\d+).*?User:\s+(\d+)\s+Group:\s+(\d+)', out, re.S)
    return m.groups() if m else None


def run(cmd, answers, trace=None, env=None):
    # -v: also record each program's environment, not only its command line.
    if trace:
        cmd = ['strace', '-f', '-v', '-qq', '-e', 'trace=execve', '-s', '65536', '-o', str(trace)] + cmd
    return subprocess.run([str(c) for c in cmd], input=''.join(a + '\n' for a in answers),
                          capture_output=True, text=True, env=env)


def prepare(img, *answers, trace=None, env=None):
    return run(['bash', INNER, img], answers, trace, env)


def leaks(secret, text):
    """Whether secret is in text as typed, as strace writes it (\\ for \\), or as the keyfile holds it."""
    spellings = {secret, secret.replace('\\', '\\\\'), secret.replace('\\', '\\\\\\\\')}
    return any(s in text for s in spellings)


@pytest.fixture(autouse=True)
def _drop_images(tmp_path):
    """Each test copies the 1 GB image; delete the copies, or every run leaves tens of GB behind."""
    yield
    for img in tmp_path.glob('*.img'):
        img.unlink()


def shadow(img):
    return {line.split(':')[0]: line.split(':')[1] for line in dfs(img, 'cat /etc/shadow').splitlines()}


def nm(*args, stdin=None):
    """What NetworkManager itself makes of a connection, as its keyfile lines."""
    out = subprocess.run(['nmcli', '--offline', 'connection', *args], input=stdin,
                         capture_output=True, text=True, check=True).stdout
    return {k: v for k, v in (line.split('=', 1) for line in out.splitlines() if '=' in line)
            if k in ('interface-name', 'ssid', 'key-mgmt', 'psk')}


def plant(img, path, text, tmp_path):
    """Replace one file in the image, to build the images the script must refuse or clean."""
    src = tmp_path / 'planted'
    src.write_text(text)
    dfs(img, f'rm {path}', write=True)
    dfs(img, f'write {src} {path}', write=True)


@pytest.fixture(scope='module')
def prepared(upstream, tmp_path_factory):
    tmp = tmp_path_factory.mktemp('prepared')
    img = copy(upstream, tmp)
    # Host keys planted, so their removal is tested: the upstream image ships none.
    for name in ('ssh_host_ed25519_key', 'ssh_host_ed25519_key.pub'):
        plant(img, f'/etc/ssh/{name}', 'not a real key\n', tmp)
    assert 'ssh_host_ed25519_key' in dfs(img, 'ls /etc/ssh')
    r = prepare(img, *ANSWERS, trace=tmp / 'trace')
    assert r.returncode == 0, r.stderr
    yield img, r, (tmp / 'trace').read_text()
    img.unlink()


def test_the_machine_id_is_32_hex_digits(prepared):
    img, _, _ = prepared
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(img, 'cat /etc/machine-id'))
    assert stat(img, '/etc/machine-id') == ('regular', '0644', '0', '0')


def test_the_wifi_keyfile_is_roots_and_private(prepared):
    img, _, _ = prepared
    assert stat(img, KEYFILE) == ('regular', '0600', '0', '0')
    assert dfs(img, 'ls /etc/NetworkManager/system-connections').count('.nmconnection') == 1


def test_networkmanager_reads_the_wifi_as_entered(prepared):
    img, _, _ = prepared
    text = dfs(img, f'cat {KEYFILE}')
    assert 'autoconnect=true' in text.splitlines()
    ours = nm('modify', 'connection.id', 'x', stdin=text)
    own = nm('add', 'type', 'wifi', 'con-name', 'x', 'ifname', 'wlan0', 'ssid', SSID,
             'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', PSK)
    assert ours == own
    assert ours['interface-name'] == 'wlan0'


def test_root_is_locked_and_pmos_takes_the_new_password(prepared):
    img, _, _ = prepared
    users = shadow(img)
    assert users['root'] == '!'
    salt = users['pmos'].split('$')[2]

    def hashed(pw):
        return subprocess.run(['openssl', 'passwd', '-6', '-salt', salt, '-stdin'], input=pw + '\n',
                              capture_output=True, text=True, check=True).stdout.strip()
    assert hashed(PASSWORD) == users['pmos']
    assert hashed('thinksmart') != users['pmos']


def test_the_ssh_host_keys_are_gone(prepared):
    img, _, _ = prepared
    assert 'ssh_host_' not in dfs(img, 'ls /etc/ssh')


def test_nothing_starts_the_automatic_partition_rewrite(prepared):
    img, _, _ = prepared
    for level in ('sysinit', 'boot', 'default', 'shutdown', 'nonetwork'):
        assert 'bootstrap-apply-ubuntu-gpt' not in dfs(img, f'ls /etc/runlevels/{level}')


def test_the_filesystem_checks_clean(prepared):
    img, _, _ = prepared
    r = subprocess.run(['e2fsck', '-fn', root(img)], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_no_secret_reaches_a_command_line_an_environment_or_the_output(prepared):
    _, r, trace = prepared
    assert re.search(r'execve\("[^"]*/debugfs", \[[^]]*"-w"', trace)     # the trace saw the programs
    assert 'vars */' not in trace      # -v: environments are written out, not summarised as /* N vars */
    for secret in (PASSWORD, PSK.strip()):
        assert not leaks(secret, trace)
        assert not leaks(secret, r.stdout + r.stderr)


def test_answers_stay_private_even_when_the_caller_exported_their_names(upstream, tmp_path):
    # bash's read keeps an inherited export, so without the script's unset the answers would
    # reach every program's environment.
    img = copy(upstream, tmp_path)
    env = dict(os.environ, SSID='', PSK='', PASS='', PASS2='')
    r = prepare(img, *ANSWERS, trace=tmp_path / 'trace', env=env)
    assert r.returncode == 0, r.stderr
    trace = (tmp_path / 'trace').read_text()
    assert not leaks(PASSWORD, trace) and not leaks(PSK.strip(), trace)


def test_hidden_answers_are_not_echoed_on_a_terminal(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    master, slave = pty.openpty()
    p = subprocess.Popen(['bash', INNER, img], stdin=slave, stdout=slave, stderr=slave)
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

    # Type each answer only after its question: a terminal echoes type-ahead before read -s runs.
    for prompt, answer in ((b'WiFi name', 'home'), (b'WiFi password', 'wifi-Secret-9'),
                           (b'password for pmos', PASSWORD), (b'same password again', PASSWORD)):
        deadline = time.time() + 30
        while prompt not in seen:
            assert time.time() < deadline and read_more(), seen
        os.write(master, answer.encode() + b'\n')
    while read_more(5) and p.poll() is None:
        pass
    assert p.wait(timeout=60) == 0, seen
    os.close(master)
    assert b'home' in seen                        # the WiFi name is echoed: it is not a secret
    assert b'wifi-Secret-9' not in seen
    assert PASSWORD.encode() not in seen


def test_an_open_network_has_no_password(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    name = 'Cafe-' + 'x' * 27                 # 32 bytes, the longest name WiFi allows
    r = prepare(img, name, '', PASSWORD, PASSWORD)
    assert r.returncode == 0, r.stderr
    text = dfs(img, f'cat {KEYFILE}')
    assert '[wifi-security]' not in text
    assert nm('modify', 'connection.id', 'x', stdin=text) == nm(
        'add', 'type', 'wifi', 'con-name', 'x', 'ifname', 'wlan0', 'ssid', name)


def test_no_wifi_name_means_usb_only(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode == 0, r.stderr
    assert '.nmconnection' not in dfs(img, 'ls /etc/NetworkManager/system-connections')
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(img, 'cat /etc/machine-id'))
    assert shadow(img)['root'] == '!'


def test_a_usb_only_run_removes_wifi_settings_from_an_earlier_run(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    assert prepare(img, 'home', 'wifi-Secret-9', PASSWORD, PASSWORD).returncode == 0
    assert 'bootstrap-wifi.nmconnection' in dfs(img, 'ls /etc/NetworkManager/system-connections')
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode == 0, r.stderr
    assert '.nmconnection' not in dfs(img, 'ls /etc/NetworkManager/system-connections')


@pytest.mark.parametrize('answers, why', [
    (('', '', ''), 'needs 8 or more characters'),
    (('', 'short', 'short'), 'needs 8 or more characters'),
    (('', '家' * 7, '家' * 7), 'needs 8 or more characters'),     # 21 bytes, but 7 characters
    (('', 'x' * 129, 'x' * 129), 'at most 128 bytes'),     # openssl would cut it at 256 bytes
    (('', 'thinksmart', 'thinksmart'), 'published default'),
    (('', PASSWORD, PASSWORD + 'x'), 'differ'),
    (('home', 'seven77', PASSWORD, PASSWORD), 'WPA password'),
    (('home', 'pässword-1', PASSWORD, PASSWORD), 'WPA password'),
    (('x' * 33, '', PASSWORD, PASSWORD), '32 bytes'),
    (('家' * 11, '', PASSWORD, PASSWORD), '32 bytes'),
    ((), 'no answer'),
])
def test_bad_answers_are_refused_before_anything_is_written(upstream, tmp_path, answers, why):
    img = copy(upstream, tmp_path)
    r = prepare(img, *answers)
    assert r.returncode != 0
    assert why in r.stderr
    assert sha256(img) == SHA256, 'a refused run changed the image'


def tiny(tmp_path, fs, label):
    img = tmp_path / 'tiny.img'
    subprocess.run(['truncate', '-s', '8M', img], check=True)
    subprocess.run(['sfdisk', '-q', img], input='2048,,83\n', text=True, check=True)
    subprocess.run(['mke2fs', '-q', '-t', fs, '-L', label, '-E', 'offset=1048576', img, '7168'],
                   capture_output=True, check=True)
    return img


@pytest.mark.parametrize('fs, label, why', [
    ('ext2', 'pmOS_root', 'not ext4'),
    ('ext4', 'other', 'no ext4 pmOS_root partition'),
])
def test_images_without_an_ext4_pmos_root_are_refused(tmp_path, fs, label, why):
    r = prepare(tiny(tmp_path, fs, label), PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert why in r.stderr


def test_a_file_without_a_partition_table_is_refused(tmp_path):
    img = tmp_path / 'blank.img'
    img.write_bytes(bytes(1 << 20))
    r = prepare(img, PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'no partition table' in r.stderr


@pytest.mark.parametrize('setting', ['sshd_disable_keygen="yes"', 'SSHD_DISABLE_KEYGEN="yes"'])
def test_an_image_whose_sshd_makes_no_host_keys_is_refused(upstream, tmp_path, setting):
    # Why prepare-image.sh deletes the host keys but adds no boot script to make them (spec §7.3 item 4).
    img = copy(upstream, tmp_path)
    plant(img, '/etc/conf.d/sshd', setting + '\n', tmp_path)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'would not make its own host keys' in r.stderr


def test_a_missing_runlevel_directory_is_not_taken_for_an_empty_one(upstream, tmp_path):
    # debugfs prints nothing and exits 0 for a directory that is not there.
    img = copy(upstream, tmp_path)
    names = [line.split('/')[5] for line in dfs(img, 'ls -p /etc/runlevels/nonetwork').splitlines() if line]
    assert names == ['.', '..']               # empty, so rmdir works
    dfs(img, 'rmdir /etc/runlevels/nonetwork', write=True)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'cannot read /etc/runlevels/nonetwork' in r.stderr


def test_an_image_that_rewrites_the_partitions_on_boot_is_refused(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    dfs(img, 'symlink /etc/runlevels/default/bootstrap-apply-ubuntu-gpt /etc/init.d/bootstrap-apply-ubuntu-gpt',
        write=True)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'automatic partition rewrite' in r.stderr
```

說明：

- 「處理程序清單」用 `strace -f -v -e trace=execve` 檢查：它記下腳本執行的每一個程式、完整的命令列和環境變數，比定時讀 `ps` 可靠，因為 `ps` 可能剛好錯過一個很短的處理程序。沒有 `-v` 時 strace 只寫 `/* 30 vars */`，所以測試要求 trace 裏沒有這種摘要。strace 把反斜線記成 `\\`，所以兩種寫法都找。
- NetworkManager 的對照：`nmcli --offline connection modify` 從 stdin 讀我們寫的 keyfile，再印出它理解的結果；`nmcli --offline connection add` 為同一組輸入寫出它自己的版本。兩者的 `ssid`、`psk`、`key-mgmt`、`interface-name` 必須相同。`autoconnect=true` 是預設值，NetworkManager 不會印出來，所以直接在我們的檔案裏檢查。
- 回顯測試等到每個問題出現才輸入答案：終端機在 `read -s` 關掉回顯之前，會把提早輸入的字回顯出來。
- 每個被拒絕的答案用一份新副本，之後核對整個映像的 sha256 仍然是上游的值。拒絕的訊息比對 `die` 的原文（例如 `needs 8 or more characters`），不是提示文字：提示 `(8 or more characters)` 也會出現在 stderr。

- [ ] **Step 4: 執行並確認通過**

```bash
cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider bootstrap
```

Expected：`31 passed`（`prepared` 的 8 個、export 過的同名變數、回顯、開放網絡、只用 USB、清除舊的 WiFi 設定、11 個被拒絕的答案、3 個被拒絕的檔案、2 個 sshd、缺少的 runlevel 目錄、自動改分區）。執行後 `/tmp/pytest-of-$USER` 不會留下映像副本（每個測試結束時刪除）。

- [ ] **Step 5: stage，然後證明守門的測試會失敗**

```bash
cd /home/chris/Projects/ohimsmart && git add bootstrap/prepare-image.sh bootstrap/test_prepare.py
```

逐一做以下破壞，每次執行對應的 `-k`，確認那個測試失敗，再用 `git checkout -- bootstrap/prepare-image.sh` 從暫存區還原：

1. `HASH=$(printf '%s\n' "$PASS" | openssl passwd -6 -stdin)` 改成 `HASH=$(openssl passwd -6 "$PASS")`（`-k secret`）；
2. 在 `[ "$PASS" = "$PASS2" ] || die …` 下一行加 `export PASS`（`-k secret`）；
3. 同一位置改加 `export PSK`（`-k secret`；WiFi 密碼含反斜線，證明 strace 的 `\\` 寫法也找得到）；
4. `IFS= read -rsp` 改成 `IFS= read -rp`（`-k echoed`）；
5. `'^[^#]*[Kk][Ee][Yy][Gg][Ee][Nn]'` 改成 `'^[^#]*keygen'`（`-k sshd_makes`，`SSHD_DISABLE_KEYGEN` 那個參數失敗）；
6. `unset SSID PSK psk PASS PASS2 HASH` 那一行刪掉（`-k exported`）；
7. runlevel 迴圈裏的 `listdir "/etc/runlevels/$level"` 改成 `dfs "ls -p /etc/runlevels/$level"`（`-k missing_runlevel`）。

最後 `git diff --exit-code bootstrap/prepare-image.sh` 沒有輸出，再跑一次全部通過。結果寫進實作記錄。

- [ ] **Step 6: 全部測試和 commit**

```bash
cd /home/chris/Projects/ohimsmart && GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q -p no:cacheprovider update kiosk bootstrap
git commit -m "feat(bootstrap): prepare-image.sh gives the bootstrap image a machine-id, WiFi and your own login password"
```

Expected：`122 passed`（91 + 31）。commit 前跑 litmus。

### Task 2: merge 和實作記錄

- [ ] **Step 1: merge**

```bash
cd /home/chris/Projects/ohimsmart && git checkout main && git merge --no-ff feat/bootstrap-prepare -m "Merge branch 'feat/bootstrap-prepare': prepare-image.sh for the bootstrap image (plan 4a of 7)" && git push origin main
```

- [ ] **Step 2: 實作記錄**

在本文件的「實作記錄」寫下 commit、偏離計劃的地方和 Step 5 的七次失敗證明，然後 commit 本文件。

## 實作記錄

- **Commit：** `1d9c9ff`（`bootstrap/prepare-image.sh`、`bootstrap/test_prepare.py`），merge commit `102cb84`，已推送 `origin/main`。主 repo 測試 `update kiosk bootstrap`：124 passed（91 + 33）。litmus PASS（只剩 59 個 shellcheck 的低嚴重度風格提示，例如 SC2292「用 `[[ ]]`」、SC2310「函式在 `||` 裏時 `set -e` 不作用」；腳本刻意以讀回結果判斷成敗，不依賴 `set -e`）。
- **審閱：** 4 次完整審閱、1 次中途停下（第 3 輪 medium 數沒有下降，以 `--continue` 繼續，沒有提高輪數上限），之後把計劃縮成 4a（只有 `prepare-image.sh`）。第 4 輪 Grok 逾時、覆蓋不足，沒有 PASS；重跑的那一輪三個審閱者都完成，0 high、1 medium、9 low，PASS。
- **偏離計劃的地方（實作時修正審閱最後一輪的問題）：**
  1. **只接受未改過的上游映像**（最後一輪唯一的 medium）：`debugfs rm` 釋放舊的 keyfile 時不會清掉資料，所以對已經改過的映像再跑一次，舊的 WiFi 密碼會留在檔案系統的空閒空間裏，刷進裝置。改為：`/etc/machine-id` 不是 0 位元組就拒絕（上游映像的 machine-id 是空的）。原本「只用 USB 時刪掉舊 keyfile」那一段和它的測試刪掉，換成 `test_an_image_prepared_before_is_refused`。決定第 3 點最後一句因此不再成立：要改設定，就從上游映像的新副本重來。
  2. 判斷 machine-id 大小時，`debugfs stat` 的 `Fragment: … Size: 0` 那一行也會符合 `Size: 0$`，所以比對限定在 `User:` 開頭的那一行（測試第一次就抓到這個錯）。
  3. `unset` 之後加 `set +o allexport +o xtrace`：呼叫者的環境若有 `SHELLOPTS=allexport`，bash 會 export 每個變數，答案會進入子程序的環境（審閱實際重現）；`xtrace` 會把答案印出來。`test_answers_stay_private_whatever_the_caller_exported` 多一個 `SHELLOPTS` 參數。
  4. litmus 找到的 medium：暫存目錄的路徑放在 `debugfs` 指令的雙引號裏，`TMPDIR` 含引號、反斜線或換行時指令會出錯，而 `put` 已經先刪掉了目標檔。改為在寫入任何東西之前拒絕這種路徑，加 `test_a_temporary_directory_debugfs_cannot_quote_is_refused_before_writing`。
  5. 測試的小修正：`/etc/shadow` 的擁有者和權限也檢查；pty 測試的最後一段有時間上限並在 `finally` 結束程序、關閉 pty；`prepared` fixture 在準備失敗時也刪掉 1 GB 的副本。
- **證明守門的測試會失敗（Step 5，加上實作時新增的守門）：** 每一項都在暫存區的版本上 `sed` 破壞、執行對應的 `-k`、確認失敗、`git checkout --` 還原：`openssl` 的命令列帶密碼、`export PASS`、`export PSK`（洩漏測試）；`read -rsp` → `read -rp`（回顯）；sshd 檢查只認小寫（`SSHD_DISABLE_KEYGEN` 參數）；刪掉 `unset`（export 同名變數）；runlevel 清單不經 `listdir`（缺少的 runlevel 目錄）；刪掉 `set +o allexport`（`SHELLOPTS` 參數）；machine-id 檢查改成永遠成立（改過的映像）；刪掉 `TMPDIR` 檢查（暫存目錄）。十項都失敗，還原後全部通過。回顯測試另外連續跑了 25 次都通過。
- **還沒做（4b）：** `prepare.sh`、`Dockerfile`、經 Docker 的測試、macOS Docker Desktop 的驗收；見下一節。需要 UM 的帳號能用 Docker。

## 不在這份計劃裏

- **4b：`bootstrap/prepare.sh`、`Dockerfile`、`.dockerignore`、經 Docker 的測試和 macOS Docker Desktop 的驗收。** 等 UM 能用 Docker 後另寫計劃、另行審閱。scratchpad 裏的原型已經採用的設計：`alpine:3.22` 固定 digest `sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f`；`IMAGE=$(docker build -q bootstrap/)`；`docker run --rm -i [-t] --init --name ohimsmart-prepare-<pid> --network none --read-only --tmpfs /tmp --user $(id -u):$(id -g) --mount type=bind,"source=<暫存目錄>",target=/work`；暫存目錄在輸出檔旁邊、權限 700；`ln` 放到輸出位置；`docker run` 在背景、用 `wait` 等；同一組 §7.4 檢查和被拒絕的答案經 Docker 再跑一次；Mac 上用 UM 做好的、放了假主機金鑰的副本。三輪審閱在這部分留下、4b 必須處理並在 Docker 裏驗證的問題：
  - 用戶按 Docker 的 detach 鍵（Ctrl-P Ctrl-Q）時 `docker run` 以 0 結束、容器還在跑，外殼會把未完成的映像當作成功（要以容器自己的結束狀態為準，例如不用 `--rm`，`docker inspect` 確認 `exited 0`）；
  - 清理時 `kill` 背景的 `docker run` 用戶端，信號會被轉給容器，`wait` 可能等不完（要設上限、必要時 `kill -9`，`docker rm -f` 前後都做；用 `-t` 時要恢復終端機設定）；
  - Dockerfile 的 `COPY` 在 umask 027／077 的 checkout 下，非 root 的 `--user` 執行不了腳本（`COPY --chmod=0755`）；
  - 唯讀（0444）的來源檔複製後不能寫（複製後先 `chmod 600`）；
  - 輸出位置在執行期間變成目錄時，`ln` 會把含密碼的副本放進那個目錄；
  - `cp`、`mktemp`、`docker run` 失敗時的訊息沒有 `prepare:` 開頭；
  - 洩漏測試在 Mac 上沒有 strace：改用 `bash -x prepare.sh` 的輸出檢查主機那一側的每個命令列；只用 USB 的 Mac 映像也要帶回 UM 檢查；
  - 經 Docker 的 pty 測試（`-t` 那條路的回顯）。
- 教學（README）和 spec §7.3 第 4 點的文字更新（教學和映像 Release 計劃）。
- rootless Docker 和 Windows。
- 在真實裝置上開機驗證 WiFi（§10：v1 驗收不包括路線 A 和 bootstrap WiFi）。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
