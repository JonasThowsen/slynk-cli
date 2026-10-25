#!/usr/bin/env bash
# Passes when the spool in DIR runs the reported sequence right (the
# second reminder runs, the cancelled one never does), runs many random
# sequences of submits and cancels between job starts in the order a
# model of the queue gives, and passes the project's tests. The tests are
# the copies in this directory, not the ones in DIR. The jobs of the
# sequences are gates the check opens, so the outcome does not depend on
# timing; a job that never starts fails the check after ten seconds.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here/tests" "$work/tests"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
# A worker or a client that hangs for good must not hang the check.
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  timeout 600 sbcl --noinform --non-interactive --no-userinit --no-sysinit \
                   --load "$here/run.lisp" \
  || { status=$?; [ "$status" -eq 124 ] && echo "FAIL: the check did not finish in 600 s"; exit "$status"; }
