#!/bin/zsh
# usage: size.sh W H  -> resizes the mdpro window (points), prints the result
osascript -e "tell application \"System Events\" to tell (first process whose name is \"tauri-app\")
  set position of window 1 to {100, 100}
  set size of window 1 to {$1, $2}
  get size of window 1
end tell"
