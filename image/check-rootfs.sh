#!/bin/sh
# File-tree checks on a sanitized root filesystem, run before mke2fs (spec §5.3, §5.4, §5.5):
#   check-rootfs.sh ROOT IDENTIFIERS_FILE REPO
# REPO is this repository (its system layer is compared file by file). Prints every failure;
# exits 1 if any, 2 on a usage or tool error.
set -eu
# git run from a hook or another tool would otherwise act on that repository: no GIT_* variable
# (GIT_DIR, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_PARAMETERS...) reaches git here
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
# nor the caller's global or system settings (status.showUntrackedFiles, hooksPath...)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# grep -I and the patterns behave the same in the container (POSIX locale) and in the tests
export LC_ALL=C
R=${1:?root}; IDS=${2:?identifiers file}; REPO=${3:?repository}
S=$(cd "$(dirname "$0")" && pwd)
HOME_ALLOW=$S/home-allowlist.txt
PROV=$S/upstream-provenance.txt
# shellcheck source=image/allowlist.sh
. "$S/allowlist.sh"
[ -d "$R/etc" ] || { echo "check-rootfs: $R is not a root filesystem"; exit 2; }
# canonical, so it compares with readlink -f output below
R=$(cd "$R" && pwd -P)
H=$R/home/ubuntu
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
bad() { echo "check-rootfs: $*"; fail=1; }
# neither a file nor a link (test -e follows a link on the build host, not in the image)
absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
# a path inside the image with its links followed there (an absolute target is the image's /)
inroot() {
    _p=$1; _i=0
    while [ -L "$_p" ] && [ "$_i" -lt 20 ]; do
        _l=$(readlink "$_p"); case $_l in /*) _p=$R$_l ;; *) _p=${_p%/*}/$_l ;; esac; _i=$((_i + 1))
    done
    printf '%s\n' "$_p"
}
# grep that tells "no match" (1) from an error (2+)
search() { rc=0; grep "$@" || rc=$?; [ "$rc" -le 1 ] || { echo "check-rootfs: grep failed: $*"; exit 2; }; }
# the names in a directory, sorted, on one line; "(unreadable)" when find fails, never nothing
names() {
    _n=$(find "$1" -mindepth 1 -maxdepth 1 -exec basename {} \;) || { echo '(unreadable) '; return 0; }
    [ -z "$_n" ] || printf '%s\n' "$_n" | sort | tr '\n' ' '
}

# --- update source and gateway remote (§5.3 points 1, 3, 5)
grep -qxF 'SOURCES="https://github.com/ohimsmart/oh-im-smart-client/releases/"' "$R/etc/thinksmart-update.conf" \
    || bad "thinksmart-update.conf does not carry the ohimsmart SOURCES line"
# the gateway checkout as clean-hub-git.sh leaves it: our config only, main and origin/main only,
# nothing unreachable (a deleted tag's commits), nothing else in .git, no hooks, no ignored file
# outside image/hub-ignored.txt, data/ as sanitize wrote it
HUB=$H/xiaozhi-hub-server
G() { git -c safe.directory='*' -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$HUB" "$@"; }
hubfail=0
hubbad() { bad "$@"; hubfail=1; }
{ [ -d "$HUB/.git" ] && [ ! -L "$HUB/.git" ]; } || hubbad "the gateway's .git is not a directory"
cmp -s "$S/hub-git-config" "$HUB/.git/config" || hubbad "the gateway's .git/config is not image/hub-git-config"
absent "$R/etc/gitconfig" || bad "/etc/gitconfig is there (it can redirect the gateway's fetches)"
absent "$HUB/.git/hooks" || hubbad "the gateway has .git/hooks (clean-hub-git.sh removes it, samples too)"
for f in "$HUB"/.git/* "$HUB"/.git/.[!.]* "$HUB"/.git/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in HEAD|config|index|objects|refs|packed-refs|shallow) ;; *) hubbad "the gateway's .git holds ${f##*/}" ;; esac
    fi
