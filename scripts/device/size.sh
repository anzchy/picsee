#!/bin/zsh
set -eu
# usage: size.sh RUN_DIR W H
exec python3 "${0:A:h}/input.py" size "$@"
