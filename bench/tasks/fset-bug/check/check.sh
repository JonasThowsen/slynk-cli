#!/usr/bin/env bash
# Passes when the FSet in DIR keeps dotted pairs with unordered cdrs
# apart, as the report asks, and passes FSet's own test suite. The test
# suite is the pristine one from $BENCH_SRC_FSET, not the copy in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_FSET:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$BENCH_SRC_FSET/Code/testing.lisp" "$work/testing.lisp"
chmod u+w "$work/testing.lisp"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