done
# and inside objects/ and refs/ only what git itself writes there, no links (no info/alternates)
# (names carry a SHA-1 or SHA-256 in hex: a file only named like git's would need that too)
hexid() { case $1 in ''|*[!0-9a-f]*) return 1 ;; esac; [ ${#1} = 40 ] || [ ${#1} = 64 ]; }
(cd "$HUB/.git" && find objects refs ! -type d 2>/dev/null) | while IFS= read -r p; do
    if [ -L "$HUB/.git/$p" ]; then echo "$p"; continue; fi
    case $p in
        objects/info/packs|objects/info/commit-graph|objects/info/commit-graphs/commit-graph-chain) ;;
        refs/heads/main|refs/remotes/origin/main) ;;
        objects/pack/pack-*.pack|objects/pack/pack-*.idx|objects/pack/pack-*.rev|objects/pack/pack-*.bitmap|objects/pack/pack-*.mtimes)
            n=${p#objects/pack/pack-}; hexid "${n%.*}" || echo "$p" ;;
        objects/info/commit-graphs/graph-*.graph)
            n=${p#objects/info/commit-graphs/graph-}; hexid "${n%.graph}" || echo "$p" ;;
        objects/??/*)
            d=${p#objects/}; hexid "${d%%/*}${d#*/}" || echo "$p" ;;
        *) echo "$p" ;;
    esac
done > "$T/x"
[ ! -s "$T/x" ] || hubbad "the gateway's .git holds files git does not write: $(head -5 "$T/x" | tr '\n' ' ')"
# git only on a .git that passed every check above: git reads its config, attributes and object
# stores there, and a clean filter in a rejected config would run in git status
if [ "$hubfail" = 0 ]; then
    refs=$(G for-each-ref --format='%(refname)' | tr '\n' ' ') || bad "git for-each-ref failed in the gateway"
    [ "$refs" = "refs/heads/main refs/remotes/origin/main " ] || bad "gateway refs besides main and origin/main: $refs"
    [ "$(G symbolic-ref -q HEAD || true)" = refs/heads/main ] || bad "the gateway is not on its main branch"
    [ "$(G rev-parse -q --verify main || true)" = "$(G rev-parse -q --verify origin/main || echo none)" ] \
        || bad "the gateway's main is not origin/main (a commit that was never published)"
    if out=$(G fsck --unreachable --no-reflogs --no-progress 2>&1); then
        case $out in *unreachable*) bad "the gateway holds unreachable objects (run clean-hub-git.sh)" ;; esac
    else
        bad "git fsck failed in the gateway"
    fi
    G ls-files --others --ignored --exclude-standard --directory > "$T/ignored" || bad "git ls-files failed in the gateway"
    grep -v -e '^#' -e '^$' "$S/hub-ignored.txt" | sort > "$T/ignored.ok"
    sort "$T/ignored" | comm -23 - "$T/ignored.ok" > "$T/x"
    [ ! -s "$T/x" ] || bad "ignored files in the gateway not on hub-ignored.txt: $(tr '\n' ' ' < "$T/x")"
    # tracked files as committed: no index flag hides an edit (ls-files -v prints H for a plain entry),
    # and status shows no edit and no untracked file
    G ls-files -v > "$T/flags" || bad "git ls-files failed in the gateway"
    grep -v '^H ' "$T/flags" > "$T/x" || true
    [ ! -s "$T/x" ] || bad "gateway index entries with assume-unchanged or skip-worktree: $(cut -c3- "$T/x" | head -5 | tr '\n' ' ')"
    st=$(G status --porcelain --untracked-files=all) || bad "git status failed in the gateway"
    [ -z "$st" ] || bad "the gateway's working tree differs from its commit: $(printf '%s' "$st" | head -5 | tr '\n' ' ')"
