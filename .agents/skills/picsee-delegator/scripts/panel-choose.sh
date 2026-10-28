#!/bin/zsh
# panel-choose.sh RUN_DIR PATH — in an open NSOpenPanel/powerbox of the run's Picsee: ⌘⇧G, write PATH into the
# Go-to field through accessibility, read it back, Return (go), check the sheet closed, Return (Open/Grant).
# 2026-10-28: the old ⌘A ⌘V paste never reached the Go-to field (run probe-228), so Return confirmed whatever folder
# the panel remembered and every pick landed in the wrong place while the script reported success. Writing the
# AX value bypasses the pasteboard and the input method (#119), and every step is verified; any mismatch fails
# before Open is pressed. Synthetic input: disclose it in the validation record.
[[ $# -eq 2 && -n $2 ]] || { print -u2 'usage: panel-choose.sh RUN_DIR PATH'; exit 2 }
cd "$(git -C "${0:A:h}" rev-parse --show-toplevel)" || exit 1
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
run=$1 target=$2
[[ -r $run/picsee.pid ]] || { print -u2 "FAIL panel-choose — no $run/picsee.pid; launch through scripts/device/launch.sh or record the identity first"; exit 1 }
pid=$(<$run/picsee.pid); pid=${pid//[^0-9]/}

key() { scripts/device/kc.sh $run "$@" >/dev/null || { print -u2 -r -- "FAIL panel-choose — key $* failed"; return 1 } }
# AX on the dialog of this run's process (the sandbox powerbox panel is a window of the app process).
ax() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to tell (first window whose subrole is \"AXDialog\") to $1" 2>/dev/null }
wait_sheets() { local want=$1 t; for t in {1..20}; do [[ $(ax 'return count of sheets') == $want ]] && return 0; sleep 0.25; done; return 1 }

source_id=$(osascript -l JavaScript -e 'ObjC.import("Carbon"); ObjC.castRefToObject($.TISGetInputSourceProperty($.TISCopyCurrentKeyboardInputSource(), $.kTISPropertyInputSourceID)).js' 2>&1) &&
  print -r -- "input-source: $source_id" || print -r -- "input-source: unknown (${source_id%%$'\n'*})"

[[ -n $(ax 'return name') ]] || { print -u2 'FAIL panel-choose — no open panel (AXDialog) on the run process'; exit 1 }
key 5 command shift || exit 1
wait_sheets 1 || { print -u2 'FAIL panel-choose — Go-to sheet did not open'; exit 1 }
quoted=${target//\\/\\\\}; quoted=${quoted//\"/\\\"}
ax "set value of text field 1 of sheet 1 to \"$quoted\"" >/dev/null
got=$(ax 'return value of text field 1 of sheet 1')
[[ $got == $target ]] || { print -u2 -r -- "FAIL panel-choose — Go-to field holds '$got', not the target; nothing chosen"; key 53; exit 1 }
key 36 || exit 1
wait_sheets 0 || { print -u2 -r -- "FAIL panel-choose — Go-to sheet still open after Return (path not found?); nothing chosen"; key 53; exit 1 }
key 36 || exit 1
sleep 1.5
print -r -- "chose: $target"
