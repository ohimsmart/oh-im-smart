#!/bin/sh
# Strip everything personal or machine-specific from an extracted root filesystem before it goes
# into a release image (checklist: 开源发布规划与版权审查 3.1). Run as root in the image-tools
# container, on a copy, never on a running device:
#   sanitize-rootfs.sh ROOT HUB_TEMPLATE REPO
# HUB_TEMPLATE is xiaozhi-hub-server's scripts/config.template.yaml of the shipped commit; the hub's
# data/ starts over from it, the way its install script does it.
# REPO is this repository: update/thinksmart-update.conf and kiosk/thinksmart-kiosk.conf are keep
# files on the device, so only this puts our copies (our update source) into the image.
# What stays on purpose: user ubuntu with password thinksmart (ubuntu-password.hash), passwordless
# sudo, SSH with password login; root is locked. The README tells people to change the password.
set -eu
R=${1:?root}; TEMPLATE=${2:?hub config template}; REPO=${3:?repository}
# canonical, so it compares with readlink -f output in the link check
R=$(cd "$R" && pwd -P)
if [ ! -d "$R/etc" ] || [ ! -d "$R/home/ubuntu" ]; then echo "$R does not look like the root filesystem"; exit 1; fi
# Deletions and writes below go through whatever links the capture holds. In the container an
# absolute link resolves there, where /w (the work volume) and /out (OUT_DIR) are the build's own:
# no link may lead into them from outside the copy. (SANITIZE_GUARD: those places, for the tests.)
L=$(mktemp); trap 'rm -f "$L" "$L.links"' EXIT
find "$R" -xdev -type l | while IFS= read -r l; do
    t=$(readlink -f "$l") || continue
    case $t in "$R"|"$R"/*) continue ;; esac
    for g in ${SANITIZE_GUARD:-/w /out}; do
        case $t in "$g"|"$g"/*) echo "  ${l#"$R"} -> $t" ;; esac
    done
done > "$L"
if [ -s "$L" ]; then echo "sanitize: links out of the copy into the build's own directories:"; cat "$L"; exit 1; fi
S=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC2034 # read by allowlist.sh's home_allowed
HOME_ALLOW=$S/home-allowlist.txt
# shellcheck source=image/allowlist.sh
. "$S/allowlist.sh"
# links that would take the changes below into the build container instead of the image
out_dir_links "$R" "$L.links" > "$L" || { cat "$L"; rm -f "$L.links"; exit 1; }
rm -f "$L.links"
for f in $WRITTEN_FILES; do
    if [ -L "$R/$f" ]; then echo "/$f -> $(readlink "$R/$f")"; fi
done >> "$L"
if [ -s "$L" ]; then
    echo "sanitize: links where it deletes or writes (replace them on the device with what they point at):"; cat "$L"; exit 1
fi
H=$R/home/ubuntu
HUB=$H/xiaozhi-hub-server
SRV=$HUB/main/xiaozhi-server

say() { echo "sanitize: $*"; }

# Leftovers the device setup didn't remove: the restored partition originals, temp files
say "originals and temp files"
# the first chat page and py-xiaozhi left these in the kiosk's folder (vendor logos, an Edge TTS sample)
rm -rf "$R"/usr/local/share/thinksmart-kiosk/chat.html "$R"/usr/local/share/thinksmart-kiosk/logos \
    "$R"/usr/local/share/thinksmart-kiosk/wake.wav
[ -L "$R/etc/systemd/system/ModemManager.service" ] && rm -f "$R/etc/systemd/system/ModemManager"
find "$R/lib/modules" -name '*.orig' -delete
rm -rf "$R"/tmp/* "$R"/tmp/.[!.]* "$R"/var/tmp/* 2>/dev/null || true

# tar on a Mac adds AppleDouble files (._name, magic 00 05 16 07) unless COPYFILE_DISABLE=1, and
# Finder leaves .DS_Store; deploys from the Mac brought them in. A ._ file without the magic stays.
say "macOS leftovers: ._* AppleDouble files, .DS_Store, __MACOSX"
find "$R" -xdev \( -name .DS_Store -type f -o -name __MACOSX -type d -prune \) -exec rm -rf {} +
find "$R" -xdev -name '._*' -type f | while IFS= read -r f; do
    [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 00051607 ] && rm -f "$f"
done || true

say "update source and kiosk settings: this repository's copies"
install -m 644 -o 0 -g 0 "$REPO/update/thinksmart-update.conf" "$R/etc/thinksmart-update.conf"
install -m 644 -o 0 -g 0 "$REPO/kiosk/thinksmart-kiosk.conf" "$R/etc/thinksmart-kiosk.conf"

say "accounts: ubuntu with the published password, root locked, nobody else"
people=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/passwd")
groups=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/group")
for u in $people; do
    home=$(awk -F: -v u="$u" '$1 == u {print $6}' "$R/etc/passwd")
    case $home in
        /nonexistent) ;;
        # one name right under /home, nothing else: /home//ubuntu or /home/bob/x would hit the wrong tree
        /home/ubuntu|/home/.|/home/..|/home/*/*) echo "sanitize: $u's home is $home: sort it out on the device"; exit 1 ;;
        /home/?*) rm -rf "$R$home" ;;
        *) echo "sanitize: $u's home $home is outside /home: remove it on the device first"; exit 1 ;;
    esac
    rm -f "$R/var/spool/cron/crontabs/$u" "$R/var/mail/$u" "$R/var/lib/AccountsService/users/$u" \
        "$R/var/lib/AccountsService/icons/$u" "$R/var/lib/sudo/lectured/$u"
    # a sudoers file for the removed account goes; one that also holds ubuntu's rule (the screen
    # services run sudo unattended) is not edited here: sudoers syntax is no place for sed
    for f in "$R"/etc/sudoers.d/*; do
        if [ -f "$f" ] && grep -qwF -e "$u" "$f"; then
            if grep -qwF ubuntu "$f"; then
                echo "sanitize: ${f#"$R"} names both $u and ubuntu: take $u out of it on the device"; exit 1
            fi
            rm -f "$f"
        fi
    done
    say "  removed account $u"
done
# edit FILE KIND: drop the removed accounts (passwd, shadow, subuid, subgid) or groups (group,
# gshadow), and removed accounts from member lists; keeps owner and mode (the new text is written
# into the same file). Users and groups stay apart: a system user can share a removed group's name.
edit() {
    f=$R/etc/$1
    [ -e "$f" ] || return 0
    case $2 in group|gshadow) rows=$groups ;; *) rows=$people ;; esac
    # (the scratch file too: one the capture holds as a link would take the write elsewhere)
    rm -f "$f.sanitize"
    ROWS=$rows PEOPLE=$people HASH=$(cat "$S/ubuntu-password.hash") DAYS=$(($(date +%s) / 86400)) \
        awk -F: -v OFS=: -v kind="$2" '
        BEGIN {
            n = split(ENVIRON["ROWS"], d, "\n"); for (i = 1; i <= n; i++) if (d[i] != "") gone[d[i]] = 1
            n = split(ENVIRON["PEOPLE"], d, "\n"); for (i = 1; i <= n; i++) if (d[i] != "") person[d[i]] = 1
        }
        function strip(list,   n, a, i, out) {
            n = split(list, a, ","); out = ""
            for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in person)) out = out (out == "" ? "" : ",") a[i]
            return out
        }
        $1 in gone { next }
        # ageing and expiry from the mother device go with its password: expired, ubuntu could not log in
        kind == "shadow" && $1 == "ubuntu" { $2 = ENVIRON["HASH"]; $3 = ENVIRON["DAYS"]; $4 = 0; $5 = 99999; $6 = 7; $7 = ""; $8 = ""; $9 = "" }
        kind == "shadow" && $1 == "root" { $2 = "!" }
        kind == "passwd" && $1 == "ubuntu" { $5 = "Ubuntu" }
        kind == "group" { $4 = strip($4) }
        kind == "gshadow" { $3 = strip($3); $4 = strip($4) }
        { print }' "$f" > "$f.sanitize"
    cat "$f.sanitize" > "$f"
    rm -f "$f.sanitize"
}
edit passwd passwd; edit shadow shadow; edit group group; edit gshadow gshadow; edit subuid plain; edit subgid plain
# ubuntu's name (above), photo and e-mail are the mother device owner's: the image's ubuntu keeps
# only its session and language settings (not a link: checked at the top; a directory there fails
# check-rootfs)
A=$R/var/lib/AccountsService
rm -f "$A/icons/ubuntu"
if [ -f "$A/users/ubuntu" ]; then
    rm -f "$A/users/ubuntu.sanitize"
    awk "$ACCOUNTS_KEEP" "$A/users/ubuntu" > "$A/users/ubuntu.sanitize"
    cat "$A/users/ubuntu.sanitize" > "$A/users/ubuntu"
    rm -f "$A/users/ubuntu.sanitize"
fi
rm -f "$R"/etc/shadow- "$R"/etc/passwd- "$R"/etc/group- "$R"/etc/gshadow- "$R"/etc/subuid- "$R"/etc/subgid-
# what no account owns any more: a home left by userdel without -r, or by an account removed earlier
for d in "$R"/home/* "$R"/home/.[!.]* "$R"/home/..?*; do
    if { [ -e "$d" ] || [ -L "$d" ]; } && [ "${d##*/}" != ubuntu ]; then rm -rf "$d"; say "  removed /home/${d##*/}"; fi
done
# the locate database lists every file name the mother device had (its timer rebuilds it)
rm -f "$R/var/lib/plocate/plocate.db" "$R/var/lib/mlocate/mlocate.db"

say "host name and time zone: the public defaults"
# /etc/hosts whole: the owner's LAN names in it are no one else's (none of these is a link: checked at
# the top)
rm -f "$R/etc/machine-info"
printf 'thinksmart\n' > "$R/etc/hostname"
stock_hosts > "$R/etc/hosts"
printf 'Etc/UTC\n' > "$R/etc/timezone"
ln -sfn /usr/share/zoneinfo/Etc/UTC "$R/etc/localtime"

say "mail and crontabs: none (each removal printed: a crontab the device needs shows up here)"
for d in var/spool/cron/crontabs var/mail; do
    for f in "$R/$d"/* "$R/$d"/.[!.]* "$R/$d"/..?*; do
        if [ -e "$f" ] || [ -L "$f" ]; then rm -rf "$f"; say "  removed /$d/${f##*/}"; fi
    done
