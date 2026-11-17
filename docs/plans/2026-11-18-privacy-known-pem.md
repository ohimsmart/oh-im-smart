# 隱私掃描放行 GnuTLS 內建測試金鑰 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use busdriver:subagent-driven-development (recommended) or busdriver:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓映像的隱私掃描（`image/check-image-privacy.sh`）不把 Ubuntu 官方 libgnutls 裏 GnuTLS 的 10 組自我測試金鑰算成私鑰，其他任何私鑰照樣讓打包失敗。

**Architecture:** 放行的單位是「整組 PEM 區塊的內容」，不是檔案或路徑：repo 裏一份 `image/known-pem-blocks.txt` 列出這 10 組區塊（從 BEGIN 到 END）的 sha256。掃描到私鑰時，算每組完整區塊的 sha256，在清單上的不計；檔案樹、boot、initramfs、整個磁碟映像四次掃描都用同一個做法（磁碟映像沒有路徑可排除，只能看內容）。清單只存雜湊，不存金鑰原文。

**Tech Stack:** POSIX sh（dash）、GNU grep `-P -z -o`、`sha256sum`；測試是 `image/tests/test-image-privacy.sh`。

**Global Constraints:**
- 維護者 2026-11-18 同意放寬這一項（「ok go」，回覆映像計劃 Task 8「套件裏的測試用 key 要回報，不能放寬規則」那一列）。只放行清單上的完整區塊；不排除路徑、不改 `{40}`、不按數量放行、不跳過 `/usr`。
- 清單由 `check-image-privacy.sh --list-pem` 從 **Ubuntu 套件庫下載的** `.deb` 產生，不是從母機擷取的內容產生。
- 輸出不印任何比對到的內容；`--list-pem` 只印雜湊。
- 失敗往安全的方向：清單缺檔、grep 出錯 → 結束碼 2；區塊沒有 END、比 8 KiB 長、改了一個字、或區塊數算不攏 → 算成未知金鑰 → 結束碼 1。
- commit 用 Litmus；merge 到 `main` 用 `--no-ff`；commit 結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。不跑 sudo、不建 skip 檔。

---

## 背景（2026-11-18 實測，紀錄在 `~/tsimg/record.md`）

- 修正計劃 `2026-11-17-image-capture-fixes.md` Task 4 重新擷取打包：`check-rootfs: ok`，但檔案樹的隱私掃描失敗，`private keys (PEM) 1`：`/usr/lib/aarch64-linux-gnu/libgnutls.so.30.37.1`。
- 該檔屬 `libgnutls30t64 3.8.3-1.1ubuntu3.6`（arm64），sha256 `17ffd34fd0bc239903ca37e95bb14eab6ee986c8d1260a5a08f16e0bfc669739`，跟 `http://ports.ubuntu.com/ubuntu-ports/pool/main/g/gnutls28/libgnutls30t64_3.8.3-1.1ubuntu3.6_arm64.deb`（sha256 `18482c85067bcc8e2b3802d7c3bb87bd54acf4da228e760054e88ef1e125d80a`）裏的同一個檔完全相同；母機 dpkg 的 md5 也相符。
- 掃描的比對規則在原版檔裏找到 10 組（5 EC、3 PKCS#8、1 RSA、1 DSA），正好是 GnuTLS 3.8.3 `lib/crypto-selftests-pk.c` 的 `rsa_2048_privkey`、`dsa_2048_privkey`、`ecdsa_secp256r1/secp192r1/secp224r1/secp384r1/secp521r1_privkey`、`gost01_privkey`、`gost12_256_privkey`、`gost12_512_privkey`。UM 的 x86 libgnutls 也有。腳本註解「none on a stock Ubuntu /usr or /etc」是錯的。
- 為甚麼用完整區塊而不是比對到的前 40 個字：RSA 的 PKCS#8 金鑰開頭幾十個 base64 字元是固定的 ASN.1 結構，同長度的 RSA 金鑰前 40 個字可能完全一樣，用它放行會連真正的金鑰一起放掉。
- 原型（同樣的規則和雜湊方法）在官方檔上：比對 10 組、完整區塊 10 組、10 個不同的雜湊，母機擷取的那份結果相同。

