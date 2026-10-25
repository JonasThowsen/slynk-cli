## claude-opus-5-5, effort high

Claude Code 2.1.310 (Claude Code), SBCL 2.6.4, slynk-cli 2de39a7

| task, arm | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| failing-test, with | 5/5 | 50 | 0.31 | 279k | 2 |
| failing-test, without | 5/5 | 44 | 0.26 | 262k | 0 |
| feature, with | 5/5 | 118 | 0.69 | 585k | 3 |
| feature, without | 5/5 | 124 | 0.68 | 521k | 0 |
| local-time-bug, with | 5/5 | 80 | 0.34 | 398k | 5 |
| local-time-bug, without | 5/5 | 69 | 0.27 | 329k | 0 |
| macro-bug, with | 5/5 | 85 | 0.49 | 565k | 0 |
| macro-bug, without | 5/5 | 60 | 0.32 | 320k | 0 |
| ppcre-bug, with | 5/5 | 58 | 0.26 | 294k | 4 |
| ppcre-bug, without | 5/5 | 47 | 0.17 | 158k | 0 |
| question, with | 5/5 | 91 | 0.55 | 615k | 4 |
| question, without | 5/5 | 83 | 0.46 | 418k | 0 |
| slow-repro, with | 5/5 | 134 | 0.37 | 494k | 7 |
| slow-repro, without | 5/5 | 82 | 0.21 | 172k | 0 |

| all tasks | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| with | 35/35 | 85 | 0.37 | 449k | 4 |
| without | 35/35 | 69 | 0.31 | 325k | 0 |

## claude-opus-5-5, effort medium

Claude Code 2.1.310 (Claude Code), SBCL 2.6.4, slynk-cli 2de39a7-dirty

| task, arm | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| failing-test, with | 5/5 | 41 | 0.26 | 286k | 2 |
| failing-test, without | 5/5 | 32 | 0.21 | 152k | 0 |
| feature, with | 5/5 | 91 | 0.52 | 416k | 0 |
| feature, without | 5/5 | 91 | 0.51 | 327k | 0 |
| local-time-bug, with | 5/5 | 51 | 0.25 | 290k | 0 |
| local-time-bug, without | 5/5 | 44 | 0.22 | 229k | 0 |
| macro-bug, with | 5/5 | 58 | 0.28 | 307k | 0 |
| macro-bug, without | 5/5 | 39 | 0.28 | 295k | 0 |
| ppcre-bug, with | 5/5 | 39 | 0.19 | 193k | 0 |
| ppcre-bug, without | 5/5 | 35 | 0.16 | 157k | 0 |
| question, with | 5/5 | 67 | 0.43 | 473k | 4 |
| question, without | 5/5 | 72 | 0.4 | 419k | 0 |
| slow-repro, with | 5/5 | 87 | 0.29 | 362k | 0 |
| slow-repro, without | 5/5 | 62 | 0.2 | 192k | 0 |

| all tasks | passed | median s | median $ | median tokens | median lisp calls |
|---|---|---|---|---|---|
| with | 35/35 | 59 | 0.28 | 303k | 0 |
| without | 35/35 | 48 | 0.25 | 235k | 0 |


The medium runs are marked `2de39a7-dirty`: the one change was in
`bench/run.sh`, creating `bench/results/` before the first run; the tool,
the guide and the tasks were those of 2de39a7.
