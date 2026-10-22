#!/bin/zsh
set -eu
# usage: launch.sh <absolute-run-directory>

exec python3 "${0:A:h}/device.py" launch "$@"
