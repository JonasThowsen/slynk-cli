#!/usr/bin/env bash
# Passes when the chipz in DIR decompresses stored blocks right however
# its input is cut, and passes chipz's own tests. The tests are the
# pristine tests.lisp from $BENCH_SRC_CHIPZ, not the copy in DIR, run on
# chipz's own sources as test files.
set -euo pipefail

dir=$(cd "$1" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
: "${BENCH_SRC_CHIPZ:?run inside nix develop .#bench}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$BENCH_SRC_CHIPZ/tests.lisp" "$work/"
# The sources whose salza2 deflate output chipz reads without the known
# "Unexpected EOF" of issue #3 (crc32, dstate, stream and tests have it).
mkdir "$work/test-files"
for name in adler32 bzip2 conditions constants decompress gzip inflate-state \
            inflate package stream-fallback types-and-tables zlib; do
  cp "$BENCH_SRC_CHIPZ/$name.lisp" "$work/test-files/$name.uncompressed"
done
chmod -R u+w "$work"
cp "$here/repro.lisp" "$work/"

export XDG_CACHE_HOME="$work/cache"
CHECK_DIR="$dir/" CHECK_WORK="$work/" \
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$here/run.lisp"
