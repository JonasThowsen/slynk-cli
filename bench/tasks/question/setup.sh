#!/usr/bin/env bash
# Makes the project in DIR: cl-ppcre's pinned source, unchanged, as one
# commit.
set -euo pipefail

dir=$1
: "${BENCH_SRC_CL_PPCRE:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_CL_PPCRE"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git add -A
git commit -q -m "cl-ppcre 2.1.2"
