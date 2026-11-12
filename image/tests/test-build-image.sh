#!/bin/sh
# build-image.sh's checks that stop it before Docker runs:
#   sh image/tests/test-build-image.sh
set -eu
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
IMG=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
no() { n=$((n + 1)); echo "not ok $n - $1"; failed=1; }
# a capture whose hub commit is on no main (each run must stop before Docker), and a release manifest
# naming exactly its versions
mkdir -p "$T/work" "$T/hub"
printf '%s\n1.0.0\n5\nabc\n' 0000000000000000000000000000000000000000 > "$T/work/versions.txt"
echo '{"version": "1.0.0", "system": {"version": "5", "tree": "abc"}}' > "$T/manifest.json"
echo 'a secret' > "$T/secrets.txt"
git -C "$T/hub" init -q -b main
git -C "$T/hub" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m x
git -C "$T/hub" remote add origin https://github.com/ohimsmart/oh-im-smart-gateway.git
git -C "$T/hub" update-ref refs/remotes/origin/main HEAD
# build-image.sh clears every GIT_* variable: an empty HOME keeps the caller's ~/.gitconfig (an
# insteadOf would change the origin URL it checks) away from it
run() { HOME=$T XDG_CONFIG_HOME=$T bash "$IMG/build-image.sh" "$T/work" "$T/out" "$T/hub" "$@" > "$T/log" 2>&1; }
# git, but fetch does nothing and ls-remote answers $LSREMOTE: the published-main check without GitHub
REALGIT=$(command -v git)
mkdir "$T/bin"
# shellcheck disable=SC2016 # the generated script expands them when it runs
printf '#!/bin/sh\nfor a; do case $a in fetch) exit 0 ;; ls-remote) printf "%%s\\trefs/heads/main\\n" "$LSREMOTE"; exit 0 ;; esac; done\nexec "%s" "$@"\n' "$REALGIT" > "$T/bin/git"
chmod +x "$T/bin/git"
HEADC=$(git -C "$T/hub" rev-parse HEAD)

if HUB_MAIN=main RELEASE_MANIFEST=$T/manifest.json run "$T/secrets.txt"; then no "HUB_MAIN=main refused for a release"
elif grep -q 'is for test images only' "$T/log"; then ok "HUB_MAIN=main refused for a release"
else no "HUB_MAIN=main refused for a release"; fi
# a test image may: it gets past the check and stops at the hub commit (not on that main)
if HUB_MAIN=main ALLOW_UNRELEASED=1 run --test-image; then no "HUB_MAIN=main allowed for a test image"
elif grep -q 'is not on main' "$T/log" && ! grep -q 'is for test images only' "$T/log"; then ok "HUB_MAIN=main allowed for a test image"
else no "HUB_MAIN=main allowed for a test image"; fi
# origin/main must be what GitHub says main is
if PATH=$T/bin:$PATH LSREMOTE=1111111111111111111111111111111111111111 ALLOW_UNRELEASED=1 run --test-image; then
    no "an origin/main that is not GitHub's main refused"
elif grep -q "origin/main is not GitHub's main" "$T/log"; then ok "an origin/main that is not GitHub's main refused"
else no "an origin/main that is not GitHub's main refused"; fi
if PATH=$T/bin:$PATH LSREMOTE=$HEADC ALLOW_UNRELEASED=1 run --test-image; then no "GitHub's main accepted"
elif grep -q 'is not on origin/main' "$T/log" && ! grep -q "is not GitHub's main" "$T/log"; then ok "GitHub's main accepted"
else no "GitHub's main accepted"; fi

echo "1..$n"
exit "$failed"