## 檔案

- Modify: `image/check-image-privacy.sh`（比對規則的定義移到開頭；加 `--list-pem`、`pem_hashes`、`unknown_pem`；`check()` 對 PEM 扣掉已知區塊；改正註解）
- Create: `image/known-pem-blocks.txt`
- Modify: `image/tests/test-image-privacy.sh`
- 不改 `image/build-image.sh`：容器裏 `/s` 就是 `image/`，清單在腳本旁邊，`$(dirname "$0")` 找得到。

### Task 1: 掃描腳本

**Interfaces:**
- Produces: `check-image-privacy.sh --list-pem FILE`：FILE 裏每組完整 PEM 私鑰區塊的 sha256，一行一個（區塊原樣的位元組，不做任何轉換），grep 或 split 出錯結束碼 2；`image/known-pem-blocks.txt`：每行開頭 64 個小寫十六進位字元是一個雜湊，`#` 開頭是註解。

- [ ] **把 `set -eu`、`export LC_ALL=C` 之後、`IMG=` 之前改成下面這樣**（原本第 58–81 行的註解和定義整段移上來，內容只改第 62–63 行那句；`PEM` 和 `BLOCK` 是新的；原本第 82 行改用 `$PEM`；`T=` 那兩行從原位置移上來）：

```sh
set -eu
export LC_ALL=C
# a real PEM block: the header, optional encryption headers (Proc-Type, DEK-Info), then 40 base64
# characters with any whitespace between them (any line width, indented as in YAML, spaces inside a
# line). Inside a JSON string (a service-account key file) whitespace may be escaped (\n, \r, \t,
# \u000a...) and so may each character of the header and the base64 (P, \/, M...). The
# header alone in quotes (cryptography's ssh.py) is no key. Prose right after an unquoted header can
# match as well: a false alarm stops the build, the safe side. Stock Ubuntu has real ones: libgnutls
# carries GnuTLS's self-test keys, whole blocks listed in known-pem-blocks.txt and not counted.
# No start-of-line anchor (in a raw image a key can follow zero bytes); -z splits on NUL so the
# pattern can span lines.
# shortcut: matches PEM as plain text, indented and inside a JSON string; base64-, URL- or
# HTML-encoded or archived keys are not matched. A key file sanitize let through already fails
# check-rootfs.sh (home, .ssh and /root layout); upgrade if a real capture shows a key in another form.
# a literal as a pattern that takes each character as itself or as JSON's \u00XX
jlit() {
    printf '%s' "$1" | od -An -tx1 -v | tr ' ' '\n' | while read -r h; do
        if [ -n "$h" ]; then printf '(?:\\x%s|\\\\u00(?i:%s))' "$h" "$h"; fi
    done
}
SEP='(?:\s|\\[nrt]|\\u00(?:0[9aAdD]|20))*'
NL='(?:\n|\\n|\\u000[aAdD])'
# a base64 character as itself, as \/, or as \u00XX (A-Z 41-5a, a-z 61-7a, 0-9 30-39, + 2b, / 2f, = 3d)
BODY='(?:[A-Za-z0-9+/=]|\\/|\\u00(?i:[46][1-9a-f]|[57][0-9a]|3[0-9d]|2[bf]))'
# the header's key type (RSA, EC, OPENSSH, ENCRYPTED...) and an encryption header's name, likewise
TYPE='(?:[A-Z ]|\\u00(?i:4[1-9a-f]|5[0-9a]|20))*'
NAME='(?:[A-Za-z-]|\\u00(?i:[46][1-9a-f]|[57][0-9a]|2d))+(?::|\\u00(?i:3a))'
PEM="$(jlit '-----BEGIN ')$TYPE$(jlit 'PRIVATE KEY-----')$SEP(?:${NAME}[^\\n]*?$NL$SEP)*(?:$BODY$SEP){40}"
# a whole block: the key up to its END line. 8 KiB covers the known ones; a longer block is not
# matched, so it is never taken for a known one
BLOCK="$PEM[\\s\\S]{0,8192}?$(jlit '-----END ')$TYPE$(jlit 'PRIVATE KEY-----')"
# the secrets, cleaned, in a private file: grep reads them from there, never from its command line
# (ps shows that), and no path printed below may contain one
T=$(umask 077 && mktemp -d); trap 'rm -rf "$T"' EXIT
# pem_hashes FILE: the sha256 of each whole block in FILE (its exact bytes), one per line, never the
# block; 2 when grep or split fails (grep's message can name a path). grep -o ends each block with
# NUL; split makes one file per block and head drops that NUL
pem_hashes() {
    grep -a -o -Pz -e "$BLOCK" -- "$1" > "$T/b" 2>/dev/null || [ $? = 1 ] || return 2
    rm -rf "$T/blk"; mkdir "$T/blk"
    split -t '\0' -l 1 -a 6 - "$T/blk/b" < "$T/b" || return 2
    for b in "$T"/blk/b*; do
        [ -e "$b" ] || continue
        head -c -1 "$b" > "$T/raw" || return 2
        d=$(sha256sum < "$T/raw") || return 2
        printf '%s\n' "${d%% *}"
    done
}
if [ "${1-}" = --list-pem ]; then
    pem_hashes "${2:?FILE}" || { echo "check-image-privacy: grep failed"; exit 2; }
    exit 0
fi
```