done

say "networks: Wi-Fi profiles, leases, Bluetooth pairings"
rm -f "$R"/etc/netplan/90-NM-*.yaml
rm -rf "$R"/etc/NetworkManager/system-connections/*
rm -f "$R"/var/lib/NetworkManager/*.lease "$R"/var/lib/NetworkManager/secret_key \
    "$R"/var/lib/NetworkManager/timestamps "$R"/var/lib/NetworkManager/seen-bssids
rm -rf "$R"/var/lib/dhcpcd/* "$R"/var/lib/bluetooth/*

say "SSH: authorized keys and host keys (regenerated on first boot)"
rm -rf "$H/.ssh" "$R/root/.ssh"
install -d -m 700 -o 1000 -g 1000 "$H/.ssh"
rm -f "$R"/etc/ssh/ssh_host_*

say "machine identity: machine-id, random seed"
: > "$R/etc/machine-id"
rm -f "$R/var/lib/dbus/machine-id"
ln -s /etc/machine-id "$R/var/lib/dbus/machine-id"
rm -f "$R/var/lib/systemd/random-seed" "$R/var/lib/systemd/credential.secret"

say "logs, crash dumps, apt caches"
find "$R/var/log" -type f -delete
rm -rf "$R"/var/log/journal/* "$R"/var/crash/* "$R"/var/lib/systemd/coredump/*
rm -rf "$R"/var/cache/apt/*.bin "$R"/var/cache/apt/archives/*.deb "$R"/var/cache/apt/archives/partial/*
rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/debconf/*-old "$R"/var/backups/*

say "home: only what the voice terminal uses"
for f in "$H"/* "$H"/.[!.]* "$H"/..?*; do
    case "${f##*/}" in
        .bashrc|.profile|.bash_logout|.config|.local|.ssh|xiaozhi-hub-server|xiaozhi-workspace) ;;
        Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos) ;;
        *) rm -rf "$f" ;;
    esac
