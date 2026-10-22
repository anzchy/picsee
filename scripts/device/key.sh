#!/bin/zsh
# usage: key.sh <char> [mods...]   mods: command control option shift
k=$1; shift; m=""
for x in "$@"; do m="$m${m:+, }$x down"; done
# Built separately: inside ${m:+...} the "}" of "{$m}" would end the expansion early.
u=""; [ -n "$m" ] && u=" using {$m}"
osascript -e "tell application \"System Events\" to tell (first process whose name is \"tauri-app\")
  set frontmost to true
  keystroke \"$k\"$u
end tell"
