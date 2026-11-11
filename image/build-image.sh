#!/bin/bash
# Build the release image from a capture made by pull-from-device.sh:
#   image/build-image.sh WORK_DIR OUT_DIR HUB_REPO SECRETS_FILE|--test-image
# WORK_DIR   has root.tar.zst, boot.tar.zst, versions.txt (hub commit, client version, system layer
#            version and file-set id)
# OUT_DIR    gets <name>.img.xz, SHA256SUMS (.img.xz and .img), packages.txt
# HUB_REPO   a checkout of ohimsmart/oh-im-smart-gateway (its origin must be that repository) holding
#            the captured commit (for the config template)
# SECRETS_FILE (required; keep it outside any repository) one literal string per line that must not
#            appear anywhere in the image: Wi-Fi names, API keys, device ids, the owner's e-mail...
#            --test-image instead skips that check and names the image ...-TEST-DO-NOT-PUBLISH.
# HUB_MAIN   (environment, default origin/main, fetched first) the hub's published main: the shipped
#            commit must be on it, or every device's scripts/update.sh (git merge --ff-only) fails.
#            HUB_MAIN=main checks against the local main before it is pushed (push before releasing).
# RELEASE_MANIFEST (environment) the latest.json of the newest online update (a file, or the URL
#            https://github.com/ohimsmart/oh-im-smart-client/releases/latest/download/latest.json).
#            The image must carry exactly that client and system layer version, so a freshly flashed
#            device reports "up to date" instead of holding something no release has (publish the
#            update first, then build the image). ALLOW_UNRELEASED=1 skips this, for test images.
#
# The image is the "system" partition content, like upstream's: an MBR disk with pmOS_boot (ext2) and
# pmOS_root (ext4) at the original offsets and UUIDs, root shrunk to its content plus headroom. The
# pmOS initramfs grows root to the whole partition on first boot. Flash with: edl w system <image>
# Runs everything that needs root inside a container (image/Dockerfile); the work tree lives in a
# Docker volume so ownership, devices and capabilities survive.
set -euo pipefail
# no GIT_* variable (GIT_DIR, GIT_INDEX_FILE...) points git below at another repository or index
for v in $(compgen -e | grep '^GIT_' || true); do unset "$v"; done
WORK=$(cd "${1:?work dir}" && pwd); OUT=${2:?out dir}; HUB=$(cd "${3:?hub repo}" && pwd)
SECRETS=${4:?SECRETS_FILE (one secret per line, outside any repository) or --test-image}
if [ "$SECRETS" != --test-image ]; then
    grep -q '[^[:space:]]' "$SECRETS" || { echo "$SECRETS lists no secrets"; exit 1; }
fi
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
read -r HUB_COMMIT CLIENT_VERSION SYSTEM_VERSION SYSTEM_TREE < <(paste -sd' ' "$WORK/versions.txt")
if [ "${ALLOW_UNRELEASED:-}" != 1 ]; then
    : "${RELEASE_MANIFEST:?set RELEASE_MANIFEST to latest.json of the newest online update (or ALLOW_UNRELEASED=1)}"
    python3 - "$RELEASE_MANIFEST" "$CLIENT_VERSION" "${SYSTEM_VERSION:-}" "${SYSTEM_TREE:-}" <<'PY' || exit 1
import json, sys, urllib.request
src, client, sysv, tree = sys.argv[1:]
m = json.load(urllib.request.urlopen(src) if src.startswith('https://') else open(src))
s = m.get('system') or {}
bad = []
if m.get('version') != client:
    bad.append(f'client: image {client}, release {m.get("version")}')
if s.get('version') != sysv or s.get('tree') != tree:
    bad.append(f'system layer: image {sysv or "?"} ({tree[:12] or "?"}), release {s.get("version")} ({str(s.get("tree"))[:12]})')
if bad:
    print('the device does not carry the released versions (publish the update and install it on the device first):')
    print('\n'.join('  ' + b for b in bad))
    sys.exit(1)
print(f'image carries the released client {client} and system layer {sysv}')
PY
fi
NAME=${IMAGE_NAME:-thinksmart-ubuntu-$(date +%Y%m%d)}
GATEWAY_URL=https://github.com/ohimsmart/oh-im-smart-gateway.git
[ "$(git -C "$HUB" remote get-url origin)" = "$GATEWAY_URL" ] || {
    echo "$HUB: origin is not $GATEWAY_URL (the shipped commit must be on our gateway's main)"; exit 1; }
HUB_MAIN=${HUB_MAIN:-origin/main}
[ "$HUB_MAIN" = origin/main ] && git -C "$HUB" fetch -q origin main
git -C "$HUB" merge-base --is-ancestor "$HUB_COMMIT" "$HUB_MAIN" || {
    echo "hub commit $HUB_COMMIT is not on $HUB_MAIN: merge it into main (fast-forward) first"; exit 1; }
