#!/bin/zsh
set -eu
# usage: build.sh <absolute-run-directory>
exec "${0:A:h}/../heavy-lock.sh" python3 "${0:A:h}/device.py" build "$@"
