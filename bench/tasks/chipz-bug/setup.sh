#!/usr/bin/env bash
# Makes the project in DIR: chipz's pinned source with defect.patch
# applied, as one commit.
#
# The defect is a real one, reverted: chipz commit f3ce12e ("Properly
# resume uncompressed blocks", Sebastian Melzer, 2023), from
# https://github.com/sharplispers/chipz/pull/10. When the input ran out
# between a stored block's LEN and NLEN, the inflater read LEN again on
# resumption and lost its place in the stream.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_CHIPZ:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_CHIPZ"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git apply "$here/defect.patch"
git add -A
git commit -q -m "chipz 0.8 (2023-06-18)"
