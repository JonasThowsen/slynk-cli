#!/usr/bin/env bash
# Makes the project in DIR: cl-json's pinned source with defect.patch
# applied, as one commit.
#
# The defect is a real one, reverted: cl-json commit 1941150 ("Fix too
# many recursiver errors on deeply nested alist structures", Russ
# Tyndall, 2014), from https://github.com/hankhero/cl-json/pull/5, which
# fixed https://github.com/hankhero/cl-json/issues/1. The guessing
# encoder's handler fell back to encoding a list as an object from inside
# the handler, so every level of nesting added to SBCL's error depth.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_CL_JSON:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_CL_JSON"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git apply "$here/defect.patch"
git add -A
git commit -q -m "cl-json 0.6.0"
