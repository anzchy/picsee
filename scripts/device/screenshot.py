#!/usr/bin/env python3
import sys
import ctypes
import re
from pathlib import Path
from device import identity, inside, executable, run_dir, checked, HERE

try:
    run = run_dir(sys.argv[1])
    name = sys.argv[2]
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise RuntimeError('screenshot name must be a simple artifact label')
    pid, bundle = identity(run)
    if not inside(executable(pid), bundle):
        raise RuntimeError('PID executable outside recorded bundle')
    # Preflight does not request or change permission; no black/empty image is saved.
    cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
    cg.CGPreflightScreenCaptureAccess.restype = ctypes.c_bool
    if not cg.CGPreflightScreenCaptureAccess():
        raise RuntimeError('Screen Recording permission missing for the terminal/host running this command')
    rows = checked(['/usr/bin/osascript', '-l', 'JavaScript', HERE / 'winid.js', str(pid)]).splitlines()
    if len(rows) != 1:
        raise RuntimeError('expected exactly one on-screen layer-0 window for recorded PID')
    wid, _, _, width, height, *_ = rows[0].split('\t')
    folder = run / 'shots'
    folder.mkdir(exist_ok=True)
    out = folder / (name + '.png')
    checked(['/usr/sbin/screencapture', '-x', '-o', '-l' + wid, out])
    if not out.exists() or out.stat().st_size < 100:
        raise RuntimeError('Screen Recording capture failed: empty image')
    dimensions = checked(['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', out])
    print(f'PASS screenshot window={wid} points={width}x{height} file={out}\n{dimensions}')
except Exception as e:
    sys.exit('FAIL screenshot — ' + str(e))
