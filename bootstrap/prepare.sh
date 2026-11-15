#!/bin/bash
# Make a copy of the upstream bootstrap image that boots with a machine-id, your WiFi and your own
# login password (spec §7.3). Optional: the unchanged upstream image still works over USB.
# Usage: bootstrap/prepare.sh <bootstrap image> <output image>
# The work happens in a Docker container (no --privileged, no network, your own user id), so this
# runs the same on Linux and macOS (whose /bin/bash is 3.2: keep this script to what 3.2 has).
# The questions are asked inside the container; this script never sees the answers.
# Delete the output after flashing: it may hold your WiFi password.
set -euo pipefail
umask 077
unset CDPATH    # it would make `cd` print the directory, which `$(cd … && pwd)` would capture too

die() { printf 'prepare: %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || die "usage: prepare.sh <bootstrap image> <output image>"
SRC=$1 OUT=$2
# A name starting with "-" would be read as an option by cp, ln and dirname.
case $SRC in -*) SRC=./$SRC ;; esac
case $OUT in -*) OUT=./$OUT ;; esac
[ -f "$SRC" ] && [ -r "$SRC" ] || die "cannot read $SRC"
[ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die "$OUT already exists: choose another name or delete it first"
HERE=$(cd "$(dirname "$0")" && pwd) || die "cannot find the directory prepare.sh is in"
OUTDIR=$(cd "$(dirname "$OUT")" 2>/dev/null && pwd) || die "no such directory: $(dirname "$OUT")"
command -v docker >/dev/null 2>&1 || die "Docker is needed: install Docker Desktop (macOS) or Docker Engine (Linux)"
docker info >/dev/null 2>&1 || die "Docker is installed but not running, or this user may not use it"

NAME=ohimsmart-prepare-$$
WORK='' RUN='' CLIENT='' TTYSAVE=''
cleanup() {
    trap '' INT TERM HUP     # a second Ctrl-C must not stop the cleanup halfway
    set +e                   # nor a failed step: every later step must still run
    # Stop the docker client before removing the container, so it cannot start one afterwards.
    # It passes the signal on to the container; if both are still there after 10 seconds, kill it.
    if [ -n "$CLIENT" ]; then
        kill "$CLIENT" 2>/dev/null || true
        i=0
        while kill -0 "$CLIENT" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
        kill -9 "$CLIENT" 2>/dev/null || true
        wait "$CLIENT" 2>/dev/null || true
    fi
    # The terminal and the copy (it may hold the WiFi password) before docker, which hangs with a
    # hung Docker daemon: then only kill -9 is left, and it must find nothing left to delete.
    if [ -n "$TTYSAVE" ]; then stty "$TTYSAVE" 2>/dev/null || true; fi   # a killed client leaves it raw
    if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
    # Only this run's container, found by its label: a container of the same name may be another's.
    if [ -n "$RUN" ]; then
        ids=$(docker ps -aq --filter "label=ohimsmart.run=$RUN" 2>/dev/null)
        for id in $ids; do docker rm -f "$id" >/dev/null 2>&1 || true; done
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Private (700) and next to the output, so the finished file is linked, never copied, into place.
WORK=$(mktemp -d "$OUTDIR/.prepare.XXXXXX") || die "cannot write in $OUTDIR"
RUN="$$-${WORK##*/.prepare.}"
IMAGE=$(docker build -q "$HERE" 2>"$WORK/build.log") || {
    cat "$WORK/build.log" >&2
    die "could not build the container image (the first build needs the internet)"
}
cp "$SRC" "$WORK/bootstrap.img" || die "could not copy $SRC into $OUTDIR (is there room for 1 GB?)"
chmod 600 "$WORK/bootstrap.img"      # a read-only source would make a read-only copy
TTY=
if [ -t 0 ]; then TTY=-t; TTYSAVE=$(stty -g); fi
# In the background with `wait`, so a signal to this script runs its traps at once; `<&0` keeps the
# questions on this script's stdin. --mount, unlike -v, refuses a missing WORK instead of creating it.
# No --rm: the client's own exit status is not trusted (the detach keys, Ctrl-P Ctrl-Q, end it
# with 0 while the container runs on), so the container is asked how it ended, then removed.
# --log-driver none: the container's output (the questions, the WiFi name echoed) is kept nowhere.
# --cidfile and --label: the container is asked about and removed by its id and this run's label,
# never by its name, which a container left behind by an earlier run with the same process id
# could hold.
docker run -i $TTY --init --name "$NAME" --label "ohimsmart.run=$RUN" --cidfile "$WORK/cid" \
    --network none --read-only --tmpfs /tmp --log-driver none --user "$(id -u):$(id -g)" \
    --mount "type=bind,\"source=$WORK\",target=/work" "$IMAGE" /work/bootstrap.img <&0 &
CLIENT=$!
wait "$CLIENT" || true
CLIENT=
state=
if [ -s "$WORK/cid" ]; then
    # In the background too: a signal must not wait for an inspect that a hung daemon never ends.
    docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$(cat "$WORK/cid")" >"$WORK/state" 2>/dev/null &
    CLIENT=$!
    if wait "$CLIENT"; then state=$(cat "$WORK/state"); fi
    CLIENT=
fi
case $state in
    'exited 0') ;;
    'exited 130') die "stopped; nothing was written" ;;
    'exited 1') exit 1 ;;   # prepare-image.sh has said why
    exited\ *) die "the container ended with status ${state#exited }; nothing was written" ;;
    running*|paused*|restarting*) die "detached from the container before it finished; nothing was written" ;;
    *) die "the container did not run; nothing was written" ;;
esac
# The few steps that publish the result run to the end: a signal between ln and the check below
# would leave a link the cleanup does not know about.
trap '' INT TERM HUP
# A hard link, not mv: it fails instead of replacing a file that appeared at OUT meanwhile.
# A directory that appeared at OUT would take the link inside it: take it back out.
ln "$WORK/bootstrap.img" "$OUT" 2>/dev/null || die "could not create $OUT"
if [ -L "$OUT" ] || ! [ "$OUT" -ef "$WORK/bootstrap.img" ]; then
    if [ "$OUT/bootstrap.img" -ef "$WORK/bootstrap.img" ]; then rm -f "$OUT/bootstrap.img"; fi
    die "$OUT appeared while this ran: nothing was written"
fi
printf 'prepare: wrote %s. Delete it after flashing: it may hold your WiFi password, and holds a hash of your login password.\n' "$OUT" >&2
