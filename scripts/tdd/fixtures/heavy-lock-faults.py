"""Deterministic OS fault injection; all paths supplied by the Node test."""
import importlib.util
import os
from pathlib import Path
import signal
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('launcher', sys.argv[1])
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
mode = sys.argv[2]
sys.argv = ['heavy-lock.py', 'fake-job']
if mode == 'survivors':
    class Child:
        pid = 123456789
        def poll(self):
            os.kill(os.getpid(), signal.SIGTERM)
            return None
        def wait(self):
            return 0
    ticks = [0]
    checks = [0]
    def clock():
        ticks[0] += 1
        return ticks[0]
    def alive(pid):
        checks[0] += 1
        return checks[0] < 100  # baseline also terminates, avoiding a hung RED
    original_popen = launcher.subprocess.Popen
    def popen(command, *args, **kwargs):
        return Child() if command == ['fake-job'] else original_popen(command, *args, **kwargs)
    with patch.object(launcher.subprocess, 'Popen', side_effect=popen), \
         patch.object(launcher.time, 'monotonic', side_effect=clock), \
         patch.object(launcher.time, 'sleep'), \
         patch.object(launcher, 'group_alive', side_effect=alive), \
         patch.object(launcher.os, 'killpg'), \
         patch.object(launcher, 'reraise', return_value=143):
        status = launcher.main()
    assert status == 143, status
    assert Path(os.environ['PICSEE_MDPRO_LOCK']).is_dir(), 'survivors require retained directory'
    assert checks[0] < 20, 'post-KILL wait must be bounded'
elif mode == 'publication':
    original = Path.write_text
    def fail_owner(path, *args, **kwargs):
        if path.name == 'owner':
            raise FileNotFoundError('peer reclaimed before publication')
        return original(path, *args, **kwargs)
    with patch.object(Path, 'write_text', fail_owner):
        assert launcher.main() == 75
    assert Path(os.environ['PICSEE_MDPRO_LOCK']).is_dir()
elif mode == 'heartbeat':
    ticks = [0]
    def clock():
        ticks[0] += 31
        return ticks[0]
    with patch.object(launcher.time, 'monotonic', side_effect=clock), \
         patch.object(launcher.time, 'sleep'):
        assert launcher.main() == 75
elif mode == 'vanished':
    lock = Path(os.environ['PICSEE_MDPRO_LOCK'])
    original_mkdir = launcher.os.mkdir
    raced = [False]
    def mkdir(path, *args, **kwargs):
        if Path(path) == lock and not raced[0]:
            raced[0] = True
            assert not lock.exists(), 'path absent when FileExistsError is handled'
            raise FileExistsError('peer moved lock away after mkdir collision')
        return original_mkdir(path, *args, **kwargs)
    ticks = [0]
    def clock():
        ticks[0] += 0.1
        return ticks[0]
    sys.argv = ['heavy-lock.py', 'true']
    with patch.object(launcher.os, 'mkdir', side_effect=mkdir), \
         patch.object(launcher.time, 'monotonic', side_effect=clock), \
         patch.object(launcher.time, 'sleep'):
        assert launcher.main() == 0, 'vanished path must retry and launch'
    assert raced[0]
elif mode in ('drain-message', 'drain-bound'):
    class Child:
        pid = 123456789
        def poll(self):
            return 3
        def wait(self):
            return 3
    ticks = [0]
    checks = [0]
    def clock():
        ticks[0] += 1
        return ticks[0]
    def alive(pid):
        checks[0] += 1
        return checks[0] < (80 if mode == 'drain-message' else 100)
    signals = []
    original_popen = launcher.subprocess.Popen
    def popen(command, *args, **kwargs):
        return Child() if command == ['fake-job'] else original_popen(command, *args, **kwargs)
    with patch.object(launcher.subprocess, 'Popen', side_effect=popen), \
         patch.object(launcher.time, 'monotonic', side_effect=clock), \
         patch.object(launcher.time, 'sleep'), \
         patch.object(launcher, 'group_alive', side_effect=alive), \
         patch.object(launcher.os, 'killpg', side_effect=lambda pid, sig: signals.append(sig)), \
         patch.object(launcher, 'group_survivors', return_value='123456789 fake-worker'):
        assert launcher.main() == 3, 'preserve direct child status'
    if mode == 'drain-bound':
        assert signals == [signal.SIGTERM, signal.SIGKILL], signals
        assert checks[0] < 30, 'post-KILL wait must be bounded'
        assert Path(os.environ['PICSEE_MDPRO_LOCK']).is_dir(), 'retain shared lock when group survives KILL'
    else:
        assert not Path(os.environ['PICSEE_MDPRO_LOCK']).exists(), 'release when group empties'
