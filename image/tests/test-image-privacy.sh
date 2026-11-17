#!/bin/sh
# check-image-privacy.sh on small synthetic images:  sh image/tests/test-image-privacy.sh
set -eu
IMG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; failed=0
CHK=$IMG/check-image-privacy.sh
expect() {  # label, wanted exit code, image file, secrets argument
    n=$((n + 1)); rc=0
    sh "$CHK" "$3" "$4" >/dev/null 2>&1 || rc=$?
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
# an Ed25519 key in PEM with its base64 wrapped at 32 and at 8 characters
for w in 32 8; do
    openssl genpkey -algorithm ed25519 2>/dev/null | {
        read -r head; body=$(grep -v -e -----)
        printf '%s\n' "$head"; printf '%s' "$body" | tr -d '\n' | fold -w "$w"; printf '\n-----END PRIVATE KEY-----\n'
    } > "$T/wrap$w.pem"
    { cat "$T/clean.img"; cat "$T/wrap$w.pem"; } > "$T/wrap$w.img"
done
# the same key indented, as in a YAML file
{ cat "$T/clean.img"; sed 's/^/    /' "$T/wrap32.pem"; } > "$T/indent.img"
# keys in JSON strings, lines joined by a literal \n: a service-account file, an encrypted RSA key
for k in wrap32 enc; do
    { cat "$T/clean.img"; printf '{"private_key": "'; awk 'BEGIN { ORS = "\\n" } { print }' "$T/$k.pem"; printf '"}\n'; } > "$T/json-$k.img"
done
# the same with \u000a for the line breaks (JSON allows any character as \uXXXX)
{ cat "$T/clean.img"; printf '{"private_key": "'; awk 'BEGIN { ORS = "\\u000a" } { print }' "$T/enc.pem"; printf '"}\n'; } > "$T/json-u.img"
# a key in a JSON string with every base64 character written \u00XX (header put together at run time)
u=$(grep -v -e ----- "$T/wrap32.pem" | tr -d '\n' | od -An -tx1 -v | tr -s ' \n' '  ' | sed 's/ \([0-9a-f][0-9a-f]\)/\\u00\1/g; s/ //g')
{ cat "$T/clean.img"; printf '{"k": "-----BEGIN %s-----\\n%s\\n-----END %s-----\\n"}\n' 'PRIVATE KEY' "$u" 'PRIVATE KEY'; } > "$T/json-uall.img"
# and the header too, every character of it (an encrypted RSA key, so Proc-Type and DEK-Info as well)
u=$(od -An -tx1 -v < "$T/enc.pem" | tr -s ' \n' '  ' | sed 's/ \([0-9a-f][0-9a-f]\)/\\u00\1/g; s/ //g')
{ cat "$T/clean.img"; printf '{"k": "%s"}\n' "$u"; } > "$T/json-uhead.img"
# the 8-wrapped key with a space inside every line
{ cat "$T/clean.img"; sed '/-----/!s/^\(....\)/\1 /' "$T/wrap8.pem"; } > "$T/spaced.img"
# and with / written \/, as JSON may (made-up base64 with a slash early on; the header is put
# together at run time, or gitleaks takes this test line for a key)
b64='MC4C/AQAw/BQYD/K2Vw/BCIE/IabC/deFg/hiJk/lmNo/pqRs/tuVw'
{ cat "$T/clean.img"; printf '{"private_key": "-----BEGIN %s-----\\n%s\\n-----END %s-----\\n"}\n' \
    'PRIVATE KEY' "$(printf '%s' "$b64" | sed 's|/|\\/|g')" 'PRIVATE KEY'; } > "$T/json-slash.img"
# grep that writes down its arguments, to show a secret never reaches a command line
mkdir "$T/shim"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s/argv\nexec %s "$@"\n' "$T" "$(command -v grep)" > "$T/shim/grep"
chmod +x "$T/shim/grep"
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
expect "PEM key wrapped at 32 characters fails" 1 "$T/wrap32.img" "$T/secrets"
expect "PEM key wrapped at 8 characters fails" 1 "$T/wrap8.img" "$T/secrets"
expect "indented PEM key fails" 1 "$T/indent.img" "$T/secrets"
expect "PEM key in a JSON string fails" 1 "$T/json-wrap32.img" "$T/secrets"
expect "encrypted PEM key in a JSON string fails" 1 "$T/json-enc.img" "$T/secrets"
expect "PEM key in a JSON string with \\/ fails" 1 "$T/json-slash.img" "$T/secrets"
expect "PEM key in a JSON string with \\u000a fails" 1 "$T/json-u.img" "$T/secrets"
expect "PEM key with spaces inside its lines fails" 1 "$T/spaced.img" "$T/secrets"
expect "PEM key in JSON with \\u00XX for each character fails" 1 "$T/json-uall.img" "$T/secrets"
expect "PEM key in JSON with its header as \\u00XX too fails" 1 "$T/json-uhead.img" "$T/secrets"
printf 'x = "-----BEGIN PRIVATE KEY-----"\nThe header above is only a string.\n' > "$T/prose.img"
expect "PEM header followed by prose passes" 0 "$T/prose.img" "$T/secrets"
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
n=$((n + 1))
mkdir -p "$T/tree-named/home/my-wifi-name/.ssh"; cp "$T/k" "$T/tree-named/home/my-wifi-name/.ssh/id_ed25519"
out=$(sh "$IMG/check-image-privacy.sh" "$T/tree-named" "$T/secrets" 2>&1) && rc=0 || rc=$?
if [ "$rc" = 1 ] && ! printf '%s' "$out" | grep -q my-wifi-name; then
    echo "ok $n - a key hit's path that names a secret is not printed"
else echo "not ok $n - a key hit's path that names a secret is not printed (exit $rc)"; failed=1; fi
n=$((n + 1))
J='x|y|;e touch sed-ran;#'
mkdir "$T/$J"; cp "$T/k" "$T/$J/id_ed25519"
(cd "$T" && sh "$IMG/check-image-privacy.sh" "$T/$J" "$T/secrets" >/dev/null 2>&1) || true
if [ -e "$T/sed-ran" ]; then echo "not ok $n - a directory name runs no command"; failed=1
else echo "ok $n - a directory name runs no command"; fi
n=$((n + 1))
mkdir -p "$T/tree-err/my-wifi-name"; echo x > "$T/tree-err/my-wifi-name/f"; chmod 000 "$T/tree-err/my-wifi-name/f"
out=$(sh "$IMG/check-image-privacy.sh" "$T/tree-err" "$T/secrets" 2>&1) || true
out=$out$(sh "$IMG/check-image-privacy.sh" "$T/missing-my-wifi-name.img" "$T/secrets" 2>&1) || true
chmod 600 "$T/tree-err/my-wifi-name/f"
if printf '%s' "$out" | grep -q my-wifi-name; then echo "not ok $n - a read error names no secret"; failed=1
else echo "ok $n - a read error names no secret"; fi
n=$((n + 1)); rc=0
(cd "$T" && sh "$IMG/check-image-privacy.sh" '--exclude=*' "$T/secrets" </dev/null >/dev/null 2>&1) || rc=$?
if [ "$rc" = 2 ]; then echo "ok $n - an image named like an option is a missing image"
else echo "not ok $n - an image named like an option is a missing image (exit $rc, wanted 2)"; failed=1; fi
n=$((n + 1)); rc=0
mkdir "$T/dash"; cp "$T/key.img" "$T/dash/-"
(cd "$T/dash" && sh "$IMG/check-image-privacy.sh" - "$T/secrets" </dev/null >/dev/null 2>&1) || rc=$?
if [ "$rc" = 1 ]; then echo "ok $n - an image named - is that file, not stdin"
else echo "not ok $n - an image named - is that file, not stdin (exit $rc, wanted 1)"; failed=1; fi
n=$((n + 1))
PATH="$T/shim:$PATH" sh "$IMG/check-image-privacy.sh" "$T/secret.img" "$T/secrets" >/dev/null 2>&1 || true
if [ -s "$T/argv" ] && ! grep -q my-wifi-name "$T/argv"; then
    echo "ok $n - a secret never reaches grep's command line"
else echo "not ok $n - a secret never reaches grep's command line"; failed=1; fi
# known-pem-blocks.txt: a whole block on the list is not counted, anything else is. The script reads
# the list next to itself, so a copy gets a list of this run's own key (wrap32), made by --list-pem
n=$((n + 1))
mkdir "$T/kn"; cp "$IMG/check-image-privacy.sh" "$T/kn/"
sh "$T/kn/check-image-privacy.sh" --list-pem "$T/wrap32.pem" > "$T/kn/known-pem-blocks.txt"
if [ "$(grep -c -x -E '[0-9a-f]{64}' "$T/kn/known-pem-blocks.txt")" = 1 ] \
    && [ "$(wc -l < "$T/kn/known-pem-blocks.txt")" = 1 ]; then
    echo "ok $n - --list-pem prints one hash per block and nothing else"
else echo "not ok $n - --list-pem prints one hash per block and nothing else"; failed=1; fi
# one character changed: in the first base64 line (inside the 40 the key pattern needs) and in the last
awk 'NR == 2 { c = substr($0, 1, 1); $0 = (c == "A" ? "B" : "A") substr($0, 2) } { print }' "$T/wrap32.pem" > "$T/changed.pem"
awk -v last="$(($(wc -l < "$T/wrap32.pem") - 1))" \
    'NR == last { c = substr($0, 1, 1); $0 = (c == "A" ? "B" : "A") substr($0, 2) } { print }' "$T/wrap32.pem" > "$T/changed-end.pem"
sed '$d' "$T/wrap32.pem" > "$T/noend.pem"
# a line break past the first 40 characters turned into byte 01 (the bytes are hashed as they are)
{ sed -n 1,2p "$T/wrap32.pem"; sed -n 3p "$T/wrap32.pem" | tr -d '\n'; printf '\001'; sed -n '4,$p' "$T/wrap32.pem"; } > "$T/ctrl.pem"
for k in changed changed-end noend ctrl; do { cat "$T/clean.img"; cat "$T/$k.pem"; } > "$T/$k.img"; done
{ cat "$T/wrap32.img"; cat "$T/wrap8.pem"; } > "$T/known-other.img"
{ cat "$T/wrap32.img"; cat "$T/wrap32.pem"; } > "$T/known-twice.img"
mkdir "$T/tree-known" "$T/tree-known-other" "$T/tree-lf" "$T/tree-lf-known"
cp "$T/wrap32.img" "$T/tree-known/lib.so"
cp "$T/wrap32.img" "$T/tree-known-other/lib.so"; cp "$T/wrap8.pem" "$T/tree-known-other/other.pem"
# a name with a line break must not let an unknown key pass as the file the first line names
cp "$T/clean.img" "$T/tree-lf/a"; cp "$T/wrap8.pem" "$T/tree-lf/a
"
cp "$T/wrap32.img" "$T/tree-lf-known/lib.so"; cp "$T/wrap8.pem" "$T/tree-lf-known/lib.so
"
CHK=$T/kn/check-image-privacy.sh
expect "a known block in an image passes" 0 "$T/wrap32.img" "$T/secrets"
expect "a known block in a file tree passes" 0 "$T/tree-known" "$T/secrets"
expect "the same known block twice passes" 0 "$T/known-twice.img" "$T/secrets"
expect "a known block and another key in one image fails" 1 "$T/known-other.img" "$T/secrets"
expect "a known block and another key in a file tree fails" 1 "$T/tree-known-other" "$T/secrets"
expect "a known block with a character changed early fails" 1 "$T/changed.img" "$T/secrets"
expect "a known block with a character changed late fails" 1 "$T/changed-end.img" "$T/secrets"
expect "a known block without its END line fails" 1 "$T/noend.img" "$T/secrets"
expect "a known block with a line break turned into 01 fails" 1 "$T/ctrl.img" "$T/secrets"
expect "a key not on the list still fails" 1 "$T/wrap8.img" "$T/secrets"
expect "a key in a file whose name has a line break fails" 1 "$T/tree-lf" "$T/secrets"
expect "the same next to a known block fails" 1 "$T/tree-lf-known" "$T/secrets"
n=$((n + 1))
out=$(sh "$CHK" "$T/tree-known-other" "$T/secrets" 2>&1) || true
if printf '%s' "$out" | grep -q 'other.pem' && ! printf '%s' "$out" | grep -q 'lib.so' \
    && printf '%s' "$out" | grep -q 'known public test keys not counted: 1'; then
    echo "ok $n - a tree names only the file with an unknown key and counts the known one"
else echo "not ok $n - a tree names only the file with an unknown key and counts the known one"; failed=1; fi
n=$((n + 1)); rc=0
out=$(cd "$T/dash" && sh "$CHK" --list-pem - < "$T/wrap32.pem") || rc=$?
if [ "$rc" = 0 ] && [ -n "$out" ] && [ "$out" = "$(sh "$CHK" --list-pem "$T/dash/-")" ] \
    && [ "$out" != "$(cat "$T/kn/known-pem-blocks.txt")" ]; then
    echo "ok $n - --list-pem - is the file named -, not stdin"
else echo "not ok $n - --list-pem - is the file named -, not stdin (exit $rc)"; failed=1; fi
mkdir "$T/nolist"; cp "$IMG/check-image-privacy.sh" "$T/nolist/"
CHK=$T/nolist/check-image-privacy.sh
expect "no known-pem-blocks.txt: refused" 2 "$T/clean.img" "$T/secrets"
CHK=$IMG/check-image-privacy.sh
n=$((n + 1))
if [ "$(grep -c -x -E '[0-9a-f]{64}' "$IMG/known-pem-blocks.txt")" = 10 ] \
    && [ "$(grep -x -E '[0-9a-f]{64}' "$IMG/known-pem-blocks.txt" | sort -u | wc -l)" = 10 ]; then
    echo "ok $n - the committed list holds 10 distinct hashes"
else echo "not ok $n - the committed list holds 10 distinct hashes"; failed=1; fi
echo "1..$n"
exit "$failed"
