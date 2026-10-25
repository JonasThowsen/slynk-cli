# slynk-cli

`lisp` gives a coding agent what SLY gives a person in Emacs: a running
Common Lisp image to evaluate in, a debugger that waits at an error, frames
to look into and restart, one form compiled at a time, and the way to a
definition. It is a command, so it works from any agent harness that can
run one, such as Claude Code or Codex, and a person can use it from a
terminal too. The image keeps all the state between calls; each call is a
short connection to it.

```sh
lisp start                     # an image of the project, its system loaded
lisp eval '(outer 1)'          # an error pauses: condition, restarts, frames with file:line
lisp frame 7 0                 # the frame's locals, each with a handle #@K
lisp eval --in 7:0 '(* y 10)'  # a form evaluated in that frame
#   ... fix the function in its file ...
lisp compile src/inner.lisp:8  # compile only the form that line is in, as C-c C-c
lisp restart-frame 7 0         # run the frame again: the evaluation finishes
```

`bench/` measures whether agents do better with it than without it; the
results are under [Does it help?](#does-it-help). `docs/guide.md` is the
guide for agents.

It runs on SBCL only, since the debugger it drives is SBCL's, with Slynk,
the server half of [SLY](https://github.com/joaotavora/sly).

## Install

With Nix, run it from the flake, or add it to a project's dev shell:

```nix
inputs.slynk-cli.url = "github:JonasThowsen/slynk-cli";
# ...
devShells.default = pkgs.mkShell {
  packages = [ sbcl slynk-cli.packages.${system}.default ];
};
```

The flake's `lisp` brings its own Slynk. Without Nix, clone the repository
and put its `bin/` on PATH; it needs `sbcl` on PATH and Slynk where the
image can find it (below).

To point an agent at it, add a line to the project's `AGENTS.md` or
`CLAUDE.md`:

```markdown
- Work in a running image: `lisp start`, then `lisp eval` and its debugger.
  Read https://github.com/JonasThowsen/slynk-cli/blob/main/docs/guide.md first.
```

## The project

`lisp` works on a root: the nearest directory up from the current one that
has a `.slynk-cli.sexp`, else the top of the git work tree, else the
current directory.

`start` runs `sbcl` from PATH, with the person's init files, as `M-x sly`
does, so a Quicklisp set up in `~/.sbclrc` is there. In the image it:

1. loads ASDF and then the `:init` files of the configuration;
2. registers the root's systems: every directory under the root that holds
   an `.asd` file, except directories whose name starts with a dot and
   directories reached through a symbolic link. ASDF looks for them before
   every other source of systems, however the `:init` files set it up, so
   the root's copy of a system wins over one of the same name from
   Quicklisp, Nix or the person's registry; of two under the root, the one
   nearer the root wins;
3. compiles the project's files under the root into `.slynk-cli/fasl/`,
   with at least `(debug 3)` while it compiles them, so the debugger has
   every local of their functions and can restart their frames, and none
   of them compiled before under another policy is loaded; a library
   outside the root keeps the compiled files and policy it comes with,
   also when the image compiles it;
4. loads Slynk and the server, and listens on 127.0.0.1;
5. loads the system: the one `start` is given, else the configuration's
   `:system`, else the system named after the one `.asd` file at the top
   of the root, else none; through `ql:quickload` when Quicklisp is
   loaded, else `asdf:load-system`.

Slynk is found through `SLYNK_CLI_SLYNK`, a directory with `slynk.asd`,
which the flake's `lisp` sets to its own; else through ASDF, as Quicklisp
or a source registry provides it; else in a SLY that Emacs installed with
package.el or straight.el, under `~/.emacs.d/` or `~/.config/emacs/`. Without one, `start` says
how to get it and exits 1.

`.slynk-cli.sexp` configures a project. It is a property list, read without
evaluation, and every key is optional:

```lisp
(:system "tun/tests"
 :lisp ("sbcl" "--noinform" "--no-userinit" "--no-sysinit")
 :init ("scripts/setup.lisp"))
```

- `:system`: the system `start` loads when it is given none.
- `:lisp`: the command that starts the image, `("sbcl" "--noinform")` by
  default; `start` adds its own arguments after it.
- `:init`: files the image loads first, relative to the root, in
  `CL-USER`, before anything else. They may set up ASDF their own way, as
  a project with its own source registry does.

`.slynk-cli/` under the root, or the directory `SLYNK_CLI_STATE` names,
holds the image's records: its port and process, `image.log` with its
output, the compiled files and `output/`. It writes a `.gitignore` of `*`
into itself, so no project has to ignore it.

## Commands

```
lisp start [--port N] [SYSTEM]
lisp stop | status
lisp eval [FORM | -] [--package P] [--wait S] [--limit S]
lisp eval --in N:F FORM [--wait S]
lisp wait N [--wait S]
lisp abort N
lisp backtrace N [--from K] [--count C]
lisp frame N F
lisp restart N R [FORM...]
lisp restart-frame N F
lisp return N F FORM
lisp compile FILE[:LINE]
lisp definition NAME
lisp xref calls|calls-who|references|binds|sets|macroexpands|specializes NAME
lisp inspect FORM
```

**The image.** `start` starts the image in the background on port N, or a
free port, and returns once its system is loaded, saying so. A load that
fails is reported, with exit 1, and the image stays up to be fixed. Every
other command talks to the image `start` recorded, or to `--port N`; it
never picks a port by itself, so it never reaches an image a person's
editor is connected to. Without an image, a command says to start one and
exits 1. `stop` ends the image. `status` gives its port, process and the
evaluations that have not finished.

**Evaluating.** `eval` reads FORM, or standard input for `-` or no FORM,
in the image's current package, and evaluates its forms in order in a
thread of its own: evaluation N, numbered from 1 per image. The package
starts as `CL-USER`, `--package P` sets it for this call, and an
`in-package` among the forms changes it for later calls, as at a REPL.
`*`, `**` and `***` are the primary values of the last three evaluations
that finished. The answer gives each value of the last form with a handle,
`#@K`, and what the forms wrote to standard output, error output and trace
output. `#@K` in a later form is a form whose value is that object.
Standard input is empty.

**Paused.** An unhandled error, a `break`, or any other way into the
debugger pauses the evaluation in its thread. The answer gives the
condition and its type, the restarts numbered from 0, and the first 20
frames numbered from 0, each with the file and line of its source where it
has one, and the commands that go on from there. The evaluation's own
frames end the backtrace; the server's frames are not shown. It stays
paused until a command resumes or aborts it:

- `frame N F` gives frame F's function, its source location, and its
  arguments and locals, each value with a handle.
- `eval --in N:F FORM` evaluates FORM in frame F's lexical environment,
  in the paused thread, and answers with its values and output. An error
  in FORM is reported; the evaluation stays paused where it was. A FORM
  still running after `--wait` seconds goes on in that thread, and the
  answer says so; the evaluation answers no other command until it ends.
- `restart N R [FORM...]` invokes restart R with the FORMs' values as
  its arguments, as `use-value 42` needs. `restart-frame N F` runs frame
  F again from its start, so a function redefined since runs in its new
  form. `return N F FORM` returns FORM's values from frame F. Each then
  answers as `eval` does: the evaluation has finished, paused again, or
  is still running.
- `backtrace N` lists C frames, 20 by default, from frame K, 0 by
  default.
- `abort N` ends the evaluation, paused or running, through its abort
  restart, also while its thread is busy with a FORM of `eval --in`: it
  interrupts the thread rather than sending it a command.

**Waiting.** A call waits for its evaluation to finish or pause for at
most `--wait` seconds, 10 by default. After that it answers that
evaluation N is still running, and the evaluation goes on; `wait N` takes
it up again. An evaluation that runs longer than `--limit` seconds, 1800
by default, is aborted; only the time it runs counts, not the time it is
paused. A paused evaluation waits until it is resumed or aborted, or the
image stops; since its thread may hold a lock that another evaluation
waits for, an answer that an evaluation is still running also lists the
evaluations that are paused.

**Compiling.** `compile FILE:LINE` compiles the top-level form that LINE,
any line of it, is in, as SLY's `C-c C-c` does. The form is read in the
package that the `in-package` forms before it in FILE name, and its
definitions record FILE and the form's position as their source. `compile
FILE` compiles the whole file into `.slynk-cli/fasl/` and loads it, as
`C-c C-k`. Both list the errors, warnings and style warnings, each with
the file and line it is about, and exit 1 when there is any.

**Finding.** `definition NAME` lists where NAME is defined, by kind, each
with a file and line, into SBCL and the libraries too when their source is
on disk. `xref` lists who calls, is called by, references, binds, sets,
macroexpands or specializes on NAME, with files and lines, among the code
compiled in the image: the project and its libraries, not SBCL itself,
which is built without that record. NAME is read in the current package.
`inspect FORM` gives the value's type and its parts, the slots of an
instance or the elements of a sequence, each with a handle. Anything else,
such as `describe`, `apropos`, `macroexpand` or `trace`, is a form for
`eval`.

**Answers.** Answers are plain text, for an agent to read. A printed value
is cut at 2,000 characters, with `*print-length*` 50 and `*print-level*`
6. An answer shows at most the last 200 lines and 16 KiB of an
evaluation's output, says how much it left out, and names the file in
`output/` with all of it. Files and lines are relative to the root when
they are in it. The exit code is 0 when the evaluation finished or the
command did what it was asked, 1 when the evaluation paused or is still
running, compiling found a problem, or the command failed, and 2 for a
usage error.

**The connection.** Slynk listens on 127.0.0.1 only. It has no
authentication and gives full access to the process, as it does for SLY.
`lisp` reaches it through Slynk's wire protocol and calls only the
server's own functions there, so the image is also an ordinary Slynk
server that SLY can connect to. An error in a thread the evaluation did
not start, such as a request to a web server started from the image, does
not pause; it goes where it would in any image.

## Does it help?

Not on the tasks measured so far. On seven tasks in Common Lisp projects
(bugs reported in cl-ppcre and local-time, a failing test, a bug behind a
slow setup, a macro bug, a small feature, a question about cl-ppcre's
code), Claude Code with Opus 5.5 passed every task in both arms, at effort
high and at medium: 140 runs, 2026-10-25.

| effort | arm | passed | median time | median cost | median tokens |
|--------|-----|--------|-------------|-------------|---------------|
| high | with `lisp` | 35/35 | 85 s | $0.37 | 449k |
| high | without | 35/35 | 69 s | $0.31 | 325k |
| medium | with `lisp` | 35/35 | 59 s | $0.28 | 303k |
| medium | without | 35/35 | 48 s | $0.25 | 235k |

With `lisp` the runs took longer and cost more. The agents read the guide
and used `lisp` as a REPL that stays up, mostly `eval`, `start` and
`compile`, and not its debugger: in the 70 runs with it, no `frame`,
`backtrace` or `restart-frame`. These tasks could be solved by reading the
code, and there the tool is overhead. Whether it helps where reading is not
enough, in a larger code base or with a bug that shows only at run time, is
not measured yet. Every run, per task: `bench/results/REPORT.md`.

## Development

`test/run.sh` checks each behaviour above against fixture projects, in a
state directory of its own; `nix flake check` runs it too. `bench/` has
its own README.
