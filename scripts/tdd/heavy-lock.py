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


def group_survivors(pid):
    try:
        listing = subprocess.run(['ps', '-axo', 'pid=,pgid=,stat='],
                                 capture_output=True, text=True, check=True)
        return ', '.join(line.strip() for line in listing.stdout.splitlines()
                         if len(line.split()) >= 3 and line.split()[1] == str(pid)) or f'pgid={pid}'
    except (OSError, subprocess.CalledProcessError):
        return f'pgid={pid} (process listing unavailable)'


def owner_pid(lock):
    try:
        return next((line[4:] for line in (lock / 'owner').read_text().splitlines()
                     if line.startswith('pid=')), '')
    except (FileNotFoundError, NotADirectoryError):
        return ''


def holder_desc(lock):
    try:
        return (lock / 'owner').read_text().replace('\n', ' ')
    except (FileNotFoundError, NotADirectoryError):
        return '(no owner file)'


def pid_alive(pid):
    try:
        number = int(pid)
        if number <= 0:
            return False
        os.kill(number, 0)
        return True
    except (ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True


def acquire_shared(lock, deadline, received, command):
    lock.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    heartbeat = started
    first = True
    while not received:
        try:
            os.mkdir(lock)
        except FileExistsError:
            if not lock.is_dir():
                print(f'[heavy-lock] mdpro lock path is not a directory: {lock}',
                      file=sys.stderr, flush=True)
                return False
        else:
            try:
                (lock / 'owner').write_text(
                    f'pid={os.getpid()}\nstarted={time.strftime("%Y-%m-%dT%H:%M:%S%z")}\n'
                    f'cwd={os.getcwd()}\ncmd={" ".join(command)}\n')
            except OSError as error:
                # A peer may reclaim the ownerless directory before publication.
                # We have no published ownership: never clean it up or launch.
                print(f'[heavy-lock] owner publication failed: {error}; waiting',
                      file=sys.stderr, flush=True)
            else:
                return True
        now = time.monotonic()
        if now >= heartbeat:
            pid = owner_pid(lock)
            if not pid or not pid_alive(pid):
                print(f'[heavy-lock] mdpro lock owner {pid or "(none)"} is dead; '
                      'waiting for an mdpro waiter to reclaim it', file=sys.stderr, flush=True)
            status = 'waiting' if first else f'still waiting ({int(now - started)}s)'
            print(f'[heavy-lock] {status} for {lock}, held by: {holder_desc(lock)}',
                  file=sys.stderr, flush=True)
            first = False
            heartbeat = now + 60
        if now >= deadline:
            print(f'[heavy-lock] lock wait timed out; held by: {holder_desc(lock)}. '
                  f'Manual recovery: first confirm no process from that job is still running '
                  f'(pgrep -f on its cmd); then remove the directory {lock}.',
                  file=sys.stderr, flush=True)
            return False
        wake = min(now + 5, deadline)
        while not received and time.monotonic() < wake:
            time.sleep(min(0.05, max(0, wake - time.monotonic())))
    return False


def release_shared(lock):
    if owner_pid(lock) == str(os.getpid()):
        (lock / 'owner').unlink()
        try:
            lock.rmdir()
        except OSError:
            pass


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
    shared_path = os.environ.get('PICSEE_MDPRO_LOCK', str(Path.home() / '.cache/mdpro-heavy.lock'))
    reverse = os.environ.get('MDPRO_HEAVY_LOCK_HELD') == '1'
    shared = None if shared_path == 'off' or reverse else Path(shared_path)
    if reverse:
        print('[heavy-lock] mdpro parent already holds the shared lock; taking picsee flock only',
              file=sys.stderr, flush=True)
    acquired = False
    retain_shared = False
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
        if not received and shared is not None:
            acquired = acquire_shared(shared, deadline, received, sys.argv[1:])
            if not acquired and not received:
                return 75
        if not received:
            try:
                child_env = {**os.environ, 'PICSEE_HEAVY_LOCK_HELD': '1'}
                if acquired:
                    child_env['MDPRO_HEAVY_LOCK_HELD'] = '1'
                child = subprocess.Popen(sys.argv[1:], env=child_env,
                                         pass_fds=(fd,), start_new_session=True)
            except OSError as error:
                print(f'[heavy-lock] {error}', file=sys.stderr)
                return 127
            stopping = None
            killed_at = None
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
                    if now - stopping >= grace and killed_at is None:
                        killed_at = now
                        try:
                            os.killpg(child.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    if killed_at is not None and now - killed_at >= 5:
                        retain_shared = True
                        print(f'[heavy-lock] WARNING: survivors {group_survivors(child.pid)}; '
                              'leaving shared directory in place', file=sys.stderr, flush=True)
                        break
                elif result is not None and not group_alive(child.pid):
                    break
                time.sleep(0.02)
            if not retain_shared:
                child.wait()
    finally:
        if acquired and not retain_shared:
            release_shared(shared)
        os.close(fd)  # no unlink, no stale recovery, no explicit LOCK_UN
    if received:
        return reraise(received[0])
    if result < 0:
        return reraise(-result)
    return result


if __name__ == '__main__':
    sys.exit(main())
