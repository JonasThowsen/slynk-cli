#!/usr/bin/env bash
# Passes when the logsum in DIR passes the project's tests (the copies in
# this directory, not the ones in DIR), gives the expected reports of two
# sample logs (the March of the prompt and a February of another seed,
# made in the check from the project's own sample), and reads March's log
# and makes its report in at most BOUND seconds, the best of three runs.
#
# The bound is relative to the machine the bench runs on, an AMD EPYC
# (Genoa) with 12 cores, with SBCL 2.6.4. There, reading March's log and
# making its report takes 55 s as the project is; 31 s with only the
# counting fixed, and 34 s with only the routes' sort fixed; 8.5 s with
# check/reference.patch, which fixes both. A bound of 18 s is twice the
# reference's time, so a right fix passes on a machine somewhat slower or
# busier than that one, and it is well under the time of either fix
# alone, so fixing one of the two causes does not pass. The prompt asks
# for 15 s.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
bound=18

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here/tests" "$work/tests"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" CHECK_HERE="$here/" CHECK_BOUND="$bound" \
  timeout 800 sbcl --noinform --non-interactive --no-userinit --no-sysinit \
                   --load "$here/run.lisp" \
  || { status=$?; [ "$status" -eq 124 ] && echo "FAIL: the check did not finish in 800 s"; exit "$status"; }
