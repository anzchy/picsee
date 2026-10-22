#!/bin/zsh
set -eu
# usage: build.sh <absolute-run-directory>
# TODO: wrap the build with scripts/heavy-lock.sh once issue #3 lands.
exec python3 "${0:A:h}/device.py" build "$@"