- [ ] **檔頭用法加一行**（第 7 行 `--test-image` 那行之後）：

```sh
#   check-image-privacy.sh --list-pem FILE          the sha256 of each whole PEM private-key block in
#                                                   FILE, for known-pem-blocks.txt (never the block)
```

- [ ] **原位置的 `T=$(umask 077 && mktemp -d); trap …` 和它上面那兩行註解刪掉**（已移上去），`: > "$T/all"` 留在原處。

- [ ] **秘密檔那段（`fi` 之後、`paths()` 之前）加入讀清單和 `unknown_pem`：**

```sh
# whole PEM blocks known to be public (known-pem-blocks.txt next to this script): not counted as keys
grep -o -E '^[0-9a-f]{64}' "$(dirname "$0")/known-pem-blocks.txt" > "$T/known" \
    || { echo "check-image-privacy: known-pem-blocks.txt missing or lists nothing"; exit 2; }
LF='
'
# unknown_pem FILE: u = the key pattern's matches in FILE less the whole blocks on the known list,
# kn = those known blocks (u below 0 cannot happen and would fail too)
unknown_pem() {
    grep -a -o -Pz -e "$PEM" -- "$1" > "$T/m" || [ $? = 1 ] \
        || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    pem_hashes "$1" > "$T/h" || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    kn=$(grep -c -x -F -f "$T/known" "$T/h") || [ "$kn" = 0 ] \
        || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    u=$(( $(tr -cd '\000' < "$T/m" | wc -c) - kn ))
}
```

- [ ] **`check()` 裏，`[ "$rc" -le 1 ] || …` 和 `printf '%-28s %s\n'` 之間加：**

```sh
    known=0
    if [ "$label" = "private keys (PEM)" ] && [ "$c" != 0 ]; then
        if [ -d "$IMG" ]; then
            printf '%s\n' "$files" > "$T/f"; files=
            while IFS= read -r hit; do
                unknown_pem "$hit"; known=$((known + kn))
                [ "$u" = 0 ] || files=${files:+$files$LF}$hit
            done < "$T/f"
            c=$(printf '%s' "$files" | grep -c '' || true)
        else
            unknown_pem "$IMG"; known=$kn; c=$u
        fi
    fi
```

並在 `printf '%-28s %s\n' "$label" "$c"` 之後加：

```sh
    [ "$known" = 0 ] || printf '    known public test keys not counted: %s\n' "$known"
```

- [ ] **原本第 82 行改成：**

```sh
check "private keys (PEM)"      -Pz -e "$PEM"
```

- [ ] **建 `image/known-pem-blocks.txt`：**

