#!/usr/bin/env python3
"""Local device-run orchestration. Evidence stays outside the checkout."""
import argparse
import ctypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

def command(argv, timeout=30):
    return subprocess.run([str(a) for a in argv], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)

def checked(argv, timeout=30):
    r = command(argv, timeout)
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip() or str(argv))
    return r.stdout.strip()

def executable(pid):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    buf = ctypes.create_string_buffer(4096)
    if lib.proc_pidpath(int(pid), buf, len(buf)) <= 0:
        return None
    return Path(os.fsdecode(buf.value)).resolve()

def identity(run):
    pid = int((run / 'picsee.pid').read_text().strip())
    if pid <= 1:
        raise RuntimeError('invalid recorded PID')
    app = Path((run / 'bundle.path').read_text().strip()).resolve()
    return pid, app

def inside(exe, app):
    return exe is not None and exe.is_relative_to(app / 'Contents' / 'MacOS')

def running():
    r = command(['/usr/bin/pgrep', '-x', 'Picsee'])
    return [int(p) for p in r.stdout.split()]

def windows(pid):
    script = '''on run argv
    tell application "System Events" to tell (first process whose unix id is (item 1 of argv as integer))
      set resultText to ""
      repeat with w in windows
        set s to size of w
        set resultText to resultText & name of w & tab & (item 1 of s) & tab & (item 2 of s) & linefeed
      end repeat
      return resultText
    end tell
    end run'''
    output = checked(['/usr/bin/osascript', '-e', script, str(pid)], timeout=5)
    return [dict(zip(['title', 'width', 'height'], line.split('\t'))) for line in output.splitlines()]

