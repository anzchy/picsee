#!/bin/zsh
set -eu
# usage: key.sh RUN_DIR KEY [command control option shift]
exec python3 "${0:A:h}/input.py" key "$@"
