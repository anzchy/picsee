#!/bin/zsh
set -eu
# usage: shot.sh RUN_DIR NAME -> RUN_DIR/shots/NAME.png (window only, native backing scale)
exec python3 "${0:A:h}/screenshot.py" "$@"