def machine():
    # Only non-sensitive model/display facts; no serial number or user information.
    scale = checked(['/usr/bin/osascript', '-l', 'JavaScript', '-e',
        "ObjC.import('AppKit'); Number($.NSScreen.mainScreen.backingScaleFactor)"])
    return dict(model=checked(['/usr/sbin/sysctl', '-n', 'hw.model']),
                chip=checked(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']),
                memory=checked(['/usr/sbin/sysctl', '-n', 'hw.memsize']),
                macOS=checked(['/usr/bin/sw_vers', '-productVersion']), scale=float(scale))

def logs(run, pid):
    start = (run / 'start.txt').read_text().strip()
    r = command(['/usr/bin/log', 'show', '--start', start, '--style', 'compact', '--info',
                 '--predicate', f'subsystem == "io.github.anzchy.picsee" AND processID == {pid}'])
    if r.returncode:
        raise RuntimeError(r.stderr.strip())
    (run / 'app.log').write_text(r.stdout)
    return r.stdout

def save(run, name, data):
    (run / name).write_text(json.dumps(data, indent=2) + '\n')

def run_dir(value):
    run = Path(value).expanduser().resolve()
    if run == ROOT or run.is_relative_to(ROOT):
        raise RuntimeError('run evidence must be outside the worktree')
    run.mkdir(parents=True, exist_ok=True)
    return run

def build(run):
    if running():
        raise RuntimeError('another Picsee is running; ask its owner to quit it')
    if checked(['git', '-C', ROOT, 'status', '--porcelain', '--untracked-files=no']):
        raise RuntimeError('commit tracked changes before building a proof image')
    developer = os.environ.get('PICSEE_XCODE', '/Applications/Xcode-26.6.app') + '/Contents/Developer'
    os.environ['DEVELOPER_DIR'] = developer
    version = checked(['/usr/bin/xcodebuild', '-version'])
    if 'Build version 17F113' not in version:
        raise RuntimeError('requires Xcode 26.6 build 17F113')
    sha = checked(['git', '-C', ROOT, 'rev-parse', '--short', 'HEAD'])
    full = checked(['git', '-C', ROOT, 'rev-parse', 'HEAD'])
    dd = ROOT / '.build' / ('device-' + run.name)
    with (run / 'build.log').open('w') as output:
        for argv in [['xcodegen', 'generate'], ['/usr/bin/xcodebuild', 'build', '-scheme', 'Picsee',
                     '-configuration', 'Debug', '-destination', 'platform=macOS', '-derivedDataPath', str(dd)]]:
            r = subprocess.run(argv, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
            if r.returncode:
                raise RuntimeError(f'build failed; see {run / "build.log"}')
    app = dd / 'Build/Products/Debug/Picsee.app'
    (run / 'bundle.path').write_text(str(app) + '\n')
    save(run, 'build.json', dict(sha=sha, fullSHA=full, machine=machine(), configuration='Debug', xcode=version))
    print(f'PASS build bundle={app} git={sha}')

def launch(run):
    if running():
        raise RuntimeError('another Picsee is running; ask its owner to quit it')
    app = Path((run / 'bundle.path').read_text().strip()).resolve()
    sha = json.loads((run / 'build.json').read_text())['sha']
    (run / 'start.txt').write_text(datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    checked(['/usr/bin/open', '-n', app])
    deadline = time.monotonic() + 30
    missing = 'process'
    while time.monotonic() < deadline:
        candidates = [p for p in running() if executable(p) == app / 'Contents/MacOS/Picsee']
        if len(candidates) == 1:
            pid = candidates[0]
            (run / 'picsee.pid').write_text(str(pid) + '\n')
            ws = windows(pid)  # Authorization failures stop immediately; never dismiss prompts.
            visible = checked(['/usr/bin/osascript', '-l', 'JavaScript', HERE / 'winid.js', str(pid)])
            log = logs(run, pid)
            if len(ws) == 1 and ws[0]['title'] == 'Picsee' and visible and f'Picsee launch git={sha}' in log:
                save(run, 'ready.json', ws)
                print(f'PASS ready pid={pid} title=Picsee git={sha}')
                return
            missing = 'visible Picsee window or public launch SHA log'
        time.sleep(0.5)
    raise RuntimeError('ready timeout after 30 s: missing ' + missing)

def collect(run, expected):
    pid, app = identity(run)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    signing = command(['/usr/bin/codesign', '-dv', '--verbose=2', app])
    ent = command(['/usr/bin/codesign', '-d', '--entitlements', '-', app])
    try:
        sandbox = plistlib.loads(ent.stdout.encode()).get('com.apple.security.app-sandbox') is True
    except Exception:
        sandbox = False
    ws, log = [], ''
    errors = {}
    try:
        ws = windows(pid)
    except Exception as e:
        errors['window'] = str(e)
    try:
        log = logs(run, pid)
    except Exception as e:
        errors['launch-log'] = str(e)
    fixture_files = [p for p in (run / 'fixtures').rglob('*') if p.is_file()]
    manifest = run / 'fixtures.sha256.json'
    fixtures = not fixture_files  # Skeleton proof has no image fixtures.
    if manifest.exists():
        hashes = json.loads(manifest.read_text())
        fixtures = {str(p.relative_to(run / 'fixtures')): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in fixture_files} == hashes
    stamp = (app / 'Contents/Info.plist').stat().st_mtime
    recorded = json.loads((run / 'build.json').read_text())
    try:
        current_machine = machine()
        machine_matches = current_machine == recorded['machine']
    except Exception as e:
        current_machine, machine_matches = str(e), False
    data = dict(expectedSHA=expected, sha=info.get('PicseeGitSHA'), bundleID=info.get('CFBundleIdentifier'),
        team=(re.search(r'TeamIdentifier=(\S+)', signing.stderr) or [None, None])[1],
        signatureValid=command(['/usr/bin/codesign', '--verify', '--deep', '--strict', app]).returncode == 0,
        sandbox=sandbox, processMatches=executable(pid) == app / 'Contents/MacOS/Picsee',
        fresh=all(p.stat().st_mtime <= stamp for folder in ['App', 'Packages/PicseeKit/Sources']
                  for p in (ROOT / folder).rglob('*.swift')),
        alone=running() == [pid], windows=ws, log=log, machineMatches=machine_matches,
        fixturesIntact=fixtures, machine=current_machine, errors=errors)
    save(run, 'doctor-input.json', data)
    return data

def verdicts(data):
    checks = [
        ('build-sha', data.get('sha') == data.get('expectedSHA') and bool(data.get('expectedSHA')), 'PicseeGitSHA differs from expected SHA'),
        ('bundle-id', data.get('bundleID') == 'io.github.anzchy.picsee', 'wrong bundle identifier'),
        ('signature-team', data.get('team') == 'GRT84NAK4T', 'wrong signing team'),
        ('signature-valid', data.get('signatureValid') is True, 'codesign verification failed'),
        ('sandbox', data.get('sandbox') is True, 'App Sandbox entitlement missing'),
        ('process-bundle', data.get('processMatches') is True, 'PID executable differs from recorded bundle'),
        ('fresh-sources', data.get('fresh') is True, 'Swift source newer than bundle'),
        ('single-instance', data.get('alone') is True, 'recorded PID is not the only Picsee instance'),
        ('window', len(data.get('windows', [])) == 1 and data['windows'][0].get('title') == 'Picsee', 'expected one window titled Picsee'),
        ('launch-log', bool(re.search(r'Picsee launch git=' + re.escape(str(data.get('expectedSHA'))) + r'(?![\w-])', data.get('log', ''))), 'public SHA launch log missing'),
        ('machine', data.get('machineMatches') is True, 'machine/display differs from build record'),
        ('fixtures', data.get('fixturesIntact') is True, 'fixture hashes missing or changed')]
    lines = [('PASS ' + name if ok else 'FAIL ' + name + ' — ' + data.get('errors', {}).get(name, why))
             for name, ok, why in checks]
    return lines, all(ok for _, ok, _ in checks)

def cleanup(run):
    pid, app = identity(run)
    exe = executable(pid)
    if exe is None:
        print(f'PASS cleanup pid={pid} already exited; evidence retained at {run}')
        return
    if not inside(exe, app):
        raise RuntimeError(f'PID {pid} executable outside recorded bundle; refusing signal')
    # Check immediately before signal; never search or kill by name.
    if executable(pid) != exe:
        raise RuntimeError('PID identity changed; refusing signal')
    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        if executable(pid) != exe:
            print(f'PASS cleanup terminated pid={pid}; evidence retained at {run}')
            return
        time.sleep(0.1)
    raise RuntimeError(f'PID {pid} did not exit after SIGTERM; no escalation sent')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['build', 'launch', 'doctor', 'cleanup'])
    parser.add_argument('run', nargs='?')
    parser.add_argument('--expected-sha')
    parser.add_argument('--fixture', help='offline doctor input only; never device proof')
    args = parser.parse_args()
    try:
        if args.action == 'doctor':
            run = None if args.fixture else run_dir(args.run)
            data = json.loads(Path(args.fixture).read_text()) if args.fixture else collect(run, args.expected_sha or checked(['git', '-C', ROOT, 'rev-parse', '--short', 'HEAD']))
            lines, passed = verdicts(data)
            output = '\n'.join(lines) + '\n'
            print(output, end='')
            if run:
                (run / 'doctor.txt').write_text(output)
            return 0 if passed else 1
        globals()[args.action](run_dir(args.run))
        return 0
    except Exception as e:
        print(f'FAIL {args.action} — {e}')
        return 1

if __name__ == '__main__':
    sys.exit(main())
