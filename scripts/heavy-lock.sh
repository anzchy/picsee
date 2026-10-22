#!/usr/bin/env bash
# Run heavy jobs under picsee's flock, then mdpro's shared directory lock.
# Usage: scripts/heavy-lock.sh <command...>
# PICSEE_HEAVY_LOCK: persistent file (default ~/.picsee/locks/heavy.lock).
# PICSEE_MDPRO_LOCK: mdpro directory (default ~/.cache/mdpro-heavy.lock); off skips.
# PICSEE_HEAVY_LOCK_WAIT_SECS: acquisition timeout, default 1800; exits 75.
# PICSEE_HEAVY_LOCK_KILL_GRACE_SECS: TERM grace before KILL, default 10.
# PICSEE_HEAVY_LOCK_HELD=1: inherited nesting flag; nested calls run directly.
# The inherited descriptor owns the lock until its last close, including after
# this launcher is SIGKILLed. Never unlink/rename the persistent lock file.
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command...>" >&2
  exit 64
fi
if [[ "${PICSEE_HEAVY_LOCK_HELD:-}" == "1" ]]; then
  export MDPRO_HEAVY_LOCK_HELD=1
  exec "$@"
fi
exec python3 "$(dirname "$0")/tdd/heavy-lock.py" "$@"
