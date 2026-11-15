#!/bin/bash
# The three tutorials (README.md 简中, README.zh-Hant.md 繁中, README.en.md English) must give the
# same commands and the same web addresses (spec §7.1). Compared: every fenced block tagged bash,
# sh or powershell, after dropping comments and blank lines and treating any <…> placeholder as the
# same word (each language names its placeholders in its own words); and the set of http(s)
# addresses. Untagged blocks hold expected output or prose and are not compared. Each tutorial must
# also link to the other two. Usage: tools/check-readmes.sh [repository directory]
set -euo pipefail
export LC_ALL=C    # byte-wise and present everywhere (C.UTF-8 is not on every macOS)
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
FILES="README.md README.zh-Hant.md README.en.md"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

# Placeholders first, so that http://<设备IP>:16688 and http://<DEVICE_IP>:16688 are one address.
# A placeholder starts and ends with a non-space, has no "." or "/", and holds something other
# than lowercase ASCII letters: a tag such as <title>, or redirections such as `cat < a.img > b.img`
# and `cat <a.img>b.img`, are compared as written. perl for the lookahead; macOS and Linux ship it.
# shortcut: `cat <IN>out` would still read as a placeholder; no tutorial command redirects like that
placeholders() { perl -pe 's{<(?=[^<>./]*[^a-z<>./])[^<>./\s](?:[^<>./]*[^<>./\s])?>}{<>}g' "$1"; }

for f in $FILES; do
    [[ -f "$DIR/$f" ]] || { printf 'check-readmes: %s is missing\n' "$f" >&2; exit 1; }
    placeholders "$DIR/$f" | awk '
        /^[[:space:]]*```(bash|sh|powershell)[[:space:]]*$/ { inside = 1; n++; print "--- block " n; next }
        /^[[:space:]]*```/ { inside = 0; next }
        inside {
            sub(/^[[:space:]]+/, "")
            if ($0 ~ /^#/) next                       # a comment line
            # shortcut: " # " inside quotes is taken as a comment too; no tutorial command has one
            sub(/[[:space:]]+#[[:space:]].*$/, "")    # a comment after the command
            sub(/[[:space:]]+$/, "")
            if ($0 != "") print
        }' >"$WORK/$f.commands"
    # grep finding no address is fine; any other failure in the pipeline still stops the script.
    placeholders "$DIR/$f" | { grep -oE 'https?://[-A-Za-z0-9._~:/?#@!$&*+,;=%<>]+' || true; } |
        sed -E 's/[.,;:]+$//' | sort -u >"$WORK/$f.urls"
    for other in $FILES; do
        [[ "$other" = "$f" ]] || grep -qF "($other)" "$DIR/$f" || {
            printf 'check-readmes: %s does not link to %s\n' "$f" "$other" >&2
            fail=1
        }
    done
done

for f in README.zh-Hant.md README.en.md; do
    for kind in commands urls; do
        if ! diff -u --label "README.md ($kind)" --label "$f ($kind)" \
            "$WORK/README.md.$kind" "$WORK/$f.$kind" >"$WORK/diff"; then
            printf 'check-readmes: the %s of %s differ from README.md:\n' "$kind" "$f" >&2
            cat "$WORK/diff" >&2
            fail=1
        fi
    done
done
[[ "$fail" -eq 0 ]] && printf 'check-readmes: the three tutorials agree\n'
exit "$fail"
