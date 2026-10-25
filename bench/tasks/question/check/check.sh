#!/usr/bin/env bash
# Passes when DIR/ANSWER.md gives the seven values the question asks for.
# Only the values are checked, not the explanations.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$dir/ANSWER.md" ]; then
  echo "FAIL: no ANSWER.md at the top of the project"
  exit 1
fi

ANSWER="$dir/ANSWER.md" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/answer.lisp"
