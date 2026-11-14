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
set +o allexport +o xtrace            # so would an inherited SHELLOPTS; xtrace would print them
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
# Only the untouched upstream image: it ships an empty machine-id. On an image prepared before,
# debugfs would free the old WiFi file without wiping it, leaving that password in free space.
has 'stat /etc/machine-id' '^User:.* Size: 0$' ||
    die "this image was prepared before (or is not the upstream one); start again from a fresh copy"
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
# WORK goes into debugfs commands inside double quotes, which cannot hold a quote or a line break.
case $WORK in *[\"\\$'\n']*) die "the temporary directory $WORK has a quote, backslash or line break in its name: set TMPDIR to a plain path" ;; esac

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
