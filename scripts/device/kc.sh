#!/bin/zsh
# usage: kc.sh <keycode> [mods...]  e.g. 126=up 125=down 48=tab 36=return 51=delete
k=$1; shift; m=""
for x in "$@"; do m="$m${m:+, }$x down"; done
# Built separately: inside ${m:+...} the "}" of "{$m}" would end the expansion early.
u=""; [ -n "$m" ] && u=" using {$m}"
osascript -e "tell application \"System Events\" to tell (first process whose name is \"tauri-app\")
  set frontmost to true
  key code $k$u
end tell"
