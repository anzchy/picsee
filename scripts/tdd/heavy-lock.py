#!/usr/bin/env python3
"""Kernel-owned flock lifetime, inherited by the heavy job and its descendants.

Python's standard fcntl + pass_fds make descriptor inheritance explicit on macOS.
We only close our descriptor, never LOCK_UN: unlocking the shared open-file
description would also release a surviving descendant's lock after owner death.
"""
import errno
import fcntl
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def nonnegative_env(name, default):
    value = float(os.environ.get(name, default))
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{name} must be a finite nonnegative number")
    return value


def reraise(signum):
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)
    return 128 + signum


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


def main():
    try:
        wait_seconds = nonnegative_env('PICSEE_HEAVY_LOCK_WAIT_SECS', '1800')
        grace = nonnegative_env('PICSEE_HEAVY_LOCK_KILL_GRACE_SECS', '10')
    except ValueError as error:
        print(f'[heavy-lock] {error}', file=sys.stderr)
        return 64
    lock = Path(os.environ.get('PICSEE_HEAVY_LOCK', str(Path.home() / '.picsee/locks/heavy.lock')))
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    # close_fds is still true for every other descriptor at the exec boundary.
    os.set_inheritable(fd, True)
    received = []
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda number, frame: received.append(number))
    child = None
    result = 70
    try:
        deadline = time.monotonic() + wait_seconds
        waiting = False
        while not received:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as error:
                if error.errno not in (errno.EAGAIN, errno.EACCES):
                    raise
                if not waiting:
                    print(f'[heavy-lock] waiting for {lock}', file=sys.stderr, flush=True)
                    waiting = True
                if time.monotonic() >= deadline:
                    print(f'[heavy-lock] lock wait timed out after {wait_seconds:g}s', file=sys.stderr)
                    return 75
                time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        if not received:
            try:
                child = subprocess.Popen(sys.argv[1:], env={**os.environ, 'PICSEE_HEAVY_LOCK_HELD': '1'},
                                         pass_fds=(fd,), start_new_session=True)
            except OSError as error:
                print(f'[heavy-lock] {error}', file=sys.stderr)
                return 127
            stopping = None
            while True:
                result = child.poll()
                if received:
                    now = time.monotonic()
                    if stopping is None:
                        stopping = now
                        try:
                            os.killpg(child.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                    if not group_alive(child.pid):
                        break
                    if now - stopping >= grace:
                        try:
                            os.killpg(child.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    if now - stopping >= grace + 5:
                        break  # kernel still protects any live inherited descriptor
                elif result is not None:
                    break
                time.sleep(0.02)
            child.wait()
    finally:
        os.close(fd)  # no unlink, no stale recovery, no explicit LOCK_UN
    if received:
        return reraise(received[0])
    if result < 0:
        return reraise(-result)
    return result


if __name__ == '__main__':
    sys.exit(main())
