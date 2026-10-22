#!/bin/zsh
set -eu
# usage: doctor.sh <absolute-run-directory> [--expected-sha SHA] | --fixture JSON

exec python3 "${0:A:h}/device.py" doctor "$@"
