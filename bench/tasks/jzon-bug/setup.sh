#!/usr/bin/env bash
# Makes the project in DIR: jzon's pinned source with defect.patch
# applied, as one commit.
# The defect is upstream's own bug, reverted: jzon commit be8542e ("Fix
# printing numbers without fractional parts"),
# https://github.com/Zulu-Inuoe/jzon/issues/45. The patch also takes out
# the regression tests for it (commit 5ca78c8); the check runs the
# pristine tests.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_JZON:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_JZON"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git apply "$here/defect.patch"
git add -A
git commit -q -m "jzon 1.1.4"
