#!/usr/bin/env bash
# Makes the project in DIR from project/, as one commit.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)

cp -r "$here/project"/. "$dir"/
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git add -A
git commit -q -m "spool 0.6.0"
