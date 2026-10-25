# Benchmark: agents with and without `lisp`

The question is whether a coding agent does Common Lisp work better with
`lisp` and its guide than without them. "Better" is, in this order: the
task's check passes more often; it takes less time; it costs fewer tokens.

## The two arms

Each run gives an agent one task in a fresh copy of its project, with the
same SBCL, the same libraries and the same prompt.

- **without**: `sbcl` on PATH and the files; what an agent has in a Lisp
  project today. It runs `sbcl --non-interactive --eval ...`, a script, or
  the project's tests, as it chooses.
- **with**: the same, plus `lisp` on PATH, a copy of `docs/guide.md` in
  the run's directory, and one line that points to it in `CLAUDE.md`, as a
  project would add it.

Both arms have that file with the same text; the "with" arm's has the one
line more.

Nothing else differs: the prompt says nothing of either tool.

The runs are independent of each other and of the person's setup, with
the person's login. Claude Code runs with `--setting-sources project`,
`--strict-mcp-config` and `--disable-slash-commands`: no user settings,
plugins, MCP servers or skills. The runner refuses to start when global
instructions (`~/.claude/CLAUDE.md`) or the person's SBCL init files
(`~/.sbclrc`, `/etc/sbclrc`) exist, so both arms and the check run SBCL
without them; the SBCL's own sysinit, which only tells it where its
sources are, is part of the SBCL. Each run is in a fresh directory, and a run that
passes 30 minutes is stopped and counts as failed. Each task runs five
times per arm, with Claude Code and Opus 5.5, at effort high and at
medium.

The bench's SBCL has the libraries the tasks need, but never the library a
task puts a defect into, so the only copy an agent can load is the task's
own.

## Tasks

Each task is a directory in `tasks/`: `prompt.md`, the prompt; `setup.sh
DIR`, which makes the project in DIR as one git commit, from `project/` or
from a library's pinned source with `defect.patch` applied; and `check/`,
which the agent never sees. After the run, `check/check.sh DIR` runs in a
fresh SBCL against what the agent left; the run passes when it exits 0.

The tasks are what Lisp work is, not built for the tool to win:

| task | project | the work |
|------|---------|----------|
| `ppcre-bug` | cl-ppcre, a defect put in | fix the bug an issue reports |
| `local-time-bug` | local-time, a defect put in | fix the bug an issue reports |
| `failing-test` | a project of its own | a test fails; fix the code, not the test |
| `slow-repro` | a project of its own | a bug that shows only after a setup that takes a while |
| `macro-bug` | a project of its own | a macro expands wrongly for one case |
| `feature` | a project of its own | add a small feature, checked by tests the agent does not see |
| `question` | cl-ppcre | answer a question about the code in `ANSWER.md`, checked against the answer |

### Hard tasks

The tasks above all passed in both arms within a few minutes. The hard
ones take a strong agent longer, and the distance from where a bug shows
to its cause is larger. Four are real bugs a library's maintainers fixed,
put back into the version nixpkgs pins with the regression test taken
out; the report is a user's, rewritten so it does not point at the fix.
The others are projects of the bench's own, of 1000 to 2000 lines each
in several packages, with their own tests; `slow-report` is about speed,
not a bug.

| task | project | the work |
|------|---------|----------|
| `fset-bug` | FSet 2.2.0, functional collections | sets and maps merge distinct cons keys whose cdrs FSet cannot order; the cause is in the ordering under every collection (upstream 7a2cb81, https://github.com/slburson/fset/issues/56) |
| `jzon-bug` | jzon 1.1.4, JSON | floats with no fractional part are written with shifted digits and a garbage character; the cause is in the Schubfach float printer (upstream be8542e, https://github.com/Zulu-Inuoe/jzon/issues/45) |
| `chipz-bug` | chipz 0.8, decompression | `make-decompressing-stream` fails on a gzip file that `decompress` reads fine; the inflater loses its place when its input ends inside a stored block's header (upstream f3ce12e, https://github.com/sharplispers/chipz/pull/10) |
| `cl-json-bug` | cl-json 0.6.0, JSON | encoding a document with objects nested three deep kills SBCL with "Help! 11 nested errors"; a handler does its fallback work without unwinding (upstream 1941150, https://github.com/hankhero/cl-json/issues/1) |
| `deep-bug` | a dependency resolver and a registry snapshot | the resolver fails on a package whose constraint plainly allows a release, and the cause is layers away from the error |
| `stateful-bug` | a full-text search index and a sample archive that takes about a minute to build | an update is lost after a particular sequence of operations on the full archive, which a small index does not show |
| `server-bug` | a job server with worker threads and a line protocol | a job is never run, and a worker fails on another job that was cancelled; the cause was laid earlier, outside that thread |
| `slow-report` | a monthly report over a sample access log | the report takes almost a minute; make it take under 15 seconds with the same output |

## Running

```sh
nix develop .#bench
bench/run.sh --model claude-opus-5-5 --effort high --repeat 5 [--jobs 4] [--label L] [TASK...]
bench/report.sh bench/results/*.jsonl > bench/results/REPORT.md
```

Each run is one line of `results/DATE-MODEL-EFFORT.jsonl`, or
`DATE-MODEL-EFFORT-LABEL.jsonl` with `--label LABEL`: task, arm,
repeat, model, effort and versions, whether the check passed, seconds, tokens and
cost as the agent's CLI reports them, and each command the agent ran.
Each run's directory, with the project as the agent left it and its
transcript, stays in `~/.cache/slynk-cli-bench/` (or `BENCH_RUNS`), away
from this repository so an agent looking around finds no check; it is not
committed. `report.sh` sums them per task and arm. A run where the agent never got
to work, such as at a usage limit, is marked `error` and left out of the
sums, and the report says how many there were.
