#!/bin/sh
# Privacy scan (spec §5.3 point 5) of the root file tree before mke2fs, and again of the raw bytes
# of the finished disk.img (every byte that ships, metadata included). The tree pass also catches a
# string mke2fs would split across non-adjacent blocks.
#   check-image-privacy.sh IMAGE|DIR SECRETS_FILE   one literal per line: Wi-Fi names, API keys,
#                                                   e-mail... (a trailing CR is dropped; blank lines skipped)
#   check-image-privacy.sh IMAGE|DIR --test-image   no owner secrets checked; such an image is never published
#   check-image-privacy.sh --list-pem FILE          the sha256 of each whole PEM private-key block in
#                                                   FILE, for known-pem-blocks.txt (never the block)
# Exit 0 clean, 1 something found, 2 a missing/empty secrets file, no known-pem-blocks.txt or a grep
# error. Prints counts (lines in an image, files in a tree), never what matched. In a tree, a key
# pattern's hit also prints the file paths (up to 20, none that names an owner secret) so it can be
# found; an owner secret's hit never does, since a Wi-Fi name can be part of a file name.
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
# a whole block: the key up to its END line. 8 KiB past the first 40 characters covers the known
# ones; a longer block is not matched, so it is never taken for a known one
BLOCK="${PEM}[\\s\\S]{0,8192}?$(jlit '-----END ')$TYPE$(jlit 'PRIVATE KEY-----')"
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
    F=${2:?FILE}
    # a path grep cannot take for stdin ("-")
    case $F in /*) ;; *) F=./$F ;; esac
    pem_hashes "$F" || { echo "check-image-privacy: grep failed"; exit 2; }
    exit 0
fi
IMG=${1:?image}; SECRETS=${2:?SECRETS_FILE or --test-image}
# a path grep cannot take for an option or for stdin ("-"), and one that is there
case $IMG in /*) ;; *) IMG=./$IMG ;; esac
[ -e "$IMG" ] || { echo "check-image-privacy: no image or file tree at the given path"; exit 2; }
fail=0
: > "$T/all"
if [ "$SECRETS" != --test-image ]; then
    [ -f "$SECRETS" ] || { echo "check-image-privacy: no secrets file $SECRETS"; exit 2; }
    cr=$(printf '\r')
    while IFS= read -r s || [ -n "$s" ]; do
        s=${s%"$cr"}
        case $s in *[![:space:]]*) printf '%s\n' "$s" >> "$T/all" ;; esac
    done < "$SECRETS"
    [ -s "$T/all" ] || { echo "check-image-privacy: $SECRETS lists nothing"; exit 2; }
fi
# whole PEM blocks known to be public (known-pem-blocks.txt next to this script): not counted as keys
grep -o -E '^[0-9a-f]{64}' "$(dirname "$0")/known-pem-blocks.txt" > "$T/known" 2>/dev/null \
    || { echo "check-image-privacy: known-pem-blocks.txt missing or lists nothing"; exit 2; }
LF='
'
# unknown_pem FILE: u = the key pattern's matches in FILE less the whole blocks on the known list,
# kn = those known blocks (u below 0 cannot happen and would fail too)
unknown_pem() {
    grep -a -o -Pz -e "$PEM" -- "$1" > "$T/m" 2>/dev/null || [ $? = 1 ] \
        || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    pem_hashes "$1" > "$T/h" || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    kn=$(grep -c -x -F -f "$T/known" "$T/h") || [ "$kn" = 0 ] \
        || { echo "check-image-privacy: grep failed for private keys (PEM)"; exit 2; }
    u=$(( $(tr -cd '\000' < "$T/m" | wc -c) - kn ))
}
# file paths of a hit, up to 20, minus any that name an owner secret
paths() {
    # (the prefix cut in the shell: IMG in a sed program could carry sed commands)
    printf '%s\n' "$files" | head -20 | while IFS= read -r l; do printf '    %s\n' "${l#"$IMG"}"; done > "$T/paths"
    if [ -s "$T/all" ]; then grep -v -F -f "$T/all" "$T/paths" || true; else cat "$T/paths"; fi
}
check() {  # label, then grep arguments
    label=$1; shift
    rc=0; known=0
    if [ -d "$IMG" ]; then
        # (grep's own messages name paths, which can hold a secret: its exit status is enough)
        # names end in NUL (-Z), so a line break inside a name cannot pass for two names
        grep -r -D skip -a -l -Z "$@" -- "$IMG" > "$T/f0" 2>/dev/null || rc=$?
        c=$(tr -cd '\000' < "$T/f0" | wc -c)
        files=$(tr '\000' '\n' < "$T/f0")
    else
        c=$(grep -a -c "$@" -- "$IMG" 2>/dev/null) || rc=$?
    fi
    [ "$rc" -le 1 ] || { echo "check-image-privacy: grep failed for $label"; exit 2; }
    # the PEM hits less the whole blocks on known-pem-blocks.txt. In a tree only when no hit's name
    # holds a line break: such names cannot be read back one per line, so then every hit counts
    if [ "$label" = "private keys (PEM)" ] && [ "$c" != 0 ]; then
        if [ ! -d "$IMG" ]; then
            unknown_pem "$IMG"; known=$kn; c=$u
        elif [ "$(tr -cd '\n' < "$T/f0" | wc -c)" = 0 ]; then
            tr '\000' '\n' < "$T/f0" > "$T/f"; files=
            while IFS= read -r hit; do
                unknown_pem "$hit"; known=$((known + kn))
                [ "$u" = 0 ] || files=${files:+$files$LF}$hit
            done < "$T/f"
            c=$(printf '%s' "$files" | grep -c '' || true)
        fi
    fi
    printf '%-28s %s\n' "$label" "$c"
    [ "$known" = 0 ] || printf '    known public test keys not counted: %s\n' "$known"
    [ "$c" = 0 ] || fail=1
    case $label in
        "owner secret"*) ;;
        *) if [ -d "$IMG" ] && [ "$c" != 0 ]; then paths; fi ;;
    esac
}
check "ssh-ed25519 public keys" -F -e "ssh-ed25519 AAAA"
check "ssh-rsa public keys"     -F -e "ssh-rsa AAAA"
check "private keys (PEM)"      -Pz -e "$PEM"
# Real keys are long runs; "sk-"/"xai-" alone match ordinary words (disk-, ssh-sk-helper). A key
# starts after a non-key character: "sk-" inside a base64url hash (a wheel's RECORD) is no key.
check "sk- API keys"            -P -e '(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{32,}'
check "xai- API keys"           -E -e "xai-[A-Za-z0-9]{32,}"
if [ "$SECRETS" = --test-image ]; then
    echo "TEST IMAGE: owner secrets not checked; never publish this image"
else
    k=0
    while IFS= read -r s; do
        k=$((k + 1))
        printf '%s\n' "$s" > "$T/s"
        check "owner secret #$k" -F -f "$T/s"
    done < "$T/all"
fi
[ "$fail" = 0 ] || { echo "privacy check FAILED"; exit 1; }
echo "privacy check ok"
