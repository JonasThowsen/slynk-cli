#!/usr/bin/env bash
# Passes when the cl-ppcre in DIR gives the reported regex the right
# registers and passes cl-ppcre's own test suite. The test suite is the
# pristine one from $BENCH_SRC_CL_PPCRE, not the copy in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_CL_PPCRE:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$BENCH_SRC_CL_PPCRE/test" "$work/test"
chmod -R u+w "$work/test"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
