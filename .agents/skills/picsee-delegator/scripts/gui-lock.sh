#!/bin/zsh
# gui-lock.sh acquire|release|status|wait — the machine-wide desktop GUI lock shared with mdpro
# (mdpro ADR-0134 decision 6; agreed with mdpro-delegator 2026-10-24).
#
#   lock dir : $HOME/.cache/desktop-gui.lock/   (mkdir = acquire; atomic)
#   owner    : key=value lines; `owner` is the file that counts. picsee writes
#              project=picsee session=<name> batch=<run-id> start=<ISO> pid=<pid> expected_minutes=<n> purpose=<text>
#
# Take it before the FIRST GUI-driving action of a device run (launch, panels, keys, mouse, drags, screencapture,
# app activation) and hold it across relaunch sub-runs; release only after the app has quit (after cleanup), also on
# aborted runs. Builds and log reads don't need it (builds use scripts/heavy-lock.sh).
# Never remove another project's lock. A lock that looks stale is reported to the user, never removed.
#
# usage:
#   gui-lock.sh acquire <run-id> [expected_minutes=30] [purpose] [session=picsee-delegator]   → exit 0 held, 75 busy
#   gui-lock.sh wait <run-id> [expected_minutes] [purpose] [session] [max_wait_min=60]       → poll 60 s, then acquire
#   gui-lock.sh release <run-id>                                                             → only our own lock
#   gui-lock.sh status
set -u
L=$HOME/.cache/desktop-gui.lock
cmd=${1:-status}
show() { [[ -d $L ]] && { echo "HELD:"; sed 's/^/  /' "$L/owner" 2>/dev/null || echo "  (no owner file)"; } || echo "FREE"; }
case $cmd in
  status) show ;;
  acquire)
    run=${2:?run-id}; exp=${3:-30}; purpose=${4:-device run}; sess=${5:-picsee-delegator}
    mkdir -p "$HOME/.cache"
    if mkdir "$L" 2>/dev/null; then
      printf 'project=picsee\nsession=%s\nbatch=%s\nstart=%s\npid=%s\nexpected_minutes=%s\npurpose=%s\n' \
        "$sess" "$run" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$$" "$exp" "$purpose" > "$L/owner"
      echo "ACQUIRED $run"; exit 0
    fi
    echo "BUSY"; show; exit 75 ;;
  wait)
    run=${2:?run-id}; exp=${3:-30}; purpose=${4:-device run}; sess=${5:-picsee-delegator}; maxw=${6:-60}
    for i in $(seq 1 $maxw); do
      "$0" acquire "$run" "$exp" "$purpose" "$sess" >/dev/null && { echo "ACQUIRED $run after ${i} poll(s)"; exit 0; }
      sleep 60
    done
    echo "TIMEOUT after $maxw min — lock still held; report to the user, do not remove it"; show; exit 75 ;;
  release)
    run=${2:?run-id}
    [[ -d $L ]] || { echo "FREE (nothing to release)"; exit 0; }
    if grep -qx 'project=picsee' "$L/owner" 2>/dev/null && grep -qx "batch=$run" "$L/owner" 2>/dev/null; then
      rm "$L/owner" && rmdir "$L" && echo "RELEASED $run"; exit $?
    fi
    echo "REFUSED: lock is not ours ($run)"; show; exit 1 ;;
  *) echo "usage: gui-lock.sh acquire|wait|release|status …"; exit 2 ;;
esac
