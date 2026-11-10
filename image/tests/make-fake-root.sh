#!/bin/sh
# A root filesystem shaped like a capture of the mother device, carrying this repository's system
# layer and everything sanitize must remove. Run under fakeroot:
#   fakeroot sh image/tests/make-fake-root.sh DIR
# Also writes DIR/../template.yaml (the gateway's config template).
set -eu
# git run from a hook or another tool would otherwise act on that repository: no GIT_* variable
# (GIT_DIR, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_PARAMETERS...) reaches git here
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
# nor the developer's global or system git settings (hooksPath, signing...)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
REPO=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "${1:?dir}"
R=$(cd "$1" && pwd)
cd "$R"
mkdir -p etc/skel etc/sudoers.d etc/NetworkManager/system-connections etc/ssh lib/modules root/.aws \
    var/log var/lib/dbus var/lib/systemd var/lib/thinksmart-update var/spool/cron/crontabs var/mail \
    tmp var/tmp usr/share/zoneinfo/Etc usr/local home/alice home/ubuntu/xiaozhi-workspace \
    opt/thinksmart/system/backup opt/thinksmart/client/1.0.0 opt/thinksmart/client/0.1.6 \
    opt/thinksmart/envs/new opt/thinksmart/envs/old

# the system layer, as image/device-setup.sh files puts it there
grep -v -e '^#' -e '^[[:space:]]*$' -e '^require ' "$REPO/image/system-files.txt" | while read -r src dst mode _; do
    [ "$src" = - ] && continue
    mkdir -p "$R${dst%/*}"
    install -m "$mode" "$REPO/$src" "$R$dst"
done
# the mother device's keep files differ from the repository's: sanitize must replace them
echo 'SOURCES="https://github.com/justhalfbit/xiaozhi-thinksmart-client/releases/"' > etc/thinksmart-update.conf
echo '#HELP_URL="https://github.com/justhalfbit/xiaozhi-hub-server"' > etc/thinksmart-kiosk.conf

cat > etc/passwd <<'E'
root:x:0:0:root:/root:/bin/bash
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
alice:x:1001:1001:Alice:/home/alice:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
E
cat > etc/shadow <<'E'
root:$6$old$roothash:19000:0:99999:7:::
www-data:*:19000:0:99999:7:::
ubuntu:$6$old$ubuntuhash:19000:0:99999:7:::
alice:$6$old$alicehash:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
E
cat > etc/group <<'E'
root:x:0:
sudo:x:27:ubuntu,alice
audio:x:29:alice,ubuntu
ubuntu:x:1000:
alice:x:1001:
carol:x:1003:
www-data:x:1005:
E
cat > etc/gshadow <<'E'
root:*::
sudo:*:alice:ubuntu,alice
audio:*::alice,ubuntu
ubuntu:!::
alice:!::
carol:!::
www-data:!::
E
printf 'ubuntu:100000:65536\nalice:165536:65536\n' > etc/subuid
cp etc/subuid etc/subgid
for f in passwd shadow group gshadow subuid subgid; do cp "etc/$f" "etc/$f-"; done
chmod 640 etc/shadow etc/gshadow

echo 'alice ALL=(ALL) NOPASSWD:ALL' > etc/sudoers.d/alice
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > etc/sudoers.d/90-ubuntu
echo '* * * * * curl example.com' > var/spool/cron/crontabs/alice
echo 'mail' > var/mail/alice

printf '# skel bashrc\n' > etc/skel/.bashrc
printf '# skel profile\n' > etc/skel/.profile
printf '# skel logout\n' > etc/skel/.bash_logout
echo mother-host > etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\tmother-host\n' > etc/hosts
echo Asia/Shanghai > etc/timezone
: > usr/share/zoneinfo/Etc/UTC
ln -s /usr/share/zoneinfo/Asia/Shanghai etc/localtime

echo 'export TOKEN=root-token' > root/.bashrc
echo 'export TOKEN=root-token' > root/.profile
echo '[default]' > root/.aws/credentials
echo 'alice' > home/alice/notes
# left by userdel without -r: no account owns it
mkdir -p home/retired; echo 'diary' > home/retired/diary.txt
mkdir -p var/lib/AccountsService/users var/lib/plocate
echo '[User]' > var/lib/AccountsService/users/alice
echo 'every file name' > var/lib/plocate/plocate.db

H=home/ubuntu
echo 'export TOKEN=user-token' > $H/.bashrc
echo 'export TOKEN=user-token' > $H/.profile
echo 'clear' > $H/.bash_logout
U=$H/.config/systemd/user
mkdir -p $U/default.target.wants $U/pipewire-pulse.service.wants $H/.config/thinksmart-kiosk \
    $H/.local/share/uv/python/bin $H/.local/bin $H/.local/state/wireplumber