```
# Whole PEM private-key blocks that are public, by sha256, as check-image-privacy.sh --list-pem FILE
# prints them. A block on this list is not counted as a private key; any other, or one with a
# single character changed, is. Add a block only after the maintainer agreed, from the package in
# Ubuntu's archive (never from a captured tree), with where it comes from.
#
# GnuTLS 3.8.3 self-test keys (lib/crypto-selftests-pk.c: rsa_2048, dsa_2048, ecdsa secp256r1,
# secp192r1, secp224r1, secp384r1, secp521r1, gost01, gost12_256, gost12_512), compiled into
# /usr/lib/aarch64-linux-gnu/libgnutls.so.30.37.1 of libgnutls30t64 3.8.3-1.1ubuntu3.6 arm64
# (file sha256 17ffd34fd0bc239903ca37e95bb14eab6ee986c8d1260a5a08f16e0bfc669739). A GnuTLS upgrade
# that changes them fails the build: regenerate from the new .deb.
934b3e9bfd9936c5e30c7f0ed7d36a05e2044f755c0aa433e1d6bef6a68d1391
a0b9679665e29ac220dfb0b366317e1b9dd5fe31e9def8b2e511669a041389ae
91ea1699ff6b1a34b4a1d500a9c75a808441e47b9ea68da6fb0195e01ce1dc61
293216817f0d585f0b54f225582f59e7b2e2a795b5f8002e2d71c5e3d49ce9b0
f8766749b0c6f9b5661364568226af0ba7ae8d87c0073df24e440de4417521cd
d039c8119a029ab9f9c83c04d67002d887b6bc6026c4264402ab27cdf24cf138
7c4c63ee462e0e700cd9e29c8e0f730b3f1b484c4abdd83f1e69fcd477c061fa
ef237ea8db4f2ae9ee100e8ced96d29b5dceb0e6a948443e6b8a00b1791f9ec9
fa0b06a72461ec0a963dcfccb8d5b61bd88a6074fc7271573bff68ab86b8c1af
a4d138d7ef9748464117b44fb9c0a4b5b85a1599a127d02690abaa96d03c16e6
```

（這 10 行是原型的輸出；Task 2 用改好的腳本從 `.deb` 重新產生並比對，不同就用新的並查原因。）

### Task 2: 測試和清單的來源

- [ ] **`image/tests/test-image-privacy.sh`：`expect()` 改用 `$CHK`**（同一支腳本，之後的測試可以換成旁邊放了測試清單的副本）：

```sh
CHK=$IMG/check-image-privacy.sh
expect() {  # label, wanted exit code, image file, secrets argument
    n=$((n + 1)); rc=0
    sh "$CHK" "$3" "$4" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "$2" ]; then echo "ok $n - $1"; else echo "not ok $n - $1 (exit $rc, wanted $2)"; failed=1; fi
}
```

- [ ] **`echo "1..$n"` 之前加：**

