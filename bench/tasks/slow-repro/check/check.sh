#!/usr/bin/env bash
# Passes when the tally in DIR gives the reported query sequence the right
# answers, keeps its answers through related sequences (other stores, a
# one-day period, SKU totals and the store ranking), and passes the
# project's tests. The tests are the copies in this directory, not the
# ones in DIR. The check builds the full sample database once, as the
# report does, which takes about half a minute.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$here/repro.lisp" "$here/tests.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
# A query over a list made circular would never return.
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  timeout 600 sbcl --noinform --non-interactive --no-userinit --no-sysinit \
                   --load "$here/run.lisp" \
  || { status=$?; [ "$status" -eq 124 ] && echo "FAIL: the check did not finish in 600 s"; exit "$status"; }
