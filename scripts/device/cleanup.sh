#!/bin/zsh
set -eu
# usage: cleanup.sh <absolute-run-directory>

exec python3 "${0:A:h}/device.py" cleanup "$@"
