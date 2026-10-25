#!/usr/bin/env bash
# Makes the project in DIR: local-time's pinned source with defect.patch
# applied, as one commit.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_LOCAL_TIME:?run inside nix develop .#bench}"

cp -r "$BENCH_SRC_LOCAL_TIME"/. "$dir"/
chmod -R u+w "$dir"
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git apply "$here/defect.patch"
git add -A
git commit -q -m "local-time 1.0.6"
