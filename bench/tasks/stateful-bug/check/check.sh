#!/usr/bin/env bash
# Passes when the trove in DIR gives the reported sequence on the full
# sample archive the right answers, keeps every article right through a
# second correction, withdrawal and import on the same index, agrees with
# a model on random sequences of changes to small indexes, and passes the
# project's tests. The tests are the copies in check/tests/, not the ones
# in DIR. The check builds the full sample archive once, as the report
# does, which takes about a minute.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here/tests" "$work/tests"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  timeout 600 sbcl --noinform --non-interactive --no-userinit --no-sysinit \
                   --load "$here/run.lisp" \
  || { status=$?; [ "$status" -eq 124 ] && echo "FAIL: the check did not finish in 600 s"; exit "$status"; }
