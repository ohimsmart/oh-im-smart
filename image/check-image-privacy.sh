#!/bin/sh
# Privacy scan (spec §5.3 point 5) of the root file tree before mke2fs, and again of the raw bytes
# of the finished disk.img (every byte that ships, metadata included). The tree pass also catches a
# string mke2fs would split across non-adjacent blocks.
#   check-image-privacy.sh IMAGE|DIR SECRETS_FILE   one literal per line: Wi-Fi names, API keys,
#                                                   e-mail... (a trailing CR is dropped; blank lines skipped)
#   check-image-privacy.sh IMAGE|DIR --test-image   no owner secrets checked; such an image is never published
# Exit 0 clean, 1 something found, 2 a missing/empty secrets file or a grep error. Prints counts
# (lines in an image, files in a tree), never what matched. In a tree, a key pattern's hit also
# prints the file paths (up to 20, none that names an owner secret) so it can be found; an owner
# secret's hit never does, since a Wi-Fi name can be part of a file name.
set -eu
export LC_ALL=C
IMG=${1:?image}; SECRETS=${2:?SECRETS_FILE or --test-image}
# a path grep cannot take for an option or for stdin ("-"), and one that is there
case $IMG in /*) ;; *) IMG=./$IMG ;; esac
[ -e "$IMG" ] || { echo "check-image-privacy: no image or file tree at the given path"; exit 2; }
fail=0
# the secrets, cleaned, in a private file: grep reads them from there, never from its command line
# (ps shows that), and no path printed below may contain one
T=$(umask 077 && mktemp -d); trap 'rm -rf "$T"' EXIT
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
# file paths of a hit, up to 20, minus any that name an owner secret
paths() {
    # (the prefix cut in the shell: IMG in a sed program could carry sed commands)
    printf '%s\n' "$files" | head -20 | while IFS= read -r l; do printf '    %s\n' "${l#"$IMG"}"; done > "$T/paths"
    if [ -s "$T/all" ]; then grep -v -F -f "$T/all" "$T/paths" || true; else cat "$T/paths"; fi
}
check() {  # label, then grep arguments
    label=$1; shift
    rc=0
    if [ -d "$IMG" ]; then
        # (grep's own messages name paths, which can hold a secret: its exit status is enough)
        files=$(grep -r -D skip -a -l "$@" -- "$IMG" 2>/dev/null) || rc=$?
        c=$(printf '%s' "$files" | grep -c '' || true)
    else
        c=$(grep -a -c "$@" -- "$IMG" 2>/dev/null) || rc=$?
    fi
    [ "$rc" -le 1 ] || { echo "check-image-privacy: grep failed for $label"; exit 2; }
    printf '%-28s %s\n' "$label" "$c"
    [ "$c" = 0 ] || fail=1
    case $label in
        "owner secret"*) ;;
        *) if [ -d "$IMG" ] && [ "$c" != 0 ]; then paths; fi ;;
    esac
}
check "ssh-ed25519 public keys" -F -e "ssh-ed25519 AAAA"
check "ssh-rsa public keys"     -F -e "ssh-rsa AAAA"
# a real PEM block: the header, optional encryption headers (Proc-Type, DEK-Info), then 40 base64
# characters with any whitespace between them (any line width, indented as in YAML, spaces inside a
# line). Inside a JSON string (a service-account key file) whitespace may be escaped (\n, \r, \t,
# \u000a...) and so may each character of the header and the base64 (P, \/, M...). The
# header alone in quotes (cryptography's ssh.py) is no key. Prose right after an unquoted header can
# match as well: a false alarm stops the build, the safe side (none on a stock Ubuntu /usr or /etc).
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
check "private keys (PEM)"      -Pz -e "$(jlit '-----BEGIN ')$TYPE$(jlit 'PRIVATE KEY-----')$SEP(?:${NAME}[^\\n]*?$NL$SEP)*(?:$BODY$SEP){40}"
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