git -C "$HUB" show "$HUB_COMMIT:scripts/config.template.yaml" > "$WORK/hub-config.template.yaml"
if [ "$SECRETS" = --test-image ]; then : > "$WORK/secrets.txt"; else cp "$SECRETS" "$WORK/secrets.txt"; fi
# no owner-secret check, or versions no release carries: not a release
if [ "$SECRETS" = --test-image ] || [ "${ALLOW_UNRELEASED:-}" = 1 ]; then
    NAME=$NAME-TEST-DO-NOT-PUBLISH
elif ! st=$(git -C "$HERE/.." status --porcelain) || ! lv=$(git -C "$HERE/.." ls-files -v) \
        || [ -n "$st" ] || grep -q '^[a-zS]' <<< "$lv"; then
    # /repo and /s below are the work tree: a release carries what is committed, nothing else; git
    # failing refuses too (ls-files -v: lowercase is assume-unchanged, S skip-worktree, edits git
    # status does not show)
    echo "$HERE/..: uncommitted changes: commit them first (or build a test image)"; exit 1
fi

# the DMIC fix must be the codec-dmic build (it only exists on the device and in codec-dmic/out)
KO_MD5=$(awk '/snd-soc-msm8916-digital.ko/{print $1}' "$HERE/../codec-dmic/expected.md5")
DTB_MD5=$(awk '/apq8053-lenovo-cd-18781y.dtb/{print $1}' "$HERE/../codec-dmic/expected.md5")
docker build -q -t thinksmart-image "$HERE" >/dev/null 2>&1
docker volume create tsimg-work >/dev/null
# /repo: this repository, for the keep files sanitize puts in and the system layer check-rootfs compares
docker run --rm -i -v tsimg-work:/w -v "$WORK:/in:ro" -v "$OUT:/out" -v "$HERE:/s:ro" -v "$HERE/..:/repo:ro" \
    -e NAME="$NAME" -e HUB_COMMIT="$HUB_COMMIT" -e CLIENT_VERSION="$CLIENT_VERSION" -e KO_MD5="$KO_MD5" -e DTB_MD5="$DTB_MD5" \
    thinksmart-image bash -s <<'EOF'
set -euo pipefail
BOOT_UUID=35bca636-764e-4f53-b5e5-96eb774eb19e
ROOT_UUID=8b6cd6d2-cf64-4279-b1cc-426345d5b822
BOOT_START=2048 BOOT_SECTORS=509952 ROOT_START=512000
log() { echo "== $*  ($(date +%T))"; }

log "unpack"
rm -rf /w/root /w/boot /w/*.img /w/caps.txt
mkdir -p /w/root /w/boot
zstd -dc /in/root.tar.zst | tar -x --numeric-owner --xattrs --xattrs-include='*' --acls -p -C /w/root
zstd -dc /in/boot.tar.zst | tar -x --numeric-owner -p -C /w/boot
rm -f /w/boot/*.orig
R=/w/root

log "USB network: NCM instead of RNDIS (macOS has no RNDIS)"
sh /s/initramfs-usb-ncm.sh /w/boot/initramfs

log "sanitize"
# the mother device's name is an owner identifier: it must not survive anywhere (hosts, prompts, logs)
orig_host=$(cat $R/etc/hostname)
cp /s/owner-identifiers.txt /w/owner-identifiers.txt; : > /w/host.txt
case $orig_host in
    thinksmart|ubuntu|localhost|"") echo "mother hostname '$orig_host' is generic: not searched for" ;;
    *) echo "$orig_host" >> /w/owner-identifiers.txt; echo "$orig_host" > /w/host.txt ;;
esac
sh /s/sanitize-rootfs.sh $R /in/hub-config.template.yaml /repo

log "files the image must carry: DMIC fix, audio rules, ALSA plugin, user unit links"
# codec-dmic/build.sh output (codec-dmic/expected.md5): the DTB with qcom,dmic-sample-rate and the module
need() { [ -e "$1" ] || { echo "missing: ${1#$R}"; exit 1; }; }
need /w/boot/apq8053-lenovo-cd-18781y.dtb
[ "$(md5sum < /w/boot/apq8053-lenovo-cd-18781y.dtb | cut -d' ' -f1)" = "$DTB_MD5" ] \
    || { echo "/boot DTB is not the codec-dmic build: the second mic would be noise"; exit 1; }
ko=$(echo $R/usr/lib/modules/*/kernel/sound/soc/codecs/snd-soc-msm8916-digital.ko)
need "$ko"
[ "$(md5sum < "$ko" | cut -d' ' -f1)" = "$KO_MD5" ] || { echo "codec module is not the codec-dmic build"; exit 1; }
# speaker S16LE and the disabled DSP capture node; without it the speaker is almost silent
need $R/home/ubuntu/.config/wireplumber/main.lua.d/99-cd18781y-alsa.lua
# PipeWire's ALSA plugin, installed by hand, not by dpkg (device-setup.sh alsa-plugin)
need $R/usr/lib/aarch64-linux-gnu/alsa-lib/libasound_module_pcm_pipewire.so
need $R/usr/share/alsa/alsa.conf.d/50-pipewire.conf
# user units enabled (device-setup.sh files); the mic link brings it back after pipewire-pulse restarts
for l in default.target.wants/thinksmart-mic.service default.target.wants/idle-blanker.service \
         pipewire-pulse.service.wants/thinksmart-mic.service; do
    [ -L $R/home/ubuntu/.config/systemd/user/$l ] || { echo "missing user unit link: $l"; exit 1; }
