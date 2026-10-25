# Working in a running image: lisp

A person works on Common Lisp with Emacs connected to a running image: they
evaluate a form, land in the debugger when it fails, look at the frames,
fix the function, compile just that form, and carry on from the frame that
failed. `lisp` gives you the same, as a command. The image keeps its state
between your calls, so you load the project once, not for every try.

The files are still the truth: after working in the image, run the
project's build and tests the way it says, in a fresh process.

## Start

```sh
lisp start            # the project's system: the one .asd at the top, or .slynk-cli.sexp's
lisp start my-app/tests
```

It returns once the system is loaded, or says why it did not load and stays
up for you to fix it. One image per project; `lisp stop` ends it, and
`lisp status` lists what is still running or paused.

## Evaluate

```sh
lisp eval '(my-app:run-report :since "2026-01-01")'
lisp eval - <<'EOF'
(in-package :my-app)
(list *package* (find-class 'invoice))
EOF
```

Each value comes back with a handle, `#@4 = #<INVOICE …>`, and `#@4` in a
later form is that object. `*` is the last value, and an `in-package`
stays for the next call, as at a REPL.

A call waits ten seconds. For a form you expect to take longer, say so:
`lisp eval --wait 300 '(build-index)'` returns as soon as it finishes or
pauses, and at the latest after 300 seconds. An evaluation still running
when the call returns goes on in the image; `lisp wait N --wait 300` takes
it up again. One call with a long `--wait` does what a loop of short ones
would, without the loop.

`describe`, `apropos`, `macroexpand-1` and `trace` are forms like any
other: `lisp eval '(macroexpand-1 (quote (define-rule …)))'`.

## When it fails: the debugger waits

An error does not end the evaluation. It waits in the debugger, and the
answer says what happened and where:

```
evaluation 7 is paused in the debugger

SIMPLE-ERROR: too big: 2

restarts:
  0  abort       Abort evaluation 7.
  1  abort       abort thread (…)

backtrace:
  0  (INNER 1)  src/inner.lisp:8
  1  (OUTER 1)  src/inner.lisp:12
  2  (SB-INT:SIMPLE-EVAL-IN-LEXENV (OUTER 1) #<NULL-LEXENV>)

next: lisp frame 7 F · eval --in 7:F FORM · restart 7 R [FORM...] · …
```

Look before you change anything:

- `lisp frame 7 0`: the frame's arguments and locals, each with a handle.
- `lisp eval --in 7:0 '(* y 10)'`: a form evaluated where the error
  happened, with the frame's variables. An error there leaves the
  evaluation paused where it was.
- `lisp backtrace 7 --from 20`: more frames.

Then go on, without starting over:

1. Fix the function in its file, with your own editing tools.
2. `lisp compile src/inner.lisp:8`: compiles the top-level form that line
   is in, and only that one, as SLY's `C-c C-c` does. Any line of the form
   will do. `lisp compile FILE` compiles and loads the whole file.
   Warnings come with their lines, and exit 1.
3. `lisp restart-frame 7 0`: runs the frame again from its start, so the
   fixed function runs on the same arguments, and the evaluation carries
   on from there.

The other ways on are the restarts: `lisp restart 7 R` invokes restart R,
and forms after it are its arguments, as `use-value` needs:
`lisp restart 9 0 '(* 6 7)'`. `lisp return 7 1 FORM` makes frame 1 return
FORM's value. `lisp abort 7` gives up.

A paused evaluation waits until you resume or abort it. It may hold a lock
another evaluation needs, so an answer that one is still running names the
paused ones. Abort what you no longer need.

To pause a FiveAM test where it fails, let FiveAM call the debugger:
`lisp eval '(let ((fiveam:*on-error* :debug) (fiveam:*on-failure* :debug)) (fiveam:run! (quote my-test)))'`.
`(break)` in a function pauses there too.

## Find your way

- `lisp definition my-app:insert`: where it is defined, into SBCL and the
  libraries too (`lisp definition string-trim`).
- `lisp xref calls my-app:insert`: who calls it; also `calls-who`,
  `references`, `binds`, `sets`, `macroexpands`, `specializes`. This
  covers the code compiled in the image, not SBCL's own.
- `lisp inspect '#@4'`: an object's slots or elements, each with a handle.

## Things to know

- **Expensive state stays.** Data you loaded or built in the image is
  there for the next call; keep it in a variable, `(defvar *orders* …)`,
  rather than building it again. The image holds everything you keep, so
  let go of a large value you no longer need, `(setf *old-orders* nil)`,
  before building another. If the image dies anyway, `lisp` says so and
  shows the end of its output; `lisp start` starts a new one.
- **Long output is cut.** An answer shows the last 200 lines and 16 KiB of
  the output and names the file with all of it, under `.slynk-cli/output/`.
  Read or search that file with your own tools.
- **The image drifts from the files.** After many live changes it no longer
  matches them. `lisp stop` and `lisp start` again now and then, and trust
  the project's build and tests in a fresh process over the image.
- **A restarted frame runs the new function; its callers stay compiled.**
  SBCL may have compiled a caller in the same file on what it derived about
  the old function, such as that it never returns. When a caller then
  complains about values, compile the whole file.
- **Only evaluations pause.** An error in a thread `eval` did not start,
  such as a request to a server started from the image, does not pause.
- **The image is yours.** Never connect to a port you did not start: a
  person's editor may be connected to it.
