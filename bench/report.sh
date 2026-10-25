#!/usr/bin/env bash
# Sum benchmark runs (bench/README.md) per model and effort, task and arm,
# as Markdown: how often the check passed, and the median time, cost and
# tokens of each arm.
#   bench/report.sh bench/results/*.jsonl > bench/results/REPORT.md
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: bench/report.sh RESULTS.jsonl..." >&2; exit 2; }
jq -s -r '
  def median: sort | if length == 0 then null
                     elif length % 2 == 1 then .[length / 2 | floor]
                     else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  def fixed(n): if . == null then "–" else (. * pow(10; n) | round) / pow(10; n) | tostring end;
  def tokens: (.input_tokens // 0) + (.output_tokens // 0)
              + (.cache_read_tokens // 0) + (.cache_creation_tokens // 0);
  def summary: {runs: length,
                passed: (map(select(.passed)) | length),
                seconds: (map(.seconds) | median),
                cost: (map(.cost_usd // empty) | median),
                tokens: (map(tokens) | median),
                lisp: (map(.lisp_commands) | median)};
  def row($name): "| \($name) | \(.passed)/\(.runs) | \(.seconds | fixed(0)) | \(.cost | fixed(2)) | \(.tokens / 1000 | fixed(0))k | \(.lisp | fixed(0)) |";
  (map(select(.error)) | length) as $errors
  | map(select(.error | not))
  | group_by([.model, .effort]) | map(
    "## \(.[0].model), effort \(.[0].effort)\n",
    "Claude Code \(.[0].claude), \(.[0].sbcl), slynk-cli \(.[0].tool)\n",
    "| task, arm | passed | median s | median $ | median tokens | median lisp calls |",
    "|---|---|---|---|---|---|",
    (group_by(.task)[] | (.[0].task) as $task
      | (group_by(.arm)[] | .[0].arm as $arm | summary | row("\($task), \($arm)"))),
    "",
    "| all tasks | passed | median s | median $ | median tokens | median lisp calls |",
    "|---|---|---|---|---|---|",
    (group_by(.arm)[] | .[0].arm as $arm | summary | row($arm)),
    "")
  | .[], (if $errors > 0 then "\($errors) runs where the agent could not work, such as at a usage limit, are left out.\n" else empty end)' "$@"
