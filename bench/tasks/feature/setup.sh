#!/usr/bin/env bash
# Makes the project in DIR: the timesheet system in project/, as one
# commit.
set -euo pipefail

dir=$1
here=$(cd "$(dirname "$0")" && pwd)

cp -r "$here/project"/. "$dir"/
cd "$dir"
git init -q
git config user.name bench
git config user.email bench@example.invalid
git add -A
git commit -q -m "timesheet 0.4.0"