done
for f in "$H"/.config/* "$H"/.config/.[!.]* "$H"/.config/..?*; do
    case "${f##*/}" in
        pipewire|wireplumber|systemd|user-dirs.dirs|user-dirs.locale) ;;
        *) rm -rf "$f" ;;
    esac
done
# where setup writes, only home-allowlist.txt stays: anything else may hold a token. Each removal
# is printed: a file the device needs shows up here first (then it belongs on the list).
for d in .config/systemd .config/pipewire .config/wireplumber .local; do
    [ -d "$H/$d" ] || continue
    (cd "$H" && find "$d" -mindepth 1 \( -type f -o -type l -o -type p -o -type s \)) | while IFS= read -r p; do
        home_allowed "$p" || { rm -f "$H/$p"; say "  removed /home/ubuntu/$p"; }
    done
    find "$H/$d" -mindepth 1 -depth -type d -empty -delete
done
rm -rf "$H/.config/thinksmart-kiosk"   # the kiosk's language choice: a new device asks again
# the gateway's unit as scripts/autostart.sh writes it, with the image's paths: whatever the mother
# device had in it (an Environment= with a key) does not ship
if [ -e "$H/.config/systemd/user/xiaozhi-hub.service" ]; then
    install -m 644 -o 1000 -g 1000 "$S/xiaozhi-hub.service" "$H/.config/systemd/user/xiaozhi-hub.service"