else
    bad "no git command was run on the gateway: fix the .git failures above first"
fi
# (names prints nothing for a file or a link: each must be a real directory first)
SRV=$HUB/main/xiaozhi-server
{ [ -d "$SRV/data" ] && [ ! -L "$SRV/data" ] && [ "$(names "$SRV/data")" = ".config.yaml .install-complete " ] \
    && [ -f "$SRV/data/.config.yaml" ] && [ ! -L "$SRV/data/.config.yaml" ] \
    && [ -f "$SRV/data/.install-complete" ] && [ ! -L "$SRV/data/.install-complete" ] \
    && [ ! -s "$SRV/data/.install-complete" ]; } \
    || bad "the gateway's data/ is not fresh"
# the config exactly as sanitize writes it from the checkout's own (tracked, unmodified) template:
# the mother device's config, with its keys, cannot pass
hub_config "$HUB/scripts/config.template.yaml" > "$T/config.yaml" \
    || { echo "check-rootfs: no scripts/config.template.yaml in the gateway"; exit 2; }
cmp -s "$T/config.yaml" "$SRV/data/.config.yaml" || bad "the gateway's data/.config.yaml is not its template's"
{ [ -d "$SRV/tmp" ] && [ ! -L "$SRV/tmp" ] && [ -z "$(names "$SRV/tmp")" ]; } || bad "the gateway's tmp/ is not an empty directory"
py=$(inroot "$SRV/.venv/bin/python")
{ [ -d "$SRV/.venv" ] && [ ! -L "$SRV/.venv" ] && [ -f "$py" ] && [ ! -L "$py" ]; } \
    || bad "the gateway's .venv has no Python (scripts/start.sh runs .venv/bin/python)"

# --- the system layer is this repository's, file for file (an older one still names upstream)
# (read into a file first: in a pipe a missing list would just mean nothing to compare)
search -v -e '^#' -e '^[[:space:]]*$' -e '^require ' "$REPO/image/system-files.txt" > "$T/files"
[ -s "$T/files" ] || { echo "check-rootfs: $REPO/image/system-files.txt lists nothing"; exit 2; }
while read -r src dst mode owner _; do
    [ "$src" = - ] && continue
    cmp -s "$REPO/$src" "$R$dst" || echo "$dst is not this repository's $src"
    # a root-run script writable by ubuntu, or a service that lost its execute bit, is no copy
    case $owner in root) uid=0 ;; ubuntu) uid=1000 ;; *) uid=unknown ;; esac
    [ "$(stat -c '%a %u' "$R$dst" 2>/dev/null)" = "$mode $uid" ] || echo "$dst is not mode $mode, owner $owner"
done < "$T/files" > "$T/layer"
[ ! -s "$T/layer" ] || { bad "system layer differs (install this branch's layer on the device first):"; cat "$T/layer"; }
cmp -s "$S/xiaozhi-hub.service" "$H/.config/systemd/user/xiaozhi-hub.service" \
    || bad "the gateway unit is not image/xiaozhi-hub.service"

# --- upstream URLs and owner identifiers in the file tree (§5.3 point 5)
# uncovered OUT GREP_ARGS...: the files that match, then each file's lines, against the provenance list
uncovered() {
    out=$1; shift
    search -rlI "$@" "$R" > "$T/hits.files"
    : > "$out"
    while IFS= read -r f; do
        search -nI "$@" "$f" > "$T/hits"
        provenance_uncovered "$R" "$PROV" "$f" < "$T/hits" >> "$out"
    done < "$T/hits.files"
}
grep -v -e '^#' -e '^[[:space:]]*$' "$IDS" > "$T/ids" || { echo "check-rootfs: $IDS lists nothing"; exit 2; }
uncovered "$T/up.bad" -E '(github(usercontent)?\.com[/:]|githubusercontent\.com/)justhalfbit'
uncovered "$T/own.bad" -wF -f "$T/ids"
[ ! -s "$T/up.bad" ] || { bad "upstream URLs:"; head -20 "$T/up.bad"; }
[ ! -s "$T/own.bad" ] || { bad "owner identifiers:"; head -20 "$T/own.bad"; }
# and in file names, which a scan of contents does not see (no attribution is ever a file name)
(cd "$R" && find . -xdev) > "$T/paths"
search -wF -f "$T/ids" "$T/paths" > "$T/x"
[ ! -s "$T/x" ] || bad "file names with an owner identifier: $(head -5 "$T/x" | tr '\n' ' ')"

