#!/usr/bin/env bash
# Passes when the local-time in DIR decodes the reported leap days right
# and passes local-time's own tests. The tests are the pristine ones
# from $BENCH_SRC_LOCAL_TIME, not the copy in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_LOCAL_TIME:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$BENCH_SRC_LOCAL_TIME/test" "$work/test"
chmod -R u+w "$work/test"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
