#!/usr/bin/env bash
# Passes when the cl-json in DIR encodes nested decoded documents back to
# the JSON they came from and passes cl-json's own tests, apart from the
# six that fail before the bug too. The tests are the pristine ones from
# $BENCH_SRC_CL_JSON, not the copy in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_CL_JSON:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$BENCH_SRC_CL_JSON/t" "$work/t"
chmod -R u+w "$work/t"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