# --- accounts (§5.4)
hash=$(cat "$S/ubuntu-password.hash")
awk -F: -v h="$hash" '$1 == "ubuntu" && $2 == h && $3 ~ /^[1-9][0-9]*$/ && $4 "|" $5 "|" $6 "|" $7 "|" $8 "|" $9 == "0|99999|7|||" && NF == 9 {f = 1}
    END {exit !f}' "$R/etc/shadow" \
    || bad "ubuntu's password is not ubuntu-password.hash, set and never ageing, inactive or expired"
awk -F: '$1 == "root" && $2 == "!" {f = 1} END {exit !f}' "$R/etc/shadow" || bad "root is not locked"
others=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "ubuntu" {print $1}' "$R/etc/passwd" "$R/etc/group" | sort -u | tr '\n' ' ')
[ -z "$others" ] || bad "people or their groups besides ubuntu: $others"
cut -d: -f1 "$R/etc/passwd" | sort > "$T/users"
cut -d: -f1 "$R/etc/group" | sort > "$T/groups"
for f in shadow subuid subgid; do
    if [ -e "$R/etc/$f" ]; then
        cut -d: -f1 "$R/etc/$f" | sort | comm -23 - "$T/users" | sed "s|^|$f names a removed account: |"
    fi
done > "$T/x"
[ ! -s "$T/x" ] || bad "$(cat "$T/x")"
if [ -e "$R/etc/gshadow" ]; then
    cut -d: -f1 "$R/etc/gshadow" | sort | comm -23 - "$T/groups" > "$T/x"
    [ ! -s "$T/x" ] || bad "gshadow names a removed group: $(tr '\n' ' ' < "$T/x")"
fi
{ cut -d: -f4 "$R/etc/group"; if [ -e "$R/etc/gshadow" ]; then cut -d: -f3,4 "$R/etc/gshadow" | tr : ,; fi; } \
    | tr , '\n' | sed '/^$/d' | sort -u | comm -23 - "$T/users" > "$T/x"
[ ! -s "$T/x" ] || bad "group members without an account: $(tr '\n' ' ' < "$T/x")"
awk -F: '$1 == "sudo" {n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] == "ubuntu") f = 1} END {exit !f}' "$R/etc/group" \
    || bad "ubuntu is not in the sudo group (root is locked: no way to administer the device)"