done
# the tested versions stay put (device-setup.sh hold): dpkg marks them "hold ok installed"
# (/s is this directory; the list is read into a variable first so a missing file stops the build
# instead of giving the loop nothing to check)
held=$(grep -v -e '^#' -e '^[[:space:]]*$' /s/held-packages.txt)
[ -n "$held" ] || { echo "held-packages.txt is empty"; exit 1; }
n=0
for p in $held; do
    awk -v p="$p" '$0 == "Package: " p {f = 1; next} f && /^Status:/ {print; exit}' $R/var/lib/dpkg/status |
        grep -q '^Status: hold ' || { echo "not held: $p (device-setup.sh hold)"; exit 1; }
    n=$((n + 1))
done
echo "held packages: $n"
# rsyslog off (device-setup.sh tidy); the NTP= line is checked by check-rootfs.sh
[ ! -e $R/etc/systemd/system/multi-user.target.wants/rsyslog.service ] || { echo "rsyslog still enabled (device-setup.sh tidy)"; exit 1; }
# Wi-Fi power save off (device-setup.sh files)
need $R/etc/NetworkManager/conf.d/zz-thinksmart-wifi-powersave-off.conf
echo "ok"

log "no macOS leftovers"
find $R /w/boot -xdev \( -name '._*' -o -name .DS_Store -o -name __MACOSX \) > /w/macos.txt
[ ! -s /w/macos.txt ] || { echo "macOS files left (a ._ file that is not AppleDouble needs a look):"; sed "s|^/w/||" /w/macos.txt | head; exit 1; }
echo "ok"

log "hub data/ fresh, no backup copies"
# data/ holds exactly what sanitize-rootfs.sh wrote: the template config and the install marker
got=$(ls -A $R/home/ubuntu/xiaozhi-hub-server/main/xiaozhi-server/data | sort | tr '\n' ' ')
[ "$got" = ".config.yaml .install-complete " ] || { echo "hub data/ is not fresh: $got"; exit 1; }
find $R/etc $R/home $R/root $R/opt $R/usr/local -xdev \
    \( -name '*.bak*' -o -name '*.orig' -o -name '*.old' -o -name '*.save' -o -name '*~' \
       -o -name '*.dpkg-old' -o -name '*.dpkg-dist' -o -name '*.ucf-old' \) \
    -not -path '*/site-packages/*' -not -path '*/.venv/*' > /w/backups.txt
[ ! -s /w/backups.txt ] || { echo "backup copies left:"; sed "s|^$R||" /w/backups.txt | head; exit 1; }
echo "ok"

log "hub repository: $HUB_COMMIT as main, tracking origin/main"
# as the owner (uid 1000), so .git stays ubuntu's
setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/tmp \
    sh /s/clean-hub-git.sh $R/home/ubuntu/xiaozhi-hub-server "$HUB_COMMIT"

log "file tree: sources, system layer, upstream URLs, owner identifiers, accounts, home"
sh /s/check-rootfs.sh $R /w/owner-identifiers.txt /repo

log "privacy check over the file tree"
# the owner's secrets (none for a test image) and the mother device's name, which nothing may
# carry; the maintainer's identifiers are check-rootfs.sh's, which allows an attribution in a
# LICENSE (a newline between: the owner's file may lack its last one; blank lines are skipped)
{ cat /in/secrets.txt; echo; cat /w/host.txt; } > /w/secrets.txt
# a test image of a generically named device has nothing to look for
if grep -q '[^[:space:]]' /w/secrets.txt; then PRIV=/w/secrets.txt; else PRIV=--test-image; fi
sh /s/check-image-privacy.sh $R $PRIV
log "privacy check over the boot files and the unpacked initramfs"
sh /s/check-image-privacy.sh /w/boot $PRIV
# the initramfs is gzip (the NCM member too): the scan of the raw image cannot see inside it
for f in /w/boot/initramfs*; do
    gzip -dc "$f" > /w/initramfs.raw
    sh /s/check-image-privacy.sh /w/initramfs.raw $PRIV