```sh
# known-pem-blocks.txt: a whole block on the list is not counted, anything else is. The script reads
# the list next to itself, so a copy gets a list of this run's own key (wrap32), made by --list-pem
n=$((n + 1))
mkdir "$T/kn"; cp "$IMG/check-image-privacy.sh" "$T/kn/"
sh "$T/kn/check-image-privacy.sh" --list-pem "$T/wrap32.pem" > "$T/kn/known-pem-blocks.txt"
if [ "$(grep -c -x -E '[0-9a-f]{64}' "$T/kn/known-pem-blocks.txt")" = 1 ] \
    && [ "$(wc -l < "$T/kn/known-pem-blocks.txt")" = 1 ]; then
    echo "ok $n - --list-pem prints one hash per block and nothing else"
else echo "not ok $n - --list-pem prints one hash per block and nothing else"; failed=1; fi
awk 'NR == 2 { c = substr($0, 1, 1); $0 = (c == "A" ? "B" : "A") substr($0, 2) } { print }' "$T/wrap32.pem" > "$T/changed.pem"
sed '$d' "$T/wrap32.pem" > "$T/noend.pem"
{ cat "$T/clean.img"; cat "$T/changed.pem"; } > "$T/changed.img"
{ cat "$T/clean.img"; cat "$T/noend.pem"; } > "$T/noend.img"
{ cat "$T/wrap32.img"; cat "$T/wrap8.pem"; } > "$T/known-other.img"
mkdir "$T/tree-known" "$T/tree-known-other"
cp "$T/wrap32.img" "$T/tree-known/lib.so"
cp "$T/wrap32.img" "$T/tree-known-other/lib.so"; cp "$T/wrap8.pem" "$T/tree-known-other/other.pem"
CHK=$T/kn/check-image-privacy.sh
expect "a known block in an image passes" 0 "$T/wrap32.img" "$T/secrets"
expect "a known block in a file tree passes" 0 "$T/tree-known" "$T/secrets"
expect "a known block and another key in one image fails" 1 "$T/known-other.img" "$T/secrets"
expect "a known block and another key in a file tree fails" 1 "$T/tree-known-other" "$T/secrets"
expect "a known block with one character changed fails" 1 "$T/changed.img" "$T/secrets"
expect "a known block without its END line fails" 1 "$T/noend.img" "$T/secrets"
expect "a key not on the list still fails" 1 "$T/wrap8.img" "$T/secrets"
n=$((n + 1))
out=$(sh "$CHK" "$T/tree-known-other" "$T/secrets" 2>&1) || true
if printf '%s' "$out" | grep -q 'other.pem' && ! printf '%s' "$out" | grep -q 'lib.so' \
    && printf '%s' "$out" | grep -q 'known public test keys not counted: 1'; then
    echo "ok $n - a tree names only the file with an unknown key and counts the known one"
else echo "not ok $n - a tree names only the file with an unknown key and counts the known one"; failed=1; fi
mkdir "$T/nolist"; cp "$IMG/check-image-privacy.sh" "$T/nolist/"
CHK=$T/nolist/check-image-privacy.sh
expect "no known-pem-blocks.txt: refused" 2 "$T/clean.img" "$T/secrets"
CHK=$IMG/check-image-privacy.sh
n=$((n + 1))
if [ "$(grep -c -x -E '[0-9a-f]{64}' "$IMG/known-pem-blocks.txt")" = 10 ] \
    && [ "$(grep -x -E '[0-9a-f]{64}' "$IMG/known-pem-blocks.txt" | sort -u | wc -l)" = 10 ]; then
    echo "ok $n - the committed list holds 10 distinct hashes"
else echo "not ok $n - the committed list holds 10 distinct hashes"; failed=1; fi
```

（現有的 PEM 測試沿用 `$IMG` 的正式清單，等於確認正式清單沒有放行這次產生的任何金鑰。）

- [ ] **跑測試：** `sg docker -c 'bash ~/tsimg/image-tests.sh'`。Expected：三個 `exit 0`，沒有 `not ok`。`shellcheck image/check-image-privacy.sh image/tests/test-image-privacy.sh` 沒有新的警告。

- [ ] **清單的來源：** 用改好的腳本從官方 `.deb` 產生，跟清單比對，並核對上游原始碼的金鑰數：

```bash
( set -euo pipefail
D=$(mktemp -d); cd "$D"
curl -fsSLO http://ports.ubuntu.com/ubuntu-ports/pool/main/g/gnutls28/libgnutls30t64_3.8.3-1.1ubuntu3.6_arm64.deb
echo "18482c85067bcc8e2b3802d7c3bb87bd54acf4da228e760054e88ef1e125d80a  libgnutls30t64_3.8.3-1.1ubuntu3.6_arm64.deb" | sha256sum -c
dpkg-deb -x libgnutls30t64_3.8.3-1.1ubuntu3.6_arm64.deb x
sh ~/Projects/ohimsmart/image/check-image-privacy.sh --list-pem x/usr/lib/aarch64-linux-gnu/libgnutls.so.30.37.1 > deb.txt
grep -x -E '[0-9a-f]{64}' ~/Projects/ohimsmart/image/known-pem-blocks.txt | diff - deb.txt
curl -fsSL -o pk.c https://gitlab.com/gnutls/gnutls/-/raw/3.8.3/lib/crypto-selftests-pk.c
test "$(grep -c 'BEGIN [A-Z ]*PRIVATE KEY' pk.c)" = 10
cd /; rm -rf "$D"; echo provenance-ok )
```

