#!/bin/zsh
# panel-choose.sh RUN_DIR PATH — in an open NSOpenPanel/powerbox: ⌘⇧G, type PATH via System Events keystroke,
# Return (go), Return (Open/Grant). Synthetic input: disclose it in the validation record.
cd "$(git -C "${0:A:h}" rev-parse --show-toplevel)" || exit 1
scripts/device/kc.sh "$1" 5 command shift >/dev/null; sleep 1.2
osascript -e "tell application \"System Events\" to keystroke \"$2\""; sleep 1.2
scripts/device/kc.sh "$1" 36 >/dev/null; sleep 1.5
scripts/device/kc.sh "$1" 36 >/dev/null; sleep 2.5