done
rm -f /w/initramfs.raw

log "capabilities to check after mke2fs"
getcap -r $R/usr 2>/dev/null | sed "s|^$R||" > /w/caps.txt || true
cat /w/caps.txt

log "disk layout"
used_mb=$(du -s --block-size=1M -x $R | cut -f1)
files=$(find $R -xdev | wc -l)
# content + 12% + 200 MB: mke2fs metadata and the journal; first boot grows it to the whole partition
root_mb=$(( used_mb * 112 / 100 + 200 ))
root_sectors=$(( root_mb * 2048 ))
inodes=$(( files * 2 > 200000 ? files * 2 : 200000 ))
rm -f /w/disk.img
truncate -s $(( (ROOT_START + root_sectors) * 512 )) /w/disk.img
sfdisk -q /w/disk.img <<SF
label: dos
label-id: 0x37d1617d
unit: sectors
start=$BOOT_START, size=$BOOT_SECTORS, type=83
start=$ROOT_START, size=$root_sectors, type=83
SF
sfdisk -d /w/disk.img
# The filesystems are made in place (-E offset): no second copy of the root filesystem on disk
BOOT_FS="/w/disk.img?offset=$((BOOT_START*512))"
ROOT_FS="/w/disk.img?offset=$((ROOT_START*512))"

log "boot filesystem"
mke2fs -q -t ext2 -b 4096 -L pmOS_boot -U $BOOT_UUID -E root_owner=0:0,offset=$((BOOT_START*512)) \
    -d /w/boot /w/disk.img $((BOOT_SECTORS/8))
e2fsck -fn "$BOOT_FS" >/dev/null

log "root filesystem"
mke2fs -q -t ext4 -b 4096 -I 256 -N $inodes -L pmOS_root -U $ROOT_UUID \
    -O has_journal,ext_attr,resize_inode,dir_index,filetype,extent,64bit,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum,^orphan_file,^metadata_csum_seed \
    -E root_owner=0:0,offset=$((ROOT_START*512)) -d $R /w/disk.img $((root_sectors/8))
e2fsck -fn "$ROOT_FS" >/dev/null
echo "content ${used_mb} MB, $files files -> root ${root_mb} MB, $inodes inodes"
dumpe2fs -h "$ROOT_FS" 2>/dev/null | awk -F: '/^Free blocks/{printf "free in root: %d MB\n", $2*4/1024} /^Free inodes/{print "free inodes:" $2}'
while read -r path cap; do
    got=$(debugfs -R "ea_get $path security.capability" "$ROOT_FS" 2>/dev/null | head -1)
    [ -n "$got" ] || { echo "capability lost: $path ($cap)"; exit 1; }
done < /w/caps.txt
echo "capabilities kept: $(wc -l < /w/caps.txt)"
[ "$(stat -c %s /w/disk.img)" = $(( (ROOT_START + root_sectors) * 512 )) ] || { echo "mke2fs changed the image size"; exit 1; }

log "privacy check over the whole image"
# the upstream author's e-mail, LAN and proxy checks are gone (spec §5.3 point 5): ours are listed
# in SECRETS_FILE, and the maintainer's handle in owner-identifiers.txt (check-rootfs.sh)
sh /s/check-image-privacy.sh /w/disk.img $PRIV

log "package list"
awk '/^Package:/{p=$2} /^Version:/{v=$2} /^Status:/{s=$0} /^$/{if (s ~ / installed$/) print p, v; s=""}' \
    $R/var/lib/dpkg/status | sort > /out/packages.txt
wc -l < /out/packages.txt

log "compress"
mv /w/disk.img /w/$NAME.img
# -9 needs ~670 MB per thread: 4 threads fit the default Docker VM
xz -T4 -9 -c /w/$NAME.img > /out/$NAME.img.xz
# both: the compressed download, and the image after `xz -d` (sha256sum -c --ignore-missing before unpacking)
( cd /out && sha256sum $NAME.img.xz > SHA256SUMS )
( cd /w && sha256sum $NAME.img >> /out/SHA256SUMS )
echo "$NAME.img $(stat -c %s /w/$NAME.img) bytes, sha256 $(sha256sum /w/$NAME.img | cut -d' ' -f1)" > /out/image-info.txt
rm -f /w/$NAME.img
ls -l /out
cat /out/image-info.txt
EOF
