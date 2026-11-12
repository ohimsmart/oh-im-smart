#!/bin/sh
# sanitize-rootfs.sh and check-rootfs.sh on a synthetic capture:
#   fakeroot sh image/tests/test-sanitize.sh
set -eu
# a capture has stock modes and sudo refuses a group-writable sudoers file: not the caller's umask
umask 022
# git run from a hook or another tool would otherwise act on that repository: no GIT_* variable
# (GIT_DIR, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_PARAMETERS...) reaches git here
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
# nor the developer's global or system git settings (hooksPath, signing...)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
IMG=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$IMG/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
R=$T/root
n=0; failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; failed=1; }
t() { label=$1; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
nt() { label=$1; shift; if "$@" >/dev/null 2>&1; then no "$label"; else ok "$label"; fi; }
check() { sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$REPO"; }
# the tree belongs to uid 1000 and fakeroot runs as 0: git would refuse it as dubious
# shellcheck disable=SC2317 # called through eval in broken()
G() { git -c safe.directory='*' -c tag.gpgsign=false -c core.hooksPath=/dev/null -C "$R/home/ubuntu/xiaozhi-hub-server" "$@"; }

sh "$IMG/tests/make-fake-root.sh" "$R"
{ cat "$IMG/owner-identifiers.txt"; echo mother-host; } > "$T/ids"
C=$(G rev-parse HEAD); B=$(G rev-parse private-work)

nt "check-rootfs fails before sanitize" check
t "sanitize runs" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "clean-hub-git runs" sh "$IMG/clean-hub-git.sh" "$R/home/ubuntu/xiaozhi-hub-server" "$C"
if check; then ok "check-rootfs passes after sanitize"; else no "check-rootfs passes after sanitize"; fi

# the gateway checkout
HUB=$R/home/ubuntu/xiaozhi-hub-server
t "gateway on the published commit" test "$(G rev-parse main)" = "$C"
t "gateway config is the template's, LLM ClaudeAPI" grep -q '^  LLM: ClaudeAPI ' "$HUB/main/xiaozhi-server/data/.config.yaml"
t "gateway .git/config is image/hub-git-config" cmp -s "$HUB/.git/config" "$IMG/hub-git-config"
nt "gateway tag gone" G rev-parse -q --verify refs/tags/private-work
nt "unpublished commit gone" G cat-file -e "$B"
nt "gateway hooks gone, samples too" test -e "$HUB/.git/hooks"
nt "/etc/gitconfig gone" test -e "$R/etc/gitconfig"
nt "no gateway hook ran during the cleanup" sh -c "ls '$HUB/main/xiaozhi-server/data' | grep -q -- -ran"
nt "commit message of the private commit gone" test -e "$HUB/.git/COMMIT_EDITMSG"
nt "merge message gone" test -e "$HUB/.git/MERGE_MSG"
nt "git logs gone" test -e "$HUB/.git/logs"
t "the gateway checkout still works" G status --porcelain
t "the gateway's .venv kept" test -L "$HUB/main/xiaozhi-server/.venv/lib64"
t "a hidden local edit is undone" grep -qx 'echo install' "$HUB/scripts/bootstrap.sh"

# accounts
for f in passwd shadow group gshadow subuid subgid; do
    nt "alice gone from $f" grep -qw alice "$R/etc/$f"
done
nt "private group carol gone from group" grep -q '^carol:' "$R/etc/group"
nt "private group carol gone from gshadow" grep -q '^carol:' "$R/etc/gshadow"
t "sudo keeps ubuntu" grep -qx 'sudo:x:27:ubuntu' "$R/etc/group"
t "gshadow sudo keeps ubuntu" grep -qx 'sudo:\*::ubuntu' "$R/etc/gshadow"
t "system user www-data kept in passwd" grep -q '^www-data:' "$R/etc/passwd"
t "system user www-data kept in shadow" grep -q '^www-data:' "$R/etc/shadow"
nt "private group www-data gone" grep -q '^www-data:' "$R/etc/group"
nt "alice's home gone" test -e "$R/home/alice"
nt "a home no account owns gone" test -e "$R/home/retired"
nt "alice's AccountsService entry gone" test -e "$R/var/lib/AccountsService/users/alice"
t "ubuntu's name is Ubuntu" grep -qx 'ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash' "$R/etc/passwd"
nt "ubuntu's photo gone" test -e "$R/var/lib/AccountsService/icons/ubuntu"
nt "ubuntu's e-mail and photo path gone" grep -qE '^(Email|Icon)=' "$R/var/lib/AccountsService/users/ubuntu"
t "ubuntu's session kept" grep -qx 'Session=plasma' "$R/var/lib/AccountsService/users/ubuntu"
# shellcheck disable=SC2016 # the inner sh expands them
t "hosts is Ubuntu's stock file" sh -c '. "$1/allowlist.sh"; stock_hosts | cmp -s - "$2/etc/hosts"' sh "$IMG" "$R"
nt "machine-info gone" test -e "$R/etc/machine-info"
nt "locate database gone" test -e "$R/var/lib/plocate/plocate.db"
nt "alice's crontab gone" test -e "$R/var/spool/cron/crontabs/alice"
nt "alice's mail gone" test -e "$R/var/mail/alice"
nt "alice's sudoers file gone" test -e "$R/etc/sudoers.d/alice"
t "ubuntu's sudoers file kept" test -e "$R/etc/sudoers.d/90-ubuntu"
t "ubuntu hash is the published one" grep -qF "ubuntu:$(cat "$IMG/ubuntu-password.hash"):" "$R/etc/shadow"
t "ubuntu's password set, never ageing, inactive or expired" grep -qE '^ubuntu:[^:]*:[1-9][0-9]*:0:99999:7:::$' "$R/etc/shadow"
t "published hash is thinksmart" test "$(openssl passwd -6 -salt "$(cut -d'$' -f3 "$IMG/ubuntu-password.hash")" thinksmart)" = "$(cat "$IMG/ubuntu-password.hash")"
t "root locked" grep -q '^root:!:' "$R/etc/shadow"
nt "shadow- gone" test -e "$R/etc/shadow-"
t "shadow keeps mode 640" test "$(stat -c %a "$R/etc/shadow")" = 640

# home and /root
U=$R/home/ubuntu/.config/systemd/user
nt "leak.service gone" test -e "$U/leak.service"
nt "systemd user.conf gone" test -e "$R/home/ubuntu/.config/systemd/user.conf"
nt "leak.service link gone" test -L "$U/default.target.wants/leak.service"
t "gateway unit is image/xiaozhi-hub.service" cmp -s "$U/xiaozhi-hub.service" "$IMG/xiaozhi-hub.service"
t "gateway unit link kept" test -L "$U/default.target.wants/xiaozhi-hub.service"
t "proximity unit kept" test -f "$U/vcnl4200-proximity-daemon.service"
t "uv kept" test -f "$R/home/ubuntu/.local/bin/uv"
t "uv's Python kept" test -f "$R/home/ubuntu/.local/share/uv/python/bin/python3"
nt "other .local/bin file gone" test -e "$R/home/ubuntu/.local/bin/my-script"
nt ".local/state gone" test -e "$R/home/ubuntu/.local/state"
nt "unlisted PipeWire file gone" test -e "$R/home/ubuntu/.config/pipewire/pipewire.conf.d/20-experiment.conf"
nt "kiosk language gone" test -e "$R/home/ubuntu/.config/thinksmart-kiosk/lang"
t "ubuntu .bashrc from skel" cmp -s "$R/home/ubuntu/.bashrc" "$R/etc/skel/.bashrc"
t "ubuntu .bashrc owned by 1000" test "$(stat -c %u "$R/home/ubuntu/.bashrc")" = 1000
t "root .profile from skel" cmp -s "$R/root/.profile" "$R/etc/skel/.profile"
nt "/root/.aws gone" test -e "$R/root/.aws"

# host, time, updater, settings
t "hostname" test "$(cat "$R/etc/hostname")" = thinksmart
nt "old hostname gone from hosts" grep -q mother-host "$R/etc/hosts"
t "timezone" test "$(cat "$R/etc/timezone")" = Etc/UTC
t "update conf is the repository's" cmp -s "$R/etc/thinksmart-update.conf" "$REPO/update/thinksmart-update.conf"
t "kiosk conf is the repository's" cmp -s "$R/etc/thinksmart-kiosk.conf" "$REPO/kiosk/thinksmart-kiosk.conf"
nt "system backup gone" test -e "$R/opt/thinksmart/system/backup"
nt "previous client gone" test -e "$R/opt/thinksmart/client/0.1.6"
nt "previous link gone" test -L "$R/opt/thinksmart/client/previous"
nt "previous env gone" test -e "$R/opt/thinksmart/envs/old"
t "current env kept" test -d "$R/opt/thinksmart/envs/new"

# every check must also fail: break one thing, expect a failure, put it back. A break or restore
# command that fails is reported, not fatal.
broken() {  # label, command that breaks the sanitized root, command that restores it
    if ! (eval "$2") >/dev/null 2>&1; then no "break: $1"; return; fi
    if check >/dev/null 2>&1; then no "check-rootfs catches: $1"; else ok "check-rootfs catches: $1"; fi
    (eval "$3") >/dev/null 2>&1 || no "restore: $1"
}
broken "upstream URL in a script" \
    "echo 'curl https://raw.githubusercontent.com/justhalfbit/xiaozhi-hub-server/main/x | bash' > '$HUB/scripts/bootstrap.sh'" \
    "echo 'echo install' > '$HUB/scripts/bootstrap.sh'"
broken "upstream URL in a LICENSES/ directory" "mkdir '$HUB/LICENSES'; echo 'curl https://github.com/justhalfbit/x | sh' > '$HUB/LICENSES/install.sh'" \
    "rm -r '$HUB/LICENSES'"
broken "upstream URL under a directory named like a grep hit" "mkdir '$HUB/LICENSE:1:extra'; echo 'curl https://github.com/justhalfbit/x | sh' > '$HUB/LICENSE:1:extra/install.sh'" \
    "rm -r '$HUB/LICENSE:1:extra'"
broken "upstream URL as git@" "echo 'git@github.com:justhalfbit/x.git' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "owner identifier" "echo 'by chris-yyau' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "mother hostname" "echo 'host mother-host' > '$R/etc/motd'" "rm '$R/etc/motd'"
broken "upstream SOURCES" "cp '$R/etc/thinksmart-update.conf' '$T/u'; echo 'SOURCES=\"x\"' > '$R/etc/thinksmart-update.conf'" \
    "cp '$T/u' '$R/etc/thinksmart-update.conf'"
broken "upstream gateway origin" "G remote set-url origin https://example.com/x.git" \
    "G remote set-url origin https://github.com/ohimsmart/oh-im-smart-gateway.git"
broken "insteadOf in the gateway's config" "G config url.https://mirror.example/.insteadOf https://github.com/" \
    "cp '$IMG/hub-git-config' '$HUB/.git/config'"
broken "a tag in the gateway" "G tag t" "G tag -d t"
broken "an unreachable object in the gateway" "echo x | G hash-object -w --stdin" "G prune --expire=now"
broken "a gateway hook" "mkdir '$HUB/.git/hooks'; printf '#!/bin/sh\n' > '$HUB/.git/hooks/post-merge'" "rm -r '$HUB/.git/hooks'"
broken "notes as a hook sample" "mkdir -p '$HUB/.git/hooks/archive'; echo notes > '$HUB/.git/hooks/archive/notes.sample'" "rm -r '$HUB/.git/hooks'"
broken "ubuntu's mail" "echo letters > '$R/var/mail/ubuntu'" "rm '$R/var/mail/ubuntu'"
broken "ubuntu's crontab" "echo '* * * * * curl x' > '$R/var/spool/cron/crontabs/ubuntu'" "rm '$R/var/spool/cron/crontabs/ubuntu'"
broken "/etc/gitconfig" "echo '[http]' > '$R/etc/gitconfig'" "rm '$R/etc/gitconfig'"
broken "a commit message in the gateway's .git" "echo private > '$HUB/.git/COMMIT_EDITMSG'" "rm '$HUB/.git/COMMIT_EDITMSG'"
broken "an ignored file in the gateway" "echo KEY=1 > '$HUB/.env'" "rm '$HUB/.env'"
broken "an extra file in the gateway's data/" "echo x > '$HUB/main/xiaozhi-server/data/x'" "rm '$HUB/main/xiaozhi-server/data/x'"
broken "a home no account owns" "mkdir '$R/home/retired'" "rmdir '$R/home/retired'"
broken "ubuntu out of the sudo group" "cp '$R/etc/group' '$T/g'; sed -i 's/^sudo:x:27:ubuntu\$/sudo:x:27:/' '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "a file in Documents" "mkdir -p '$R/home/ubuntu/Documents'; echo notes > '$R/home/ubuntu/Documents/notes.txt'" \
    "rm -r '$R/home/ubuntu/Documents'"
broken "Documents as a file" "echo notes > '$R/home/ubuntu/Documents'" "rm '$R/home/ubuntu/Documents'"
broken "the gateway's hooks as a link" "mkdir -p '$R/home/ubuntu/.local/share/uv/hooks'; mv '$HUB/.git/hooks' '$T/hooks'; ln -s ../../../.local/share/uv/hooks '$HUB/.git/hooks'" \
    "rm '$HUB/.git/hooks'; mv '$T/hooks' '$HUB/.git/hooks'; rmdir '$R/home/ubuntu/.local/share/uv/hooks'"
broken ".local as a link" "mv '$R/home/ubuntu/.local' '$R/home/ubuntu/.local.real'; ln -s .local.real '$R/home/ubuntu/.local'" \
    "rm '$R/home/ubuntu/.local'; mv '$R/home/ubuntu/.local.real' '$R/home/ubuntu/.local'"
broken "the mother's config with a key" "cp '$HUB/main/xiaozhi-server/data/.config.yaml' '$T/cfg2'; echo '  api_key: abc' >> '$HUB/main/xiaozhi-server/data/.config.yaml'" \
    "cp '$T/cfg2' '$HUB/main/xiaozhi-server/data/.config.yaml'"
broken "content in .install-complete" "echo notes > '$HUB/main/xiaozhi-server/data/.install-complete'" \
    ": > '$HUB/main/xiaozhi-server/data/.install-complete'"
broken "user-dirs.dirs as a directory" "mkdir '$R/home/ubuntu/.config/user-dirs.dirs'; echo diary > '$R/home/ubuntu/.config/user-dirs.dirs/diary.txt'" \
    "rm -r '$R/home/ubuntu/.config/user-dirs.dirs'"
broken "a directory named data/.config.yaml" "mv '$HUB/main/xiaozhi-server/data/.config.yaml' '$T/cfg'; mkdir '$HUB/main/xiaozhi-server/data/.config.yaml'" \
    "rmdir '$HUB/main/xiaozhi-server/data/.config.yaml'; mv '$T/cfg' '$HUB/main/xiaozhi-server/data/.config.yaml'"
broken "the gateway's tmp/ as a file" "rmdir '$HUB/main/xiaozhi-server/tmp'; echo notes > '$HUB/main/xiaozhi-server/tmp'" \
    "rm '$HUB/main/xiaozhi-server/tmp'; mkdir '$HUB/main/xiaozhi-server/tmp'"
broken "an enable link to a copy of the unit elsewhere" "cp '$U/idle-blanker.service' '$R/tmp/idle-blanker.service'; ln -sfn /tmp/idle-blanker.service '$U/default.target.wants/idle-blanker.service'" \
    "ln -sfn ../idle-blanker.service '$U/default.target.wants/idle-blanker.service'; rm '$R/tmp/idle-blanker.service'"
broken "a file in the gateway's tmp/" "echo rec > '$HUB/main/xiaozhi-server/tmp/rec.wav'" "rm '$HUB/main/xiaozhi-server/tmp/rec.wav'"
broken "the client's .venv through a missing directory" "ln -sfn ../../envs/missing/new '$R/opt/thinksmart/client/1.0.0/.venv'" \
    "ln -sfn ../../envs/new '$R/opt/thinksmart/client/1.0.0/.venv'"
broken "a file in xiaozhi-workspace" "echo '{}' > '$R/home/ubuntu/xiaozhi-workspace/session.json'" \
    "rm '$R/home/ubuntu/xiaozhi-workspace/session.json'"
broken "a key in .ssh" "echo key > '$R/home/ubuntu/.ssh/id_ed25519'" "rm '$R/home/ubuntu/.ssh/id_ed25519'"
broken "an edited tracked file in the gateway" "echo 'echo edited' > '$HUB/scripts/bootstrap.sh'" \
    "echo 'echo install' > '$HUB/scripts/bootstrap.sh'"
broken "an edit hidden by skip-worktree" "echo 'echo edited' > '$HUB/scripts/bootstrap.sh'; G update-index --skip-worktree scripts/bootstrap.sh" \
    "G update-index --no-skip-worktree scripts/bootstrap.sh; echo 'echo install' > '$HUB/scripts/bootstrap.sh'"
broken "a file in .git/objects/info" "echo notes > '$HUB/.git/objects/info/private-notes.txt'" "rm '$HUB/.git/objects/info/private-notes.txt'"
broken "a non-object in a loose object directory" "mkdir -p '$HUB/.git/objects/ab'; echo notes > '$HUB/.git/objects/ab/notes'" "rm -r '$HUB/.git/objects/ab'"
broken "a file in .git/objects/info/commit-graphs" "mkdir -p '$HUB/.git/objects/info/commit-graphs'; echo notes > '$HUB/.git/objects/info/commit-graphs/private-notes.txt'" \
    "rm -r '$HUB/.git/objects/info/commit-graphs'"
broken "a file only named like a pack" "echo notes > '$HUB/.git/objects/pack/pack-notes.pack'" "rm '$HUB/.git/objects/pack/pack-notes.pack'"
broken "a file in .git/refs that is no ref" "echo notes > '$HUB/.git/refs/notes.txt'" "rm '$HUB/.git/refs/notes.txt'"
broken "mail of a removed account" "echo letters > '$R/var/mail/alice'" "rm '$R/var/mail/alice'"
broken "crontab of a removed account" "echo '* * * * * x' > '$R/var/spool/cron/crontabs/alice'" "rm '$R/var/spool/cron/crontabs/alice'"
broken "an ignored .env in the gateway's .venv sibling" "echo K=1 > '$HUB/main/xiaozhi-server/.env'" "rm '$HUB/main/xiaozhi-server/.env'"
broken "a root-run script writable by others" "chmod 777 '$R/usr/local/sbin/thinksmart-update'" "chmod 755 '$R/usr/local/sbin/thinksmart-update'"
broken "a script that lost its execute bit" "chmod 644 '$R/usr/local/sbin/thinksmart-update'" "chmod 755 '$R/usr/local/sbin/thinksmart-update'"
broken "the current client as a link elsewhere" "mv '$R/opt/thinksmart/client/1.0.0' '$R/opt/relocated'; ln -s ../../relocated '$R/opt/thinksmart/client/1.0.0'" \
    "rm '$R/opt/thinksmart/client/1.0.0'; mv '$R/opt/relocated' '$R/opt/thinksmart/client/1.0.0'"
broken "an untracked file in the gateway" "echo x > '$HUB/scripts/mine.sh'" "rm '$HUB/scripts/mine.sh'"
broken "a hidden ..name in home" "echo x > '$R/home/ubuntu/..notes'" "rm '$R/home/ubuntu/..notes'"
broken "an old system layer file" "cp '$R/usr/local/share/thinksmart-kiosk/welcome.html' '$T/w'; echo old > '$R/usr/local/share/thinksmart-kiosk/welcome.html'" \
    "cp '$T/w' '$R/usr/local/share/thinksmart-kiosk/welcome.html'"
broken "a key in the gateway unit" "echo 'Environment=K=1' >> '$U/xiaozhi-hub.service'" "cp '$IMG/xiaozhi-hub.service' '$U/xiaozhi-hub.service'"
broken "extra user unit" "echo x > '$U/x.service'" "rm '$U/x.service'"
broken "systemd user.conf" "echo 'DefaultEnvironment=K=1' > '$R/home/ubuntu/.config/systemd/user.conf'" \
    "rm '$R/home/ubuntu/.config/systemd/user.conf'"
broken "a file at the top of home" "echo x > '$R/home/ubuntu/.netrc'" "rm '$R/home/ubuntu/.netrc'"
broken "a directory in ~/.config" "mkdir '$R/home/ubuntu/.config/git'" "rmdir '$R/home/ubuntu/.config/git'"
broken "missing gateway unit" "mv '$U/xiaozhi-hub.service' '$T/hub.service'" "mv '$T/hub.service' '$U/xiaozhi-hub.service'"
broken "dangling gateway link" "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s /nonexistent/xiaozhi-hub.service '$U/default.target.wants/xiaozhi-hub.service'" \
    "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s /home/ubuntu/.config/systemd/user/xiaozhi-hub.service '$U/default.target.wants/xiaozhi-hub.service'"
broken "gateway link climbing out of the image" "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s '../../../../../../../../../../../../../../../..$IMG/xiaozhi-hub.service' '$U/default.target.wants/xiaozhi-hub.service'" \
    "rm '$U/default.target.wants/xiaozhi-hub.service'; ln -s /home/ubuntu/.config/systemd/user/xiaozhi-hub.service '$U/default.target.wants/xiaozhi-hub.service'"
broken "unit as a link" "mv '$U/vcnl4200-proximity-daemon.service' '$T/v'; ln -s /nonexistent '$U/vcnl4200-proximity-daemon.service'" \
    "rm '$U/vcnl4200-proximity-daemon.service'; mv '$T/v' '$U/vcnl4200-proximity-daemon.service'"
broken "another account" "cp '$R/etc/passwd' '$T/p'; echo 'bob:x:1002:1002::/home/bob:/bin/sh' >> '$R/etc/passwd'" "cp '$T/p' '$R/etc/passwd'"
broken "a private group" "cp '$R/etc/group' '$T/g'; echo 'carol:x:1003:' >> '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "gshadow group without group" "cp '$R/etc/gshadow' '$T/gs'; echo 'dave:!::' >> '$R/etc/gshadow'" "cp '$T/gs' '$R/etc/gshadow'"
broken "group member without account" "cp '$R/etc/group' '$T/g'; sed -i 's/^audio:x:29:.*/audio:x:29:ubuntu,ghost/' '$R/etc/group'" "cp '$T/g' '$R/etc/group'"
broken "hostname" "echo other > '$R/etc/hostname'" "echo thinksmart > '$R/etc/hostname'"
broken "NTP line" "cp '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf' '$T/n'; echo '[Time]' > '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf'" \
    "cp '$T/n' '$R/etc/systemd/timesyncd.conf.d/thinksmart.conf'"
broken "token in .bashrc" "echo 'export T=1' >> '$R/home/ubuntu/.bashrc'" "cp '$R/etc/skel/.bashrc' '$R/home/ubuntu/.bashrc'"
broken "file in /root" "echo x > '$R/root/.netrc'" "rm '$R/root/.netrc'"
broken "kiosk language" "mkdir -p '$R/home/ubuntu/.config/thinksmart-kiosk'; echo en > '$R/home/ubuntu/.config/thinksmart-kiosk/lang'" \
    "rm -r '$R/home/ubuntu/.config/thinksmart-kiosk'"
broken "update half done" "echo '{}' > '$R/var/lib/thinksmart-update/pending.json'" "rm '$R/var/lib/thinksmart-update/pending.json'"
broken "previous client" "mkdir '$R/opt/thinksmart/client/0.9.0'" "rmdir '$R/opt/thinksmart/client/0.9.0'"
broken "the client's env missing" "mv '$R/opt/thinksmart/envs/new' '$T/env'" "mv '$T/env' '$R/opt/thinksmart/envs/new'"
broken "/etc/gitconfig as a link into the image" "ln -s /home/ubuntu/.local/share/uv/gitconfig '$R/etc/gitconfig'" "rm '$R/etc/gitconfig'"
broken "a pending update as a link" "ln -s /nonexistent '$R/var/lib/thinksmart-update/pending.json'" "rm '$R/var/lib/thinksmart-update/pending.json'"
broken "the gateway without its .venv" "mv '$HUB/main/xiaozhi-server/.venv' '$T/hub-venv'" "mv '$T/hub-venv' '$HUB/main/xiaozhi-server/.venv'"
# (a chain of directory links in the middle of the path: the kernel gives up after 40)
broken "the gateway's Python behind 42 links" \
    "cd '$HUB/main/xiaozhi-server/.venv' && mv bin/python python.orig && echo py > bin/python.real && ln -s ../d1/python.real bin/python && i=1 && while [ \$i -le 40 ]; do ln -s d\$((i + 1)) d\$i; i=\$((i + 1)); done && ln -s bin d41" \
    "cd '$HUB/main/xiaozhi-server/.venv' && rm bin/python bin/python.real d[0-9]* && mv python.orig bin/python"
broken "the gateway's Python through file/.." \
    "cd '$HUB/main/xiaozhi-server/.venv/bin' && mv python ../python.orig && echo py > python.real && ln -s python.real/../python.real python" \
    "cd '$HUB/main/xiaozhi-server/.venv/bin' && rm python python.real && mv ../python.orig python"
broken "the gateway's Python through file/." \
    "cd '$HUB/main/xiaozhi-server/.venv/bin' && mv python ../python.orig && echo py > python.real && ln -s python.real/. python" \
    "cd '$HUB/main/xiaozhi-server/.venv/bin' && rm python python.real && mv ../python.orig python"
broken "the gateway's Python missing" "mv '$R/home/ubuntu/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu/bin/python3.12' '$T/py3'" \
    "mv '$T/py3' '$R/home/ubuntu/.local/share/uv/python/cpython-3.12.11-linux-aarch64-gnu/bin/python3.12'"
broken "the gateway on a detached HEAD" "G -c core.logAllRefUpdates=false checkout -q --detach" "G -c core.logAllRefUpdates=false checkout -q main"
broken "an unpublished commit on main" \
    "G -c core.logAllRefUpdates=false update-ref refs/heads/main \$(G -c user.name=t -c user.email=t@example.invalid commit-tree -m private -p HEAD 'HEAD^{tree}')" \
    "G -c core.logAllRefUpdates=false update-ref refs/heads/main '$C' && G prune --expire=now"
broken "ubuntu's account expires" "sed -i '/^ubuntu:/s/:::$/::1:/' '$R/etc/shadow'" "sed -i '/^ubuntu:/s/::1:$/:::/' '$R/etc/shadow'"
broken "a file named after the mother device" "echo x > '$R/home/ubuntu/.local/share/uv/mother-host'" "rm '$R/home/ubuntu/.local/share/uv/mother-host'"
broken "a directory named after the maintainer" "mkdir '$R/opt/chris-yyau'" "rmdir '$R/opt/chris-yyau'"
broken "ubuntu's sudo rule in a file sudo skips" "mv '$R/etc/sudoers.d/90-ubuntu' '$R/etc/sudoers.d/90-ubuntu.disabled'" "mv '$R/etc/sudoers.d/90-ubuntu.disabled' '$R/etc/sudoers.d/90-ubuntu'"
broken "a later sudo rule asking ubuntu for a password" "echo 'ubuntu ALL=(ALL) PASSWD: ALL' > '$R/etc/sudoers.d/99-later'" "rm '$R/etc/sudoers.d/99-later'"
broken "rules after sudoers' @includedir" "echo '%sudo ALL=(ALL:ALL) ALL' >> '$R/etc/sudoers'" "sed -i '\$d' '$R/etc/sudoers'"
broken "a later password rule for a group of ubuntu's" "echo '%audio ALL=(ALL) PASSWD:ALL' > '$R/etc/sudoers.d/99-audio'" "rm '$R/etc/sudoers.d/99-audio'"
broken "a later password rule listing ubuntu" "echo 'root,ubuntu ALL=(ALL) PASSWD:ALL' > '$R/etc/sudoers.d/99-list'" "rm '$R/etc/sudoers.d/99-list'"
broken "a later password rule for uid 1000" "echo '#1000 ALL=(ALL) PASSWD:ALL' > '$R/etc/sudoers.d/99-uid'" "rm '$R/etc/sudoers.d/99-uid'"
broken "a later password rule in a spaced list" "echo 'root, ubuntu ALL=(ALL) PASSWD:ALL' > '$R/etc/sudoers.d/99-spaced'" "rm '$R/etc/sudoers.d/99-spaced'"
broken "a password rule after a comment with no newline" "printf '# note' > '$R/etc/sudoers.d/95-note'; echo 'ubuntu ALL=(ALL) PASSWD:ALL' > '$R/etc/sudoers.d/99-later'" \
    "rm '$R/etc/sudoers.d/95-note' '$R/etc/sudoers.d/99-later'"
broken "an empty secure_path, which visudo rejects" "sed -i '1i Defaults secure_path=\"\"' '$R/etc/sudoers'" "sed -i 1d '$R/etc/sudoers'"
broken "a secure_path with an escaped closing quote" "sed -i '1i Defaults secure_path=\"/usr/bin\\\\\"' '$R/etc/sudoers'" "sed -i 1d '$R/etc/sudoers'"
broken "a secure_path without the tools' directories" "sed -i '1i Defaults secure_path=\"/nonexistent\"' '$R/etc/sudoers'" "sed -i 1d '$R/etc/sudoers'"
broken "sudo requiring a terminal" "sed -i '1i Defaults requiretty' '$R/etc/sudoers'" "sed -i 1d '$R/etc/sudoers'"
broken "a world-writable /etc/sudoers" "chmod o+w '$R/etc/sudoers'" "chmod o-w '$R/etc/sudoers'"
broken "ubuntu's sudoers file owned by ubuntu" "chown 1000 '$R/etc/sudoers.d/90-ubuntu'" "chown 0 '$R/etc/sudoers.d/90-ubuntu'"
broken "a group-writable /etc/sudoers.d" "chmod g+w '$R/etc/sudoers.d'" "chmod g-w '$R/etc/sudoers.d'"
broken "an indented #includedir, which sudo reads as a comment" "sed -i '\$s/^@/ #/' '$R/etc/sudoers'" "sed -i '\$s/^ #/@/' '$R/etc/sudoers'"
broken "a negative uid line, which visudo rejects" "echo '#-1 this is invalid' > '$R/etc/sudoers.d/99-neg'" "rm '$R/etc/sudoers.d/99-neg'"
broken "a removed account's file outside its home" "echo x > '$R/opt/diary'; chown 1001 '$R/opt/diary'" "rm '$R/opt/diary'"
broken "a removed group's file" "echo x > '$R/opt/diary'; chown 0:1001 '$R/opt/diary'" "rm '$R/opt/diary'"
# shellcheck disable=SC2016 # the inner sh expands them
# (|| : so the run on the old allowlist.sh, which has no stock_hosts, gets to its failures;
# "hosts is Ubuntu's stock file" fails when stock_hosts does)
sh -c '. "$1/allowlist.sh"; stock_hosts' sh "$IMG" > "$T/stock-hosts" || :
broken "ubuntu named after the owner" "sed -i 's/^ubuntu:x:1000:1000:Ubuntu:/ubuntu:x:1000:1000:Mother Owner:/' '$R/etc/passwd'" \
    "sed -i 's/^ubuntu:x:1000:1000:Mother Owner:/ubuntu:x:1000:1000:Ubuntu:/' '$R/etc/passwd'"
broken "ubuntu's AccountsService photo" "echo photo > '$R/var/lib/AccountsService/icons/ubuntu'" "rm '$R/var/lib/AccountsService/icons/ubuntu'"
broken "an e-mail in ubuntu's AccountsService entry" "echo Email=owner@example.invalid >> '$R/var/lib/AccountsService/users/ubuntu'" "sed -i '\$d' '$R/var/lib/AccountsService/users/ubuntu'"
broken "ubuntu's AccountsService entry as a link" "mv '$R/var/lib/AccountsService/users/ubuntu' '$T/as-ubuntu'; ln -s /etc/passwd '$R/var/lib/AccountsService/users/ubuntu'" \
    "rm '$R/var/lib/AccountsService/users/ubuntu'; mv '$T/as-ubuntu' '$R/var/lib/AccountsService/users/ubuntu'"
broken "a LAN name in /etc/hosts" "echo '192.168.1.20 nas.home' >> '$R/etc/hosts'" "sed -i '\$d' '$R/etc/hosts'"
broken "/etc/machine-info" "echo 'PRETTY_HOSTNAME=x' > '$R/etc/machine-info'" "rm '$R/etc/machine-info'"
broken "a name after ubuntu's session" "sed -i 's/^Session=plasma$/Session=plasma RealName=Owner/' '$R/var/lib/AccountsService/users/ubuntu'" \
    "sed -i 's/^Session=plasma RealName=Owner$/Session=plasma/' '$R/var/lib/AccountsService/users/ubuntu'"
broken "/etc/hosts as a link" "mv '$R/etc/hosts' '$T/hosts'; ln -s '$T/stock-hosts' '$R/etc/hosts'" "rm '$R/etc/hosts'; mv '$T/hosts' '$R/etc/hosts'"
broken "a timesyncd drop-in after ours" "echo 'NTP=time.example.invalid' > '$R/etc/systemd/timesyncd.conf.d/zz-other.conf'" "rm '$R/etc/systemd/timesyncd.conf.d/zz-other.conf'"
broken "AccountsService icons as a link" "mv '$R/var/lib/AccountsService/icons' '$T/icons-dir'; ln -s '$T/icons-dir' '$R/var/lib/AccountsService/icons'" \
    "rm '$R/var/lib/AccountsService/icons'; mv '$T/icons-dir' '$R/var/lib/AccountsService/icons'"
broken "a machine-id" "echo 0123456789abcdef0123456789abcdef > '$R/etc/machine-id'" ": > '$R/etc/machine-id'"
broken "a timesyncd drop-in directory as a link" "mkdir -p '$R/run/systemd' '$R/usr/share/td'; echo 'NTP=time.example.invalid' > '$R/usr/share/td/a.conf'; ln -s ../../usr/share/td '$R/run/systemd/timesyncd.conf.d'" \
    "rm '$R/run/systemd/timesyncd.conf.d'; rm -r '$R/usr/share/td'"
broken "a relative link climbing out of the root" "ln -s ../../../../../../../tmp '$R/etc/climb'" "rm '$R/etc/climb'"
broken "a relative link out of the root through /var/run" "ln -s /run '$R/var/run'; ln -s ../run/../../etc '$R/var/lib/out'" "rm '$R/var/run' '$R/var/lib/out'"
broken "/var/log as a link inside the root" "mv '$R/var/log' '$R/var/log.real'; ln -s log.real '$R/var/log'" "rm '$R/var/log'; mv '$R/var/log.real' '$R/var/log'"
broken "ubuntu without passwordless sudo" "mv '$R/etc/sudoers.d/90-ubuntu' '$T/90-ubuntu'" "mv '$T/90-ubuntu' '$R/etc/sudoers.d/90-ubuntu'"
broken "a second env" "mkdir '$R/opt/thinksmart/envs/extra'" "rmdir '$R/opt/thinksmart/envs/extra'"
if check >/dev/null 2>&1; then ok "every break was put back"; else no "every break was put back"; fi
# the caller's git settings do not reach the checks (here: one that hides untracked files)
echo x > "$HUB/scripts/mine2.sh"
if GIT_CONFIG_PARAMETERS="'status.showuntrackedfiles'='no'" sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$REPO" >/dev/null 2>&1; then
    no "an untracked file the caller's git settings hide"
else ok "an untracked file the caller's git settings hide"; fi
rm "$HUB/scripts/mine2.sh"
# objects only in a store the caller's environment names: the image would ship without them
mkdir "$T/alt"; mv "$HUB/.git/objects/pack" "$T/alt/pack"; mkdir "$HUB/.git/objects/pack"
if GIT_ALTERNATE_OBJECT_DIRECTORIES="$T/alt" sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$REPO" >/dev/null 2>&1; then
    no "gateway objects only in the caller's alternate store"
else ok "gateway objects only in the caller's alternate store"; fi
rmdir "$HUB/.git/objects/pack"; mv "$T/alt/pack" "$HUB/.git/objects/pack"
# a rejected .git is never handed to git: a clean filter in its config would run in git status
printf '[filter "x"]\n\tclean = touch %s/filter-ran; cat\n' "$T" >> "$HUB/.git/config"
mkdir "$HUB/.git/info"; echo '* filter=x' > "$HUB/.git/info/attributes"; touch "$HUB/scripts/bootstrap.sh"
check >/dev/null 2>&1 || true
nt "no git command on a rejected .git" test -e "$T/filter-ran"
cp "$IMG/hub-git-config" "$HUB/.git/config"; rm -r "$HUB/.git/info"
# a directory find cannot list is not read as empty
mkdir "$T/shim"
# shellcheck disable=SC2016 # $1 and $@ are for the shim to expand
printf '#!/bin/sh\ncase $1 in */xiaozhi-server/tmp) echo "find: cannot read $1" >&2; exit 1 ;; esac\nexec %s "$@"\n' \
    "$(command -v find)" > "$T/shim/find"
chmod +x "$T/shim/find"
if PATH="$T/shim:$PATH" sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$REPO" >/dev/null 2>&1; then
    no "a directory find cannot list"
else ok "a directory find cannot list"; fi
# the same root given with a trailing / and through ..: still the same result
if sh "$IMG/check-rootfs.sh" "$R/" "$T/ids" "$REPO" >/dev/null 2>&1; then ok "root with a trailing /"; else no "root with a trailing /"; fi
if sh "$IMG/check-rootfs.sh" "$R/../${R##*/}" "$T/ids" "$REPO" >/dev/null 2>&1; then ok "root through .."; else no "root through .."; fi

# a repository without system-files.txt: a tool error (2), never ok
mkdir -p "$T/norepo/image"
rc=0; sh "$IMG/check-rootfs.sh" "$R" "$T/ids" "$T/norepo" >/dev/null 2>&1 || rc=$?
if [ "$rc" = 2 ]; then ok "check-rootfs exits 2 without system-files.txt"; else no "check-rootfs exits 2 without system-files.txt (got $rc)"; fi

# an account whose home is outside /home: sanitize stops instead of leaving it behind
# a root-owned file whose name holds a newline is no stray owner
nl=$(printf 'nl\nname')
echo x > "$R/opt/$nl"
if check >/dev/null 2>&1; then ok "a file name with a newline passes"; else no "a file name with a newline passes"; fi
rm "$R/opt/$nl"

R=$T/root2
sh "$IMG/tests/make-fake-root.sh" "$R"
echo 'bob:x:1002:1002:Bob:/srv/bob:/bin/sh' >> "$R/etc/passwd"
nt "sanitize refuses a home outside /home" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"

# a home that names ubuntu's another way: sanitize stops and ubuntu's home stays
R=$T/root3
sh "$IMG/tests/make-fake-root.sh" "$R"
echo 'bob:x:1002:1002:Bob:/home//ubuntu:/bin/sh' >> "$R/etc/passwd"
nt "sanitize refuses /home//ubuntu" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "ubuntu's home survives /home//ubuntu" test -d "$R/home/ubuntu/xiaozhi-hub-server"

# a link out of the copy into the build's own directories (here $T/out stands for /w and /out)
R=$T/root4
sh "$IMG/tests/make-fake-root.sh" "$R"
mkdir -p "$T/out/connections"; echo keep > "$T/out/connections/x"
rm -r "$R/etc/NetworkManager/system-connections"; ln -s "$T/out/connections" "$R/etc/NetworkManager/system-connections"
SANITIZE_GUARD=$T/out nt "sanitize refuses a link into the build's directories" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing deleted through the link" test -f "$T/out/connections/x"

# a file link: the hostname write would go through it
R=$T/root6
sh "$IMG/tests/make-fake-root.sh" "$R"
echo keep > "$T/out/hostname"; rm "$R/etc/hostname"; ln -s "$T/out/hostname" "$R/etc/hostname"
SANITIZE_GUARD=$T/out nt "sanitize refuses a file link into the build's directories" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing written through the link" grep -qx keep "$T/out/hostname"

# AccountsService's icons as a link out of the root: sanitize stops before it changes anything
R=$T/root9
sh "$IMG/tests/make-fake-root.sh" "$R"
mv "$R/var/lib/AccountsService/icons" "$T/icons9"; ln -s "$T/icons9" "$R/var/lib/AccountsService/icons"
nt "sanitize refuses linked AccountsService icons" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing deleted through the icons link" test -f "$T/icons9/ubuntu"

# /etc/hosts as a link out of the root (not into the build's own directories): sanitize stops and
# writes nothing through it
R=$T/root10
sh "$IMG/tests/make-fake-root.sh" "$R"
printf '192.168.1.20\tnas.home\n' > "$T/lan-hosts"; rm "$R/etc/hosts"; ln -s "$T/lan-hosts" "$R/etc/hosts"
nt "sanitize refuses a linked /etc/hosts" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing written through the hosts link" grep -qx '192.168.1.20	nas.home' "$T/lan-hosts"

# AccountsService's icons behind uv's minor-version link, a directory only the image has: sanitize stops
R=$T/root12
sh "$IMG/tests/make-fake-root.sh" "$R"
UVP=$R/home/ubuntu/.local/share/uv/python
mv "$R/var/lib/AccountsService/icons" "$UVP/cpython-3.12.11-linux-aarch64-gnu/icons"
ln -s /home/ubuntu/.local/share/uv/python/cpython-3.12-linux-aarch64-gnu/icons "$R/var/lib/AccountsService/icons"
nt "sanitize refuses icons behind uv's link" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "nothing deleted behind uv's link" test -f "$UVP/cpython-3.12.11-linux-aarch64-gnu/icons/ubuntu"

# sanitize's scratch files, held by the capture as links out of the root: nothing written through them
R=$T/root11
sh "$IMG/tests/make-fake-root.sh" "$R"
echo keep > "$T/scratch-passwd"; ln -s "$T/scratch-passwd" "$R/etc/passwd.sanitize"
echo keep > "$T/scratch-as"; ln -s "$T/scratch-as" "$R/var/lib/AccountsService/users/ubuntu.sanitize"
t "sanitize runs over linked scratch files" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
# shellcheck disable=SC2016 # the inner sh expands them
t "nothing written through the scratch-file links" sh -c 'grep -qx keep "$1" && grep -qx keep "$2"' sh "$T/scratch-passwd" "$T/scratch-as"

# the current client without its .venv link: sanitize stops instead of deleting every env
R=$T/root5
sh "$IMG/tests/make-fake-root.sh" "$R"
rm "$R/opt/thinksmart/client/1.0.0/.venv"
nt "sanitize refuses a client without .venv" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "the client's env survives" test -d "$R/opt/thinksmart/envs/new"
# a .venv into envs/ that names no env there, or one below it: the same
for bad in missing new/sub; do
    R=$T/root5-${bad%%/*}
    sh "$IMG/tests/make-fake-root.sh" "$R"
    ln -sfn "../../envs/$bad" "$R/opt/thinksmart/client/1.0.0/.venv"
    nt "sanitize refuses a .venv to envs/$bad" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
    t "the envs survive a .venv to envs/$bad" test -d "$R/opt/thinksmart/envs/new" -a -d "$R/opt/thinksmart/envs/old"
done

# one sudoers file with a removed account's rule and ubuntu's: sanitize stops, ubuntu's rule stays
R=$T/root7
sh "$IMG/tests/make-fake-root.sh" "$R"
printf 'alice ALL=(ALL) NOPASSWD:ALL\nubuntu ALL=(ALL) NOPASSWD:ALL\n' > "$R/etc/sudoers.d/90-cloud-init-users"
nt "sanitize refuses a sudoers file shared with ubuntu" sh "$IMG/sanitize-rootfs.sh" "$R" "$T/template.yaml" "$REPO"
t "the shared sudoers file survives" grep -qx 'ubuntu ALL=(ALL) NOPASSWD:ALL' "$R/etc/sudoers.d/90-cloud-init-users"

# a removed account's sudoers file with a space in its name goes, and nothing else does
R=$T/root8
sh "$IMG/tests/make-fake-root.sh" "$R"
echo 'alice ALL=(ALL) NOPASSWD:ALL' > "$R/etc/sudoers.d/90 alice"
echo keep > "$T/alice"
# shellcheck disable=SC2016 # the inner sh expands them
t "sanitize runs with a sudoers file name holding a space" sh -c 'cd "$1" && sh "$2/sanitize-rootfs.sh" "$3" "$1/template.yaml" "$4"' sh "$T" "$IMG" "$R" "$REPO"
nt "the removed account's spaced sudoers file is gone" test -e "$R/etc/sudoers.d/90 alice"
t "no file outside the root removed" grep -qx keep "$T/alice"

echo "1..$n"
exit "$failed"
