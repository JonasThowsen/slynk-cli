#!/usr/bin/env bash
# Check each behaviour of lisp (README.md) against fixture projects of its
# own.  The main image's records go to a state directory of the test's; the
# projects that check where the state goes by default are fresh directories.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/slynk-cli-test.XXXXXX")"
export SLYNK_CLI_STATE="$work/state"
lisp="$here/bin/lisp"
project="$work/project"
mkdir -p "$project"
# Stop every image a check started, wherever its state is.
stop_all() {
  for state in "$work/state" "$work"/*/.slynk-cli; do
    [ -d "$state" ] && SLYNK_CLI_STATE="$state" "$lisp" stop >/dev/null 2>&1 || true
  done
}
trap 'stop_all; rm -rf "$work"' EXIT

out="$work/answer"
code=0
# Run lisp with ARGS; its answer is in $out and its exit code in $code.
run() {
  code=0
  "$lisp" "$@" >"$out" 2>&1 </dev/null || code=$?
}
fail() {
  echo "--- lisp $*" >&2
  cat "$out" >&2
  exit 1
}
# expect CODE PATTERN...: the last answer exited CODE and has each pattern.
expect() {
  local expected="$1"
  shift
  [ "$code" -eq "$expected" ] || fail "exited $code, not $expected"
  for pattern in "$@"; do
    grep -qE -- "$pattern" "$out" || fail "has no line matching: $pattern"
  done
}
refuse() {
  for pattern in "$@"; do
    if grep -qE -- "$pattern" "$out"; then fail "has a line matching: $pattern"; fi
  done
}
# The number after the first match of PREFIX in the last answer.
number_after() {
  grep -oE -- "$1[0-9]+" "$out" | head -1 | grep -oE '[0-9]+$'
}

cd "$project"
cat >fixture.asd <<'EOF'
(defsystem "fixture" :components ((:file "fixture")))
EOF
cat >fixture.lisp <<'EOF'
;;;; æøå before the forms: positions count characters, not bytes.
(defpackage #:lisp-fixture (:use #:cl))
(in-package #:lisp-fixture)

(defun inner (x)
  (let ((y (* x 2)))
    (if (> y 1)
        (error "too big: ~a" y)
        y)))

(defun outer (x)
  (1+ (inner x)))

(defstruct point x y)

(defun choose (x)
  (restart-case (error "pick for ~a" x)
    (use-value (value) value)))

(eval-when (:compile-toplevel)
  (defparameter cl-user::*fixture-policy* (sb-ext:restrict-compiler-policy)))
EOF
cat >warns.lisp <<'EOF'
(in-package #:lisp-fixture)

(defun warns ()
  (let ((unused 1))
    nil))
EOF

# A system the root has too, elsewhere; a library outside the root; and
# systems in a directory with a dot and behind a symbolic link.
mkdir -p "$work/elsewhere" "$project/lib/dup" "$project/.hidden" "$work/linked"
for where in elsewhere project/lib/dup; do
  echo '(defsystem "dup" :components ((:file "dup")))' >"$work/$where/dup.asd"
  printf '(defpackage #:dup (:use #:cl))\n(in-package #:dup)\n(defun where () :%s)\n' \
    "${where%%/*}" >"$work/$where/dup.lisp"
done
echo '(defsystem "outside" :components ((:file "outside")))' >"$work/elsewhere/outside.asd"
cat >"$work/elsewhere/outside.lisp" <<'EOF'
(eval-when (:compile-toplevel)
  (defparameter cl-user::*outside-policy* (sb-ext:restrict-compiler-policy)))
EOF
echo '(defsystem "hidden")' >"$project/.hidden/hidden.asd"
echo '(defsystem "linked")' >"$work/linked/linked.asd"
ln -s "$work/linked" "$project/linked"
export CL_SOURCE_REGISTRY="$work/elsewhere/:${CL_SOURCE_REGISTRY:-}"

# No image: a command says to start one.
run eval '(+ 1 2)'
expect 1 'no image is running; start one with lisp start'
run frame one 0
expect 2 'needs a number'

# A system that does not load is reported, and the image stays up.
run start no-such-system
expect 1 'loading no-such-system failed' 'It stays up'
run status
expect 0 'no evaluation is running or paused'
run stop
expect 0 'stopped the image'

# Two .asd files at the top: no system, and start names them.
cp fixture.asd other.asd
run start
expect 0 'no system loaded' 'The root has fixture, other: '
run stop
expect 0 'stopped the image'
rm other.asd

# The system of the one .asd file at the top of the root.
run start
expect 0 'fixture loaded'
[ "$(cat "$SLYNK_CLI_STATE/.gitignore")" = '*' ] || fail "the state directory does not ignore itself"

# The project's files compile with (debug 3), into the image's directory; a
# library outside the root keeps its policy, also when the image compiles it.
run eval 'cl-user::*fixture-policy*'
expect 0 '\(\(DEBUG \. 3\)\)'
run eval "(namestring (asdf:apply-output-translations \"$project/fixture.lisp\"))"
expect 0 "$SLYNK_CLI_STATE/fasl/"
run eval '(progn (asdf:load-system "outside") cl-user::*outside-policy*)'
expect 0 '= NIL$'
run eval '(sb-ext:restrict-compiler-policy)'
expect 0 '= NIL$'

# The root's systems win over others of the same name; a directory with a
# dot and one through a symbolic link are not the root's.
run eval '(progn (asdf:load-system "dup") (funcall (read-from-string "dup::where")))'
expect 0 '= :PROJECT$'
run eval '(list (asdf:find-system "hidden" nil) (asdf:find-system "linked" nil))'
expect 0 '= \(NIL NIL\)$'

# Values with handles, output, * and the current package.
run eval '(progn (print :hi) (values 6 "seven"))'
expect 0 'evaluation [0-9]+ finished' '#@[0-9]+ = 6' '#@[0-9]+ = "seven"' '^output:' ':HI'
seven="$(number_after '#@')"
run eval '(list * (length #@'"$((seven + 1))"'))'
expect 0 '= \(6 5\)'
run eval '(in-package :lisp-fixture)'
expect 0 'PACKAGE "LISP-FIXTURE"'
run eval '(outer 0)'
expect 0 '= 1$'
# The forms read from standard input, in-package among them.
code=0
"$lisp" eval - >"$out" 2>&1 <<'EOF' || code=$?
(in-package :cl-user)
(list (package-name *package*) (lisp-fixture::outer 0))
EOF
expect 0 '= \("COMMON-LISP-USER" 1\)'
run eval '(in-package :lisp-fixture)'
expect 0 'PACKAGE "LISP-FIXTURE"'

# Compiling reports warnings with their lines.
run compile warns.lisp
expect 1 'warns.lisp:4  style warning: The variable UNUSED is defined but never used'
run compile warns.lisp:5
expect 1 'warns.lisp:4  style warning' 'the form at .*warns.lisp:3'

# An error pauses the evaluation.
run eval '(outer 1)'
expect 1 'evaluation [0-9]+ is paused in the debugger' 'SIMPLE-ERROR: too big: 2' '^restarts:' \
  'abort +Abort evaluation' '^ +0  \(INNER 1\)  fixture.lisp:8$' '^ +1  \(OUTER 1\)  fixture.lisp:12$'
refuse 'SLYNK-CLI::'
paused="$(number_after 'evaluation ')"

# Its frames: locals with handles, and forms evaluated in them.
run frame "$paused" 0
expect 0 'x  #@[0-9]+ = 1' 'y  #@[0-9]+ = 2' 'restartable: yes'
run eval --in "$paused:0" '(* y 10)'
expect 0 'still paused' '= 20'
run eval --in "$paused:0" '(car y)'
expect 1 'In frame 0 of evaluation' 'is still paused'
run backtrace "$paused" --from 1 --count 1
expect 0 '^ +1  \(OUTER 1\)'
refuse '^ +0  '

# Fixed in the file, the form compiled from a line inside it, the frame
# restarted: the evaluation finishes with the fixed function's value.
sed -i 's/(error "too big: ~a" y)/(- y 1)/' fixture.lisp
run compile fixture.lisp:8
expect 0 'compiled the form at fixture.lisp:5'
run definition inner
expect 0 '\(DEFUN INNER\)  fixture.lisp:5$'
run restart-frame "$paused" 0
expect 0 'evaluation [0-9]+ finished' '= 2$'

# A restart given a value.
run eval '(choose 1)'
expect 1 'pick for 1'
id="$(number_after 'evaluation ')"
restart="$(grep -oE '^ +[0-9]+  use-value' "$out" | grep -oE '[0-9]+')"
run restart "$id" "$restart" '(* 6 7)'
expect 0 'finished' '= 42$'

# A value returned from a frame.
run eval '(+ 1 (choose 2))'
id="$(number_after 'evaluation ')"
frame="$(grep -oE '^ +[0-9]+  \(CHOOSE 2\)' "$out" | grep -oE '[0-9]+' | head -1)"
run return "$id" "$frame" 7
expect 0 'finished' '= 8$'

# A frame compiled without (debug 2), such as SBCL's EVAL, cannot return:
# return says so, and the evaluation stays paused.
run eval '(+ 1 (choose 2))'
id="$(number_after 'evaluation ')"
frame="$(grep -oE '^ +[0-9]+  \(SB-INT:SIMPLE-EVAL-IN-LEXENV' "$out" | grep -oE '[0-9]+' | head -1)"
run return "$id" "$frame" 7
expect 1 "Frame $frame cannot return"
run status
expect 0 "evaluation $id is paused"
run abort "$id"
expect 0 "evaluation $id was aborted"

# A break pauses too, and continues.
run eval '(progn (break "look") :went-on)'
expect 1 'SIMPLE-CONDITION: look' 'continue +Return from BREAK'
id="$(number_after 'evaluation ')"
run restart "$id" 0
expect 0 '= :WENT-ON'

# Finding: a definition in the project and in SBCL, the callers of one.
run definition string-trim
expect 0 'src/code/string.lisp:[0-9]+$'
run xref calls inner
expect 0 '^OUTER  fixture.lisp:1[0-9]$'

# Inspecting, and a handle in a later form.
run inspect '(make-point :x 1 :y (list 2 3))'
expect 0 'X: #@[0-9]+ = 1' 'Y: #@[0-9]+ = \(2 3\)'
point="$(number_after '#@')"
run eval "(point-y #@$point)"
expect 0 '= \(2 3\)'

# Ended past its own restart, by SBCL's restart that aborts the thread, an
# evaluation is aborted, not left running.
run eval '(error "ended")'
id="$(number_after 'evaluation ')"
restart="$(grep -oE '^ +[0-9]+  abort +abort thread' "$out" | grep -oE '^ +[0-9]+' | tr -d ' ')"
run restart "$id" "$restart"
expect 1 "evaluation $id was aborted when its thread was ended"
run status
expect 0 'no evaluation is running or paused'

# Waiting: an evaluation still running, while another is paused.
run eval '(error "left paused")'
left="$(number_after 'evaluation ')"
run eval '(progn (sleep 3) :slept)' --wait 1
expect 1 'is still running' "paused, and maybe holding what it waits for: .*evaluation $left"
id="$(number_after 'evaluation ')"
run status
expect 0 "evaluation $id is running" "evaluation $left is paused"
run wait "$id"
expect 0 '= :SLEPT'

# A form in a frame that does not end leaves the evaluation busy; abort
# still ends it.
run eval '(error "busy")'
id="$(number_after 'evaluation ')"
run eval --in "$id:0" '(loop (sleep 0.1))' --wait 1
expect 1 "still running in frame 0 of evaluation $id"
run abort "$id"
expect 0 "evaluation $id was aborted"
run eval --in "$id:0" '1'
expect 1 "Evaluation $id is not paused; it was aborted"
refuse 'still paused'

# Aborting a running and a paused evaluation.
run eval '(sleep 100)' --wait 1
id="$(number_after 'evaluation ')"
run abort "$id"
expect 0 'was aborted'
run abort "$left"
expect 0 'was aborted'

# The limit counts the time running, not the time paused.
run eval '(sleep 100)' --wait 6 --limit 2
expect 1 'was aborted after running 2 s, its limit'
run eval '(progn (break) (sleep 1.5) :done)' --limit 2
id="$(number_after 'evaluation ')"
sleep 3
run restart "$id" 0
expect 0 '= :DONE'

# Without :main, the main thread serves eval --main itself.
run eval --main '(list (eq sb-thread:*current-thread* (sb-thread:main-thread)) (progn (print :on-main) 1))'
expect 0 '= \(T 1\)$' ':ON-MAIN'

# An error in a thread lisp did not start pauses it as an evaluation of its
# own; abort is refused there, and its own restart goes on.
run eval '(progn (sb-thread:make-thread (lambda () (error "in a worker")) :name "worker") :started)'
expect 0 ':STARTED'
sleep 1
run status
expect 0 'is paused in the debugger: an error in thread "worker"'
worker="$(grep -oE 'evaluation [0-9]+ is paused' "$out" | grep -oE '[0-9]+')"
run wait "$worker"
expect 1 'It is an error in thread "worker", which lisp did not start' 'in a worker'
refuse "abort $worker"
run abort "$worker"
expect 1 'which lisp did not start; abort would unwind'
run wait "$worker"
restart="$(grep -oE '^ +[0-9]+  abort +abort thread' "$out" | grep -oE '^ +[0-9]+' | tr -d ' ')"
run restart "$worker" "$restart"
expect 0 "evaluation $worker went on"

# Errors nested past SBCL's maximum depth, as a handler that signals
# again: the evaluation pauses as any other, and its frames answer.
run eval '(labels ((nest (n) (handler-bind ((error (lambda (c) (declare (ignore c)) (when (> n 0) (nest (1- n)))))) (error "at ~d" n)))) (nest 12))'
expect 1 'is paused in the debugger' 'Maximum error nesting depth exceeded'
id="$(number_after 'evaluation ')"
run frame "$id" 0
expect 0 "frame 0 of evaluation $id" 'n  #@[0-9]+ = 1'
run abort "$id"
expect 0 "evaluation $id was aborted"

# Long output and long values are cut.
run eval '(loop repeat 1000 do (print (make-string 30 :initial-element #\x)))'
expect 0 'the last [0-9,]+ of 34,000 characters \(1,000 lines\); all of it in .*output/[0-9]+\.txt'
file="$(grep -oE '[^ ]*output/[0-9]+\.txt' "$out")"
[ "$(grep -c xxxx "$file")" -eq 1000 ] || fail "the output file does not have all 1000 lines"
[ "$(grep -c xxxx "$out")" -le 200 ] || fail "the answer shows more than 200 lines"
run eval '(make-string 4998 :initial-element #\a)'
expect 0 '\(3,000 characters left out\)'

# An image that ends while it answers, as one whose heap runs out does.
run eval '(sb-ext:exit :abort t)'
expect 1 'the image stopped while answering' 'image.log'
refuse 'Backtrace' 'SIMPLE-STREAM-ERROR'
run eval '(+ 1 2)'
expect 1 'no image is running'

# The root: the top of the git work tree, with the state there by default.
unset SLYNK_CLI_STATE
mkdir -p "$work/git/sub"
git -C "$work/git" init -q
cp "$project/fixture.asd" "$project/fixture.lisp" "$work/git/"
cd "$work/git/sub"
run start
expect 0 'fixture loaded'
[ -f "$work/git/.slynk-cli/pid" ] || fail "the state is not at the top of the git work tree"
run stop
expect 0 'stopped'

# The root: where .slynk-cli.sexp is, which configures the image.
mkdir -p "$work/conf/a/b"
cat >"$work/conf/.slynk-cli.sexp" <<'EOF'
(:system "dup"
 :lisp ("sbcl" "--dynamic-space-size" "700MB" "--noinform")
 :init ("init.lisp"))
EOF
echo '(defparameter cl-user::*init-loaded* t)' >"$work/conf/init.lisp"
cp "$work/elsewhere/dup.asd" "$work/elsewhere/dup.lisp" "$work/conf/"
cd "$work/conf/a/b"
run start
expect 0 'dup loaded'
[ -f "$work/conf/.slynk-cli/pid" ] || fail "the state is not where .slynk-cli.sexp is"
run eval '(list cl-user::*init-loaded* (floor (sb-ext:dynamic-space-size) (* 1024 1024)))'
expect 0 '= \(T 700\)$'
run stop
expect 0 'stopped'
echo '(:system "dup" :colour "red")' >"$work/conf/.slynk-cli.sexp"
run start
expect 1 'must be a property list of :system, :lisp, :init, :main and :main-thread-dispatcher'
# Read without evaluation: #. is refused, and its form never runs.
echo "(:system #.(progn (with-open-file (out \"$work/evaluated\" :direction :output) t) \"dup\"))" \
  >"$work/conf/.slynk-cli.sexp"
run start
expect 1 'cannot be read'
[ ! -e "$work/evaluated" ] || fail "reading .slynk-cli.sexp evaluated #."

# :main runs the project's function in the main thread, and
# :main-thread-dispatcher brings eval --main there.
mkdir -p "$work/loop"
cat >"$work/loop/workloop.asd" <<'LISP'
(defsystem "workloop" :components ((:file "workloop")))
LISP
cat >"$work/loop/workloop.lisp" <<'LISP'
(defpackage #:workloop (:use #:cl) (:export #:main #:run-in-main-thread))
(in-package #:workloop)

(defvar *work* '())
(defvar *lock* (sb-thread:make-mutex :name "work"))
(defvar *more* (sb-thread:make-waitqueue :name "more work"))

(defun run-in-main-thread (thunk)
  "Have the main loop run THUNK."
  (sb-thread:with-mutex (*lock*)
    (setf *work* (append *work* (list thunk)))
    (sb-thread:condition-notify *more*)))

(defun next-work ()
  (sb-thread:with-mutex (*lock*)
    (loop until *work* do (sb-thread:condition-wait *more* *lock*))
    (pop *work*)))

(defun callback (count)
  "What a library calls back with COUNT, when an event comes."
  (if (> count 1)
      (error "callback got ~a" count)
      count))

(defun main ()
  "Run the work handed over, one piece at a time, forever, as an event loop."
  (loop (let ((thunk (next-work)))
          (with-simple-restart (continue "Skip this work and go on with the next.")
            (funcall thunk)))))
LISP
cat >"$work/loop/.slynk-cli.sexp" <<'LISP'
(:main "workloop:main" :main-thread-dispatcher "workloop:run-in-main-thread")
LISP
cd "$work/loop"
run start
expect 0 'workloop loaded'
grep -q 'slynk-cli: running workloop:main in the main thread' "$work/loop/.slynk-cli/image.log" \
  || fail "the image did not run :main"
run eval --main '(list (eq sb-thread:*current-thread* (sb-thread:main-thread)) (length (sb-thread:list-all-threads)))'
expect 0 '= \(T [0-9]+\)$'
# A form in the main thread has no limit, and the watcher of the others'
# limits goes on: it neither ends nor pauses.
run eval --main '(progn (sleep 2.5) :slept)' --wait 6
expect 0 '= :SLEPT$'
run status
expect 0 'no evaluation is running or paused'
run eval '(progn (sleep 100) :done)' --limit 2 --wait 6
expect 1 'was aborted after running 2 s, its limit'

# An error in a form of eval --main pauses it in the main thread: abort is
# refused, and the loop's own restart goes on past it.
run eval --main '(error "boom")'
expect 1 'is paused in the debugger in the main thread' 'boom' 'continue +Skip this work'
refuse '· abort [0-9]' 'Skip to toplevel' 'loading file'

id="$(number_after 'evaluation ')"
run frame "$id" 0
expect 0 "frame 0 of evaluation $id"
run abort "$id"
expect 1 'abort would unwind'
run wait "$id"
restart="$(grep -E '^ +[0-9]+  continue +Skip this work' "$out" | head -1 | awk '{print $1}')"
run restart "$id" "$restart"
expect 1 "evaluation $id was aborted when the main thread went on past it"

# An error in the main loop's own work, as in a C library's callback, pauses
# the main thread as an evaluation of its own; restart-frame or a restart
# goes on, and the loop still serves eval --main after.
run eval '(workloop:run-in-main-thread (lambda () (error "in a callback")))'
expect 0 'finished'
sleep 1
run status
expect 0 'paused in the debugger in the main thread: an error in thread "main thread"'
id="$(grep -oE 'evaluation [0-9]+ is paused' "$out" | grep -oE '[0-9]+')"
run backtrace "$id"
expect 0 'WORKLOOP:MAIN'
run eval --in "$id:0" '(+ 1 2)'
expect 0 '= 3$'
run abort "$id"
expect 1 'abort would unwind'
run wait "$id"
restart="$(grep -E '^ +[0-9]+  continue +Skip this work' "$out" | head -1 | awk '{print $1}')"
run restart "$id" "$restart"
expect 0 "evaluation $id went on"
refuse 'While evaluating the form'
run eval --main '(+ 40 2)'
expect 0 '= 42$'
# A frame of the project's own code in the main thread returns a value.
run eval '(workloop:run-in-main-thread (lambda () (print (workloop::callback 2))))'
sleep 1
run status
id="$(grep -oE 'evaluation [0-9]+ is paused' "$out" | grep -oE '[0-9]+')"
run return "$id" 0 1
expect 0 "evaluation $id went on"
run eval --main '(+ 1 1)'
expect 0 '= 2$'
run stop
expect 0 'stopped'

# :main without a dispatcher: eval --main says what is missing.
echo '(:main "workloop:main")' >"$work/loop/.slynk-cli.sexp"
run start
expect 0 'workloop loaded'
run eval --main '1'
expect 1 'name it with :main-thread-dispatcher'
run stop
expect 0 'stopped'

# No .asd file: no system.  No Slynk: start says how to get one.
mkdir -p "$work/bare" "$work/home"
cd "$work/bare"
run start
expect 0 'no system loaded'
run stop
expect 0 'stopped'
code=0
env -u SLYNK_CLI_SLYNK HOME="$work/home" CL_SOURCE_REGISTRY= "$lisp" start >"$out" 2>&1 </dev/null \
  || code=$?
expect 1 'no Slynk found'

# Slynk through ASDF.
code=0
env -u SLYNK_CLI_SLYNK HOME="$work/home" CL_SOURCE_REGISTRY="$SLYNK_CLI_SLYNK" \
  "$lisp" start >"$out" 2>&1 </dev/null || code=$?
expect 0 'no system loaded'
run stop
expect 0 'stopped'

# Slynk in a SLY that Emacs installed, and the person's init file read,
# with a Quicklisp in it: the system loads through ql:quickload.
mkdir -p "$work/home/.emacs.d/elpa/sly-20260101" "$work/quick"
ln -s "$SLYNK_CLI_SLYNK" "$work/home/.emacs.d/elpa/sly-20260101/slynk"
cat >"$work/home/.sbclrc" <<'LISP'
(require "asdf")
(defpackage #:ql (:use #:cl) (:export #:quickload))
(defvar ql::*loaded* '())
(defun ql:quickload (name)
  (push name ql::*loaded*)
  (asdf:load-system name))
LISP
cp "$project/fixture.asd" "$project/fixture.lisp" "$work/quick/"
cd "$work/quick"
code=0
env -u SLYNK_CLI_SLYNK HOME="$work/home" CL_SOURCE_REGISTRY= "$lisp" start >"$out" 2>&1 </dev/null \
  || code=$?
expect 0 'fixture loaded'
run eval '(list ql::*loaded* (and (fboundp (quote lisp-fixture::outer)) t))'
expect 0 '= \(\("fixture"\) T\)$'
run stop
expect 0 'stopped'
echo "== lisp checks passed"
