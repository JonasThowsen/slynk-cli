#!/usr/bin/env bash
# Passes when the depot in DIR locks the reported webshop with the
# releases it should, locks other projects of the registry that the
# defect changed, leaves the registry as it was after resolving, agrees
# with a plain search on random registries, and passes the project's
# tests. The tests are the copies in check/tests/, and the registry and
# the examples are the task's own copies, not the ones in DIR.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here/tests" "$work/tests"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" CHECK_DATA="$here/../project/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
