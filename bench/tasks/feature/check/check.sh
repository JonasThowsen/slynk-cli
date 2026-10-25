#!/usr/bin/env bash
# Passes when the timesheet system in DIR passes the hidden tests: the
# project's original tests, adapted only where the requested feature
# changes them, and tests of holiday pay through the interface the
# prompt specifies. The tests are the copies in check/tests, never the
# ones in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here/tests" "$work/tests"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
