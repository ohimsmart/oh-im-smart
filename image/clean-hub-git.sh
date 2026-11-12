#!/bin/sh
# The captured gateway checkout as a new device gets it (spec §5.3 point 3): COMMIT checked out as
# main, tracking origin/main; .git/config is image/hub-git-config (no insteadOf, proxy, extraHeader
# or include from the mother device); no other refs (tags, notes, stash, branches, other remotes)
# and no objects only they kept alive; .git holds only what git needs (no commit or merge messages,
# rebase state, logs, info/exclude) and no hooks, not even git's samples.
#   clean-hub-git.sh HUB_DIR COMMIT
# Run as the checkout's owner (build-image.sh: uid 1000), so .git stays ubuntu's.
set -eu
# git run from a hook or another tool would otherwise act on that repository: no GIT_* variable
# (GIT_DIR, GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG_PARAMETERS...) reaches git here
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
# nor the caller's global or system settings (status.showUntrackedFiles, hooksPath...)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
D=${1:?hub dir}; C=${2:?commit}
S=$(cd "$(dirname "$0")" && pwd)
# The mother device's hooks and config must never run: hooks go before the first git command, the
# config is read as a plain file and replaced, and every git call runs without hooks or fsmonitor.
rm -rf "$D/.git/hooks"
# the config is replaced, so it must not need a setting it would lose (sha256 objects, worktree config)
[ -z "$(git config -f "$D/.git/config" --get-regexp '^extensions\.' || true)" ] \
    || { echo "clean-hub-git: the repository uses git extensions"; exit 1; }
cp "$S/hub-git-config" "$D/.git/config"
G() { git -c safe.directory='*' -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$D" "$@"; }
[ "$(G rev-parse HEAD)" = "$C" ] || { echo "clean-hub-git: HEAD is not $C"; exit 1; }
# a power cut right after the admin page's update check leaves these zero-filled; both are rewritten
rm -f "$D/.git/FETCH_HEAD" "$D/.git/refs/remotes/origin/main"
G checkout -q -B main "$C"
# a new index from the commit: assume-unchanged or skip-worktree entries would hide local edits
# from status, and reset --hard puts every tracked file back as committed
rm -f "$D/.git/index"
G reset -q --hard "$C"
G for-each-ref --format='%(refname)' | while read -r ref; do
    case $ref in refs/heads/main) ;; *) G update-ref --no-deref -d "$ref" ;; esac
done
# The commit is on the published main (build-image.sh checks it), so origin/main may point at it
G update-ref refs/remotes/origin/main "$C"
G reflog expire --expire=now --all
G gc -q --prune=now
# what is left in .git: only what git needs to work
for f in "$D"/.git/* "$D"/.git/.[!.]* "$D"/.git/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        case ${f##*/} in HEAD|config|index|objects|refs|packed-refs|shallow) ;; *) rm -rf "$f" ;; esac
    fi
done
[ -z "$(G status --porcelain --untracked-files=all)" ] || { echo "clean-hub-git: working tree is not clean:"; G status --short | head; exit 1; }
# ignored files are not in status: list them, check-rootfs.sh holds them to image/hub-ignored.txt
G ls-files --others --ignored --exclude-standard --directory | sed 's|^|clean-hub-git: ignored: |'