Expected：`OK`（.deb 雜湊）、`diff` 沒有輸出、`provenance-ok`。結果記進 `~/tsimg/record.md`。

### Task 3: 重新打包，回到修正計劃

- [ ] 照 `2026-11-17-image-capture-fixes.md` Task 4 第一步跑 `sg docker -c 'bash ~/tsimg/test-image.sh'`（母機沒變，重新擷取也無妨）。Expected：四次 `privacy check ok`；檔案樹那次 `private keys (PEM) 0` 和 `known public test keys not counted: 10`；整個磁碟映像那次 `private keys (PEM) 0`；產生 `-TEST-DO-NOT-PUBLISH.img.xz`。`privacy check over the whole image` 花的時間記進 `~/tsimg/record.md`。
- [ ] boot、initramfs、整個磁碟映像的掃描這是第一次跑真實資料：任何未知的命中（`private keys (PEM)` 不是 0，或別的項目）照映像計劃 Task 8 的表查清楚、回報，不在這裏再放寬。磁碟映像裏若因為檔案分散在不相連的區塊而把已知區塊切開，會算成未知：停下回報。
- [ ] 通過後照修正計劃 Task 4 的 **Commit** 步驟，`git add` 另加 `image/check-image-privacy.sh image/known-pem-blocks.txt image/tests/test-image-privacy.sh docs/plans/2026-11-18-privacy-known-pem.md`，Litmus 後 commit，之後照 5b Task 7 的順序做下去。

## 實作偏差（審查第 1 輪仲裁確認的問題，2026-11-18 實作時修正）

- **檔名含換行（high）：** 計劃的檔案樹掃描用換行分開 `grep -l` 的檔名，`a` 旁邊放一個 `a<換行>` 的金鑰檔就會被當成 `a` 重掃而漏掉。實作：檔案樹的 `grep` 加 `-Z`（檔名以 NUL 結尾），`c` 數 NUL；任何命中檔名含換行時不扣已知區塊（每個命中都算）。測試 49、50。
- **grep 的錯誤訊息（medium）：** 新加的 grep 都加 `2>/dev/null`（錯誤訊息會帶路徑，路徑可能含秘密），失敗照樣結束碼 2。
- **shellcheck SC1087（medium）：** `BLOCK="${PEM}[…"`。
- 小項：`--list-pem` 的檔名照 IMG 的做法加 `./`（`-` 是檔名不是 stdin，測試 52）；另加「同一已知區塊出現兩次通過」「最後一行改一個字失敗」兩個測試；檔頭補上結束碼 2 的新情形。
- **雜湊方法（Litmus high）：** 原本把換行換成 `\001` 再算雜湊，區塊裏原有的 `\001` 跟換行算出同一個雜湊，改過位元組的已知區塊會被放行（舊版實測確實放行）。實作改成每組區塊原樣算雜湊：`grep -o` 輸出以 NUL 分隔，`split -t '\0' -l 1` 一組一檔，`head -c -1` 去掉 NUL 後 `sha256sum`。清單從官方 `.deb` 重新產生（上面的 10 行已換成新值；沒有內部換行的兩組不變）。測試 48：換行改成 `\001` 的已知區塊失敗。
- 結果：`sh image/tests/test-image-privacy.sh` 55 項全過；`shellcheck` 兩個檔都沒有警告；`--list-pem` 對官方 `.deb` 的函式庫印出的 10 個雜湊跟清單相同。

## 不在這份計劃裏

- 其他套件裏的測試金鑰：打包時出現才查、回報、經維護者同意後照清單檔頭的做法加。
- 映像計劃 Task 8 處理表那一列的文字：不改；這份計劃和清單檔頭就是那一列「回報」之後的處理方式。

<!-- design-review-coverage: FULL 3/3  -->

<!-- design-reviewed: PASS -->