# and sudo without a password (the screen services run sudo unattended). Not a sudoers parser: the
# policy must be one this check knows. /etc/sudoers holds only Ubuntu's stock Defaults and rules
# (root, %admin, %sudo with a password) and ends in its @includedir; each file sudo reads from there
# (sudo skips names with a dot or ending in ~) holds only ubuntu's NOPASSWD rule, read after the
# stock ones, and one does. Anything else (another rule, an alias, a continued line) fails, for a
# person to look at. Each file is read on its own, so one's last line cannot run into the next's.
# sudo refuses a file or directory not root's or writable by others (a link is mode 777: refused too).
sudo_policy() {
    set -- "$R/etc/sudoers"
    for f in "$R"/etc/sudoers.d/*; do
        case ${f##*/} in *.*|*~) continue ;; esac
        if [ -f "$f" ]; then set -- "$@" "$f"; fi
    done
    for f in "$R/etc/sudoers.d" "$@"; do
        m=$(stat -c '%u:%a' "$f" 2>/dev/null) || m=missing
        case $m in
            0:*[2367]?|0:*[2367]) echo "${f#"$R"} is writable by others ($m): sudo refuses it" ;;
            0:*) ;;
            *) echo "${f#"$R"} is not root's ($m): sudo refuses it" ;;
        esac
    done
    awk -v main="$R/etc/sudoers" '
    # a comment, but #include... and #1000 or #-1 (uids) are not
    /^[ \t]*$/ || (/^[ \t]*#/ && !/^[ \t]*#(include|[-+0-9])/) {next}
    {l = $0; gsub(/[ \t]+/, " ", l); sub(/^ /, "", l); sub(/ $/, "", l); gsub(/ ?= ?/, "=", l); gsub(/: /, ":", l)}
    FILENAME == main {
        # the include as Ubuntu writes it: sudo reads an indented #includedir as a comment
        last = ($0 ~ /^[@#]includedir[ \t]+\/etc\/sudoers\.d[ \t]*$/)
        if (last || l ~ /^Defaults (env_reset|mail_badpass|use_pty|secure_path="\/usr\/local\/sbin:\/usr\/local\/bin:\/usr\/sbin:\/usr\/bin:\/sbin:\/bin(:\/snap\/bin)?")$/ || l ~ /^(root|%admin|%sudo) ALL=\(ALL(:ALL)?\) ALL$/) next
        print "/etc/sudoers: " $0; next
    }
    l ~ /^ubuntu ALL=(\(ALL(:ALL)?\) ?)?NOPASSWD:ALL$/ {ok = 1; next}
    {f = FILENAME; sub(/.*\/etc\//, "/etc/", f); print f ": " $0}
    END {
        if (!last) print "/etc/sudoers does not end in @includedir /etc/sudoers.d"
        if (!ok) print "no ubuntu ALL=(ALL) NOPASSWD:ALL in /etc/sudoers.d"
    }' "$@"
}
sudo_out=$(sudo_policy)
[ -z "$sudo_out" ] || bad "sudo policy this check does not know (the screen services need ubuntu's passwordless sudo): $(printf '%s' "$sudo_out" | head -5 | tr '\n' ';')"
[ "$(names "$R/home")" = "ubuntu " ] || bad "/home holds more than ubuntu: $(names "$R/home")"
# files of an owner or group the image has no entry for: a removed account's, outside its home
# (ids only, no names: a file name can hold a newline)
find "$R" -xdev -printf 'u%U\ng%G\n' | sort -u > "$T/owners"
awk -F: 'FILENAME == ARGV[1] {k["u" $3]; next} FILENAME == ARGV[2] {k["g" $3]; next} !($0 in k)' \
    "$R/etc/passwd" "$R/etc/group" "$T/owners" > "$T/x"
[ ! -s "$T/x" ] || bad "files of an owner (u) or group (g) id with no /etc/passwd or /etc/group entry: $(tr '\n' ' ' < "$T/x")(find them with find / -xdev -uid ID, -gid ID)"
for f in shadow- passwd- group- gshadow- subuid- subgid-; do
    absent "$R/etc/$f" || bad "/etc/$f is still there"
done
# mail and crontabs: none at all (sanitize empties both; the device runs on systemd units)
for d in var/spool/cron/crontabs var/mail; do
    if [ -d "$R/$d" ] && [ -n "$(names "$R/$d")" ]; then bad "/$d is not empty: $(names "$R/$d")"; fi
done
# files named for an account: a removed account's settings are no one's now
for d in var/lib/AccountsService/users var/lib/AccountsService/icons var/lib/sudo/lectured; do
    if [ -d "$R/$d" ]; then
        for f in "$R/$d"/* "$R/$d"/.[!.]* "$R/$d"/..?*; do
            if { [ -e "$f" ] || [ -L "$f" ]; } && ! grep -qxF -e "${f##*/}" "$T/users"; then bad "/$d/${f##*/} belongs to no account"; fi
        done
    fi
done

# --- /root and shell startup files (§5.4)
[ "$(names "$R/root")" = ".bashrc .profile " ] || bad "/root holds: $(names "$R/root")"
for f in root/.bashrc root/.profile home/ubuntu/.bashrc home/ubuntu/.profile home/ubuntu/.bash_logout; do
    cmp -s "$R/$f" "$R/etc/skel/${f##*/}" || bad "/$f is not /etc/skel/${f##*/}"
done

# --- home: no link to a directory (find and the checks below would look past what it holds, and
# git would run hooks through one), except inside a directory home-allowlist.txt keeps whole
# (uv's Python) or a gateway path git ignores (its .venv)
find "$H" -type l | while IFS= read -r l; do
    [ -d "$l" ] || continue
    rel=${l#"$H"/}
    home_allowed "$rel" && continue
    case $rel in
        xiaozhi-hub-server/*)
            while IFS= read -r ign; do case ${rel#xiaozhi-hub-server/} in "$ign"*) continue 2 ;; esac; done < "$T/ignored.ok" ;;
    esac
    echo "$rel"
done > "$T/x"
[ ! -s "$T/x" ] || bad "links to directories under /home/ubuntu: $(head -5 "$T/x" | tr '\n' ' ')"

# --- home: what sanitize keeps at the top, exactly the allowlist below (§5.4)
for f in "$H"/* "$H"/.[!.]* "$H"/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in
            .bashrc|.profile|.bash_logout|.config|.local|.ssh|xiaozhi-hub-server|xiaozhi-workspace) ;;
            Desktop|Documents|Downloads|Music|Pictures|Public|Templates|Videos) ;;
            *) bad "/home/ubuntu holds ${f##*/}" ;;
        esac
    fi
done
for f in "$H"/.config/* "$H"/.config/.[!.]* "$H"/.config/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in
            pipewire|wireplumber|systemd) ;;
            # xdg-user-dirs' two settings files: files, not a place to keep others
            user-dirs.dirs|user-dirs.locale) { [ -f "$f" ] && [ ! -L "$f" ]; } || bad "/home/ubuntu/.config/${f##*/} is not a regular file" ;;
            *) bad "/home/ubuntu/.config holds ${f##*/}" ;;
        esac
    fi
done
for d in .config/systemd .config/pipewire .config/wireplumber .local; do
    if [ -d "$H/$d" ]; then (cd "$H" && find "$d" -mindepth 1 \( -type f -o -type l \)); fi
done | sort > "$T/home"
while IFS= read -r p; do home_allowed "$p" || bad "not on home-allowlist.txt: /home/ubuntu/$p"; done < "$T/home"
grep -v -e '^#' -e '^$' "$HOME_ALLOW" | while IFS= read -r e; do
    case $e in
        */) [ -d "$H/$e" ] || echo "missing from the image: /home/ubuntu/$e" ;;
        */*.wants/*)
            # an enable link: to the unit of the same name in ~/.config/systemd/user (the one this
            # list holds), a regular file; resolved with every .. and link, as boot will
            if [ -L "$H/$e" ]; then
                t=$(readlink "$H/$e")
                case $t in /*) u=$R$t ;; *) u=$(dirname "$H/$e")/$t ;; esac
                { [ "$(readlink -f "$u" || true)" = "$R/home/ubuntu/.config/systemd/user/${e##*/}" ] \
                    && [ -f "$u" ] && [ ! -L "$u" ]; } \
                    || echo "link /home/ubuntu/$e points at $t, not at its unit"
            else
                echo "not a link: /home/ubuntu/$e"
            fi ;;
        *) { [ -f "$H/$e" ] && [ ! -L "$H/$e" ]; } || echo "missing or not a regular file: /home/ubuntu/$e" ;;
    esac