# a stand-in until the system layer carries this unit (plan Task 8)
[ -e $U/vcnl4200-proximity-daemon.service ] || printf '[Unit]\n' > $U/vcnl4200-proximity-daemon.service
# systemd's per-user manager settings: DefaultEnvironment= can hold a key
echo 'DefaultEnvironment=API_KEY=sk-user-conf' > $H/.config/systemd/user.conf
printf '[Service]\nEnvironment=API_KEY=sk-from-the-mother\n' > $U/xiaozhi-hub.service
echo 'Environment=API_KEY=sk-leak' > $U/leak.service
ln -s ../idle-blanker.service $U/default.target.wants/idle-blanker.service
ln -s ../thinksmart-mic.service $U/default.target.wants/thinksmart-mic.service
# systemctl --user enable writes absolute links
ln -s /home/ubuntu/.config/systemd/user/xiaozhi-hub.service $U/default.target.wants/xiaozhi-hub.service
ln -s ../leak.service $U/default.target.wants/leak.service
ln -s ../thinksmart-mic.service $U/pipewire-pulse.service.wants/thinksmart-mic.service
echo old > $H/.config/pipewire/pipewire.conf.d/20-experiment.conf
echo en > $H/.config/thinksmart-kiosk/lang
echo py > $H/.local/share/uv/python/bin/python3
echo uv > $H/.local/bin/uv
echo uvx > $H/.local/bin/uvx
echo 'token' > $H/.local/bin/my-script
echo state > $H/.local/state/wireplumber/default-routes

HUB=$H/xiaozhi-hub-server
mkdir -p $HUB/main/xiaozhi-server/data $HUB/scripts
echo 'secret: 1' > $HUB/main/xiaozhi-server/data/.config.yaml
echo 'MIT License, Copyright (c) justhalfbit, https://github.com/justhalfbit/xiaozhi-hub-server' > $HUB/LICENSE
echo 'echo install' > $HUB/scripts/bootstrap.sh
printf 'server:\n  LLM: ClaudeCLI\n' > $HUB/scripts/config.template.yaml
echo 'print(1)' > $HUB/main/xiaozhi-server/app.py
# the gateway's .venv as uv makes it: python linked to uv's, lib64 a link to a directory
mkdir -p $HUB/main/xiaozhi-server/.venv/bin $HUB/main/xiaozhi-server/.venv/lib
ln -s /home/ubuntu/.local/share/uv/python/bin/python3 $HUB/main/xiaozhi-server/.venv/bin/python
ln -s lib $HUB/main/xiaozhi-server/.venv/lib64
# the gateway checkout as the mother device has it: the published commit, plus an unpublished one
# kept only by a tag, a mirror insteadOf, a hook; and a system-wide insteadOf
printf 'main/xiaozhi-server/data/\nmain/xiaozhi-server/tmp/\n.env\n.venv\n' > $HUB/.gitignore
FG() { git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false -C $HUB "$@"; }
FG init -q -b main
FG remote add origin https://github.com/ohimsmart/oh-im-smart-gateway.git
FG add -A
FG commit -q -m published
echo 'private notes' > $HUB/notes.txt
FG add notes.txt
FG commit -q -m private
FG tag private-work
FG reset -q --hard HEAD~1
# a local edit to a tracked file, hidden from git status
echo 'echo local edit' > $HUB/scripts/bootstrap.sh
FG update-index --skip-worktree scripts/bootstrap.sh
FG config url.https://mirror.example/.insteadOf https://github.com/
printf '#!/bin/sh\n' > $HUB/.git/hooks/post-merge
# hooks that would fire during the cleanup's checkout and ref updates: each leaves a marker
for h in post-checkout reference-transaction; do
    # shellcheck disable=SC2016 # $(...) is for the hook to run, not for now
    printf '#!/bin/sh\ntouch "$(git rev-parse --show-toplevel)/main/xiaozhi-server/data/%s-ran"\n' $h > $HUB/.git/hooks/$h
    chmod +x $HUB/.git/hooks/$h
done
echo 'merge msg' > $HUB/.git/MERGE_MSG
printf '[url "https://mirror.example/"]\n\tinsteadOf = https://github.com/\n' > etc/gitconfig

ln -s 1.0.0 opt/thinksmart/client/current
ln -s 0.1.6 opt/thinksmart/client/previous
ln -s ../../envs/new opt/thinksmart/client/1.0.0/.venv
ln -s ../../envs/old opt/thinksmart/client/0.1.6/.venv
echo 'https://github.com/justhalfbit/xiaozhi-thinksmart-client' > opt/thinksmart/client/0.1.6/README.md
echo 'https://github.com/justhalfbit/thinksmart-ubuntu-image' > opt/thinksmart/system/backup/conf

chown -R 1000:1000 home/ubuntu
chown -R 1001:1001 home/alice
cp $HUB/scripts/config.template.yaml ../template.yaml
