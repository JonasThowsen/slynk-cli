#!/usr/bin/env bash
# Passes when the jzon in DIR writes floats with no fractional part right,
# as the report asks, and passes jzon's own tests. The tests are the
# pristine ones from $BENCH_SRC_JZON, not the copy in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_JZON:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$BENCH_SRC_JZON/test" "$work/test"
chmod -R u+w "$work/test"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