done > "$T/x"
[ ! -s "$T/x" ] || bad "$(cat "$T/x")"
absent "$H/.config/thinksmart-kiosk/lang" || bad "the kiosk language choice is still there"
# kept at the top of home, but empty (sanitize empties them; .ssh gets no keys)
for d in .ssh xiaozhi-workspace Desktop Documents Downloads Music Pictures Public Templates Videos; do
    if [ -e "$H/$d" ] || [ -L "$H/$d" ]; then
        { [ -d "$H/$d" ] && [ ! -L "$H/$d" ] && [ -z "$(names "$H/$d")" ]; } \
            || bad "/home/ubuntu/$d is not an empty directory"
    fi
done

# --- host name, time zone, NTP (§5.4, §5.5)
[ "$(cat "$R/etc/hostname")" = thinksmart ] || bad "hostname is '$(cat "$R/etc/hostname")'"
if [ "$(grep -c '^127\.0\.1\.1[[:space:]]' "$R/etc/hosts")" != 1 ] || ! grep -qx '127\.0\.1\.1[[:space:]]*thinksmart' "$R/etc/hosts"; then
    bad "/etc/hosts has no single 127.0.1.1 thinksmart line"
fi
[ "$(cat "$R/etc/timezone")" = Etc/UTC ] || bad "timezone is '$(cat "$R/etc/timezone")'"
[ "$(readlink "$R/etc/localtime")" = /usr/share/zoneinfo/Etc/UTC ] || bad "/etc/localtime is not Etc/UTC"
grep -qxF 'NTP=ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org pool.ntp.org ntp.ubuntu.com' \
    "$R/etc/systemd/timesyncd.conf.d/thinksmart.conf" || bad "timesyncd: not the NTP= line of kiosk/timesyncd.conf"