fi
for d in Desktop Documents Downloads Music Pictures Public Templates Videos; do
    [ -d "$H/$d" ] && find "$H/$d" -mindepth 1 -delete
done
find "$H/xiaozhi-workspace" -mindepth 1 -delete
say "shell startup files and /root from /etc/skel (startup files are where tokens get exported)"
find "$R/root" -mindepth 1 -maxdepth 1 ! -name .bashrc ! -name .profile -exec rm -rf {} +
for f in .bashrc .profile; do install -m 644 -o 0 -g 0 "$R/etc/skel/$f" "$R/root/$f"; done
for f in .bashrc .profile .bash_logout; do install -m 644 -o 1000 -g 1000 "$R/etc/skel/$f" "$H/$f"; done

say "hub: fresh data/ from the template, no logs (its git: clean-hub-git.sh)"
# a system-wide insteadOf or proxy would redirect the gateway's fetches; the image needs none
rm -f "$R/etc/gitconfig"
rm -rf "$SRV/data" "$SRV/tmp"
install -d -o 1000 -g 1000 "$SRV/data" "$SRV/tmp"
hub_config "$TEMPLATE" > "$SRV/data/.config.yaml"
: > "$SRV/data/.install-complete"
chown 1000:1000 "$SRV/data/.config.yaml" "$SRV/data/.install-complete"
chmod 600 "$SRV/data/.config.yaml"
rm -rf "$SRV/config/assets/wakeup_words"
find "$HUB" -name __pycache__ -type d -prune -exec rm -rf {} +

say "backup copies: *.bak*, *.orig, *.old, *.save, *~, dpkg/ucf leftovers"
# hand-made copies can hold keys (a .config.yaml.bak with the API key sat in the hub's data/);
# nothing the system needs is named like this in these places (Python packages are left alone)
find "$R/etc" "$R/home" "$R/root" "$R/opt" "$R/usr/local" -xdev \
    \( -name '*.bak*' -o -name '*.orig' -o -name '*.old' -o -name '*.save' -o -name '*~' \
       -o -name '*.dpkg-old' -o -name '*.dpkg-dist' -o -name '*.ucf-old' \) \
    -not -path '*/site-packages/*' -not -path '*/.venv/*' -exec rm -rf {} + 2>/dev/null || true

say "updater: no download leftovers, past checks, system backup or previous client"
rm -rf "$R"/var/lib/thinksmart-update/download/* "$R"/var/lib/thinksmart-update/requests/*
# a new device has nothing to roll back to, and both still point at upstream (pending.json and
# system-pending.json are left alone: check-rootfs.sh refuses a capture with an update half done)
rm -rf "$R/opt/thinksmart/system/backup"
CL=$R/opt/thinksmart/client
cur=$(readlink "$CL/current" 2>/dev/null || true)
if [ -n "$cur" ]; then
    for d in "$CL"/* "$CL"/.[!.]* "$CL"/..?*; do
        if [ -e "$d" ] || [ -L "$d" ]; then
            case ${d##*/} in current|"$cur") ;; *) rm -rf "$d" ;; esac
        fi
    done
    env=$(readlink "$CL/$cur/.venv" 2>/dev/null || true)
    # the env it uses: one real directory in envs/, or every env below would count as unused and go
    case $env in ../../envs/*) name=${env#../../envs/} ;; *) name= ;; esac
    case $name in */*|.|..) name= ;; esac
    { [ -n "$name" ] && [ -d "$R/opt/thinksmart/envs/$name" ] && [ ! -L "$R/opt/thinksmart/envs/$name" ]; } \
        || { echo "sanitize: client $cur's .venv is not a link to a directory in envs/ ('$env')"; exit 1; }
    for e in "$R"/opt/thinksmart/envs/* "$R"/opt/thinksmart/envs/.[!.]* "$R"/opt/thinksmart/envs/..?*; do
        if { [ -e "$e" ] || [ -L "$e" ]; } && [ "${e##*/}" != "$name" ]; then rm -rf "$e"; fi
    done
    printf '{"current": "%s"}\n' "$cur" > "$R/var/lib/thinksmart-update/status.json"
fi

say "done"
