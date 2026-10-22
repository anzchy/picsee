#!/usr/bin/env python3
"""PID-addressed AppleScript inputs, with argv rather than interpolated strings."""
import sys
from device import identity, inside, executable, run_dir, checked

action, directory, *args = sys.argv[1:]
pid, bundle = identity(run_dir(directory))
if not inside(executable(pid), bundle):
    sys.exit('FAIL input — PID executable outside recorded bundle')
mods = args[1:] if action in ('key', 'kc') else []
if any(m not in ('command', 'control', 'option', 'shift') for m in mods):
    sys.exit('FAIL input — invalid modifier')
using = ' using {' + ', '.join(m + ' down' for m in mods) + '}' if mods else ''
if action == 'size':
    if len(args) != 2 or not all(a.isdigit() and int(a) > 0 for a in args):
        sys.exit('usage: size.sh RUN_DIR W H')
    operation = 'set size of window 1 to {item 2 of argv as integer, item 3 of argv as integer}\nget size of window 1'
elif action in ('key', 'kc') and args:
    if action == 'kc' and not args[0].isdigit():
        sys.exit('FAIL input — invalid keycode')
    operation = ('keystroke (item 2 of argv)' if action == 'key' else 'key code (item 2 of argv as integer)') + using
else:
    sys.exit('usage: key.sh|kc.sh RUN_DIR KEY [command|control|option|shift ...]')
script = '''on run argv
 tell application "System Events" to tell (first process whose unix id is (item 1 of argv as integer))
 set frontmost to true
 ''' + operation + '''
 end tell
end run'''
try:
    print(checked(['/usr/bin/osascript', '-e', script, str(pid), *args], timeout=5))
except Exception as e:
    sys.exit('FAIL input — Accessibility/Automation permission or input failed: ' + str(e))