# --- updater: nothing half done, no backup, no previous client (§5.3 point 4a)
for f in pending.json system-pending.json; do
    absent "$R/var/lib/thinksmart-update/$f" || bad "an update is half done ($f): let the device finish it, then capture again"
done
absent "$R/opt/thinksmart/system/backup" || bad "/opt/thinksmart/system/backup is still there"
cur=$(readlink "$R/opt/thinksmart/client/current" || true)
[ -n "$cur" ] || bad "no current client"
# a version name, and a real directory there (a link could put the client and its .venv elsewhere)
case $cur in */*|.|..) bad "current client '$cur' is not a version in /opt/thinksmart/client" ;; esac
{ [ -d "$R/opt/thinksmart/client/$cur" ] && [ ! -L "$R/opt/thinksmart/client/$cur" ]; } \
    || bad "current client $cur is not a directory"
[ "$(names "$R/opt/thinksmart/client")" = "$(printf '%s\n' "$cur" current | sort | tr '\n' ' ')" ] \
    || bad "/opt/thinksmart/client holds more than $cur: $(names "$R/opt/thinksmart/client")"
env=$(readlink "$R/opt/thinksmart/client/$cur/.venv" || true)
# exactly ../../envs/<id>, <id> a real directory and the only one in envs/
case $env in
    ../../envs/*/*|../../envs/.|../../envs/..) bad "client $cur's .venv is not ../../envs/<id> ('$env')" ;;
    ../../envs/?*)
        e=$R/opt/thinksmart/envs/${env##*/}
        { [ -d "$e" ] && [ ! -L "$e" ]; } || bad "client $cur's env ${env##*/} is not a directory"
        [ "$(names "$R/opt/thinksmart/envs")" = "${env##*/} " ] \
            || bad "/opt/thinksmart/envs is not exactly ${env##*/}: $(names "$R/opt/thinksmart/envs")" ;;
    *) bad "client $cur has no .venv link into envs/ ('$env')" ;;
esac

[ "$fail" = 0 ] && echo "check-rootfs: ok"
exit "$fail"
