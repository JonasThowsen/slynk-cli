# Hard tasks

Eight tasks (bench/README.md, "Hard tasks"), five runs per arm, Claude Code
with Opus 5.5 at effort high, 2026-10-26. A pilot of one run per task and
arm came first to see that the tasks were not trivial; it is not counted.

## The run

### claude-opus-5-5, effort high

Claude Code 2.1.310 (Claude Code), SBCL 2.6.4, slynk-cli 89464ad

| task, arm | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| chipz-bug, with | 5/5 | 302 | 0.95 | 1230k | 9 |
| chipz-bug, without | 5/5 | 187 | 0.78 | 799k | 0 |
| cl-json-bug, with | 5/5 | 328 | 0.74 | 901k | 11 |
| cl-json-bug, without | 5/5 | 134 | 0.66 | 661k | 0 |
| deep-bug, with | 5/5 | 343 | 0.87 | 1259k | 13 |
| deep-bug, without | 5/5 | 966 | 1 | 997k | 0 |
| fset-bug, with | 5/5 | 100 | 0.36 | 386k | 4 |
| fset-bug, without | 5/5 | 70 | 0.24 | 241k | 0 |
| jzon-bug, with | 5/5 | 86 | 0.48 | 509k | 4 |
| jzon-bug, without | 5/5 | 84 | 0.45 | 469k | 0 |
| server-bug, with | 5/5 | 82 | 0.33 | 356k | 2 |
| server-bug, without | 5/5 | 63 | 0.3 | 229k | 0 |
| slow-report, with | 5/5 | 234 | 0.63 | 805k | 6 |
| slow-report, without | 5/5 | 277 | 0.56 | 596k | 0 |
| stateful-bug, with | 5/5 | 180 | 0.45 | 562k | 6 |
| stateful-bug, without | 5/5 | 154 | 0.41 | 331k | 0 |

| all tasks | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| with | 40/40 | 186 | 0.61 | 710k | 6 |
| without | 40/40 | 155 | 0.5 | 445k | 0 |

Every `cl-json-bug` run with `lisp` met a bug of the tool: an error nested
past SBCL's maximum error depth, which is that task's bug, left `lisp eval`
without an answer instead of pausing. 75c553f fixed it, and the task ran
again on that revision, both arms:

## cl-json-bug again, on 75c553f

### claude-opus-5-5, effort high

Claude Code 2.1.310 (Claude Code), SBCL 2.6.4, slynk-cli 75c553f

| task, arm | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| cl-json-bug, with | 5/5 | 148 | 0.72 | 686k | 7 |
| cl-json-bug, without | 5/5 | 103 | 0.55 | 447k | 0 |

| all tasks | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| with | 5/5 | 148 | 0.72 | 686k | 7 |
| without | 5/5 | 103 | 0.55 | 447k | 0 |

