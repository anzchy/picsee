#!/bin/zsh
# panel-choose.sh RUN_DIR PATH — in an open NSOpenPanel/powerbox: ⌘⇧G, paste PATH (⌘A ⌘V), Return (go), Return (Open/Grant).
# PATH goes through the general pasteboard, never a System Events keystroke, so an input method cannot convert it (#119).
# Only a plain-text pasteboard is touched; it is restored and compared byte for byte on every exit, including INT/TERM/HUP.
# Prints the active input source (read-only) for the run record. Synthetic input: disclose it in the validation record.
[[ $# -eq 2 && -n $2 ]] || { print -u2 'usage: panel-choose.sh RUN_DIR PATH'; exit 2 }
cd "$(git -C "${0:A:h}" rev-parse --show-toplevel)" || exit 1
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
umask 077
run=$1 target=$2 changed=0 restored=0 dir=

restore() {
  (( changed && !restored )) || return 0
  restored=1
  pbcopy < $dir/saved || { print -u2 'FAIL pasteboard restore — pbcopy failed; the pasteboard may still hold the path'; return 1 }
  pbpaste > $dir/after && cmp -s $dir/saved $dir/after ||
    { print -u2 'FAIL pasteboard restore — read-back contents differ from the saved copy'; return 1 }
}

finish() {
  trap '' INT TERM HUP
  local rc=$1
  restore || (( rc )) || rc=1
  [[ -n $dir ]] && rm -f -- $dir/*(N) && rmdir -- $dir
  exit $rc
}
trap 'finish 130' INT
trap 'finish 143' TERM
trap 'finish 129' HUP

key() { scripts/device/kc.sh $run "$@" >/dev/null || { print -u2 -r -- "FAIL panel-choose — key $* failed"; return 1 } }

source_id=$(osascript -l JavaScript -e 'ObjC.import("Carbon"); ObjC.castRefToObject($.TISGetInputSourceProperty($.TISCopyCurrentKeyboardInputSource(), $.kTISPropertyInputSourceID)).js' 2>&1) &&
  print -r -- "input-source: $source_id" || print -r -- "input-source: unknown (${source_id%%$'\n'*})"

# First line: changeCount; then one type per line. The count is read again after the save to catch a copy in between.
types=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var b = $.NSPasteboard.generalPasteboard;
  [b.changeCount].concat(ObjC.deepUnwrap(b.types) || []).join("\n")') ||
  { print -u2 'FAIL pasteboard — cannot read its types; nothing changed'; finish 1 }
count=${types%%$'\n'*} types=${types#$count}
for type in ${(f)types}; do
  case $type in
    public.utf8-plain-text|public.utf16-plain-text|public.utf16-external-plain-text|public.plain-text|NSStringPboardType) ;;
    *) print -u2 -r -- "FAIL pasteboard — holds $type, which a text restore would lose; nothing changed"; finish 1 ;;
  esac
done

dir=$(mktemp -d "${TMPDIR:-/tmp}/panel-choose.XXXXXX") || { print -u2 'FAIL panel-choose — mktemp failed'; finish 1 }
pbpaste > $dir/saved || { print -u2 'FAIL pasteboard — cannot read it; nothing changed'; finish 1 }
[[ $(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSPasteboard.generalPasteboard.changeCount') == $count ]] ||
  { print -u2 'FAIL pasteboard changed while it was being saved; nothing changed, rerun'; finish 1 }
changed=1
print -rn -- $target | pbcopy && pbpaste > $dir/set && print -rn -- $target | cmp -s - $dir/set ||
  { print -u2 'FAIL pasteboard — the path did not read back intact; nothing pasted'; finish 1 }

key 5 command shift && sleep 1.2 &&
  key 0 command && key 9 command && sleep 1.2 &&
  key 36 && sleep 1.5 &&
  key 36 && sleep 2.5
finish $?
