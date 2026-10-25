#!/usr/bin/env bash
# Makes the project in DIR: FSet's pinned source with upstream.patch and
# defect.patch applied, as one commit.
# The defect is upstream's own bug, reverted: FSet commit 7a2cb81 ("Fix
# for #56: bug comparing tails of dotted lists"),
# https://github.com/slburson/fset/issues/56. defect.patch also takes out
# the regression test for it; the check runs the pristine tests.
# upstream.patch is FSet commit ed5487b, which the pinned source predates:
# without it one test fails under (asdf:test-system :fset), whatever the
# code does.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_FSET:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_FSET"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git apply "$here/upstream.patch"
git apply "$here/defect.patch"
git add -A
git commit -q -m "FSet 2.2.0"
