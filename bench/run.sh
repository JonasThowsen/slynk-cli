#!/usr/bin/env bash
# Run the benchmark (bench/README.md): each task, with and without lisp,
# REPEAT times, each run a fresh Claude Code session in a fresh copy of the
# task's project, then the task's check.  One line per run goes to
# bench/results/DATE-MODEL-EFFORT.jsonl; each run's directory, with its
# transcript, to ~/.cache/slynk-cli-bench/, or BENCH_RUNS.
#   bench/run.sh --model M --effort E [--repeat N] [--jobs J] [--arms A,B]
#                [--limit S] [--tasks DIR] [TASK...]
# Run inside `nix develop .#bench`.
set -euo pipefail
bench="$(cd "$(dirname "$0")" && pwd)"
model="" effort="" repeat=5 jobs=4 arms="with,without" limit=1800 tasks_dir="$bench/tasks"
tasks=()
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --effort) effort="$2"; shift 2 ;;
    --repeat) repeat="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --arms) arms="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --tasks) tasks_dir="$(cd "$2" && pwd)"; shift 2 ;;
    -*) echo "run.sh: unknown option $1" >&2; exit 2 ;;
    *) tasks+=("$1"); shift ;;
  esac
done
[ -n "$model" ] && [ -n "$effort" ] || { echo "run.sh: --model and --effort are needed" >&2; exit 2; }
if [ ${#tasks[@]} -eq 0 ]; then
  for dir in "$tasks_dir"/*/; do tasks+=("$(basename "$dir")"); done
fi

# The runs must not depend on the person's setup.
refuse() { echo "run.sh: $*" >&2; exit 1; }
[ -n "${BENCH_LISP:-}" ] || refuse "run inside nix develop .#bench"
command -v claude >/dev/null || refuse "claude is not on PATH"
[ ! -e "$HOME/.claude/CLAUDE.md" ] || refuse "~/.claude/CLAUDE.md would reach every run; move it away first"
[ ! -e "$HOME/.sbclrc" ] || refuse "~/.sbclrc would reach every run; move it away first"
# The SBCL's own sysinit, which maps SYS: to its sources, is part of it.
[ ! -e /etc/sbclrc ] || refuse "/etc/sbclrc would reach every run; move it away first"
sbcl --noinform --non-interactive --no-userinit --no-sysinit --eval '(require "asdf")' \
  --eval '(when (or (asdf:find-system "cl-ppcre" nil) (asdf:find-system "local-time" nil))
            (sb-ext:exit :code 1))' >/dev/null 2>&1 \
  || refuse "the bench SBCL can load cl-ppcre or local-time; a task's copy must be the only one"

# PATH without any lisp command, for the arm without it.
plain_path=""
IFS=: read -ra path_dirs <<<"$PATH"
for dir in "${path_dirs[@]}"; do
  [ -x "$dir/lisp" ] || plain_path="${plain_path:+$plain_path:}$dir"
done

stamp="$(date +%Y-%m-%d)"
results="$bench/results"
# Away from this repository, so an agent looking around finds no check.
runs="${BENCH_RUNS:-$HOME/.cache/slynk-cli-bench}/$stamp-$model-$effort"
mkdir -p "$runs" "$results"
record="$results/$stamp-$model-$effort.jsonl"
claude_version="$(claude --version | head -1)"
sbcl_version="$(sbcl --version)"
tool_revision="$(git -C "$bench/.." rev-parse --short HEAD)$(git -C "$bench/.." diff --quiet || echo -dirty)"

instructions_base='# Notes for agents

- This is a Common Lisp project. SBCL and ASDF are on PATH as `sbcl`; the
  project'"'"'s systems are in this directory, and the libraries it needs are
  in the SBCL'"'"'s ASDF registry.
'
instructions_with='- Work in a running image: `lisp start`, then `lisp eval` and its debugger.
  Read `LISP-GUIDE.md` first.
'

# One run: TASK ARM REPEAT.
run_one() {
  local task="$1" arm="$2" rep="$3"
  local dir="$runs/$task-$arm-$rep"
  local project="$dir/project"
  rm -rf "$dir"
  mkdir -p "$project"
  bash "$tasks_dir/$task/setup.sh" "$project" >"$dir/setup.log" 2>&1
  printf '%s' "$instructions_base" >"$project/CLAUDE.md"
  if [ "$arm" = with ]; then
    printf '%s' "$instructions_with" >>"$project/CLAUDE.md"
    cp "$bench/../docs/guide.md" "$project/LISP-GUIDE.md"
  fi
  git -C "$project" add -A
  git -C "$project" commit -q --amend --no-edit
  local path="$plain_path" extra=()
  if [ "$arm" = with ]; then
    path="$BENCH_LISP/bin:$plain_path"
  else
    extra=(-u SLYNK_CLI_SLYNK)
  fi
  local start end status=0 timed_out=false
  start="$(date +%s)"
  (cd "$project" && env "${extra[@]}" PATH="$path" timeout --kill-after=30 "$limit" \
     claude -p --model "$model" --effort "$effort" \
       --output-format stream-json --verbose --no-session-persistence \
       --setting-sources project --strict-mcp-config --disable-slash-commands \
       --permission-mode acceptEdits --allowedTools "Bash Read Edit Write Glob Grep TodoWrite" \
       <"$tasks_dir/$task/prompt.md" >"$dir/transcript.jsonl" 2>"$dir/claude.err") || status=$?
  end="$(date +%s)"
  [ "$status" -eq 124 ] || [ "$status" -eq 137 ] && timed_out=true
  # Whatever the run left running in its directory: an image, a server.
  (cd "$project" && PATH="$BENCH_LISP/bin:$plain_path" lisp stop >/dev/null 2>&1) || true
  for proc in /proc/[0-9]*; do
    case "$(readlink "$proc/cwd" 2>/dev/null)" in
      "$dir"*) kill "${proc#/proc/}" 2>/dev/null || true ;;
    esac
  done
  local passed=false
  if [ "$timed_out" = false ] \
       && timeout 900 bash "$tasks_dir/$task/check/check.sh" "$project" >"$dir/check.log" 2>&1; then
    passed=true
  fi
  jq -c -n \
    --arg task "$task" --arg arm "$arm" --argjson repeat "$rep" \
    --arg model "$model" --arg effort "$effort" --arg claude "$claude_version" \
    --arg sbcl "$sbcl_version" --arg tool "$tool_revision" \
    --argjson passed "$passed" --argjson timed_out "$timed_out" \
    --argjson seconds "$((end - start))" --argjson exit "$status" \
    --arg check "$(tail -5 "$dir/check.log" 2>/dev/null)" \
    --slurpfile transcript <(jq -c . "$dir/transcript.jsonl" 2>/dev/null || true) '
    ($transcript | map(select(.type == "result")) | last) as $result
    | ($transcript | map(select(.type == "assistant") | .message.content[]?
                         | select(.type == "tool_use" and .name == "Bash") | .input.command)) as $commands
    | {task: $task, arm: $arm, repeat: $repeat, model: $model, effort: $effort,
       claude: $claude, sbcl: $sbcl, tool: $tool,
       passed: $passed, timed_out: $timed_out, exit: $exit, seconds: $seconds,
       # The agent never got to work, as at a usage limit: not the task failing.
       error: ((($result == null) and ($timed_out | not)) or ($result.is_error // false)),
       cost_usd: $result.total_cost_usd, turns: $result.num_turns,
       input_tokens: $result.usage.input_tokens, output_tokens: $result.usage.output_tokens,
       cache_read_tokens: $result.usage.cache_read_input_tokens,
       cache_creation_tokens: $result.usage.cache_creation_input_tokens,
       tool_calls: ($transcript | map(select(.type == "assistant") | .message.content[]?
                                      | select(.type == "tool_use")) | length),
       commands: $commands,
       lisp_commands: ($commands | map(select(test("(^|[;&|(\\s])lisp\\s"))) | length),
       check: $check}' >"$dir/result.json"
  flock "$record.lock" sh -c "cat '$dir/result.json' >>'$record'"
  echo "$task $arm $rep: passed=$passed $((end - start))s"
}
export -f run_one
export bench tasks_dir runs record model effort limit plain_path claude_version sbcl_version \
  tool_revision instructions_base instructions_with BENCH_LISP

# Repeats outermost, the arms in a random order within each, so neither arm
# runs at a better time of day.
for rep in $(seq 1 "$repeat"); do
  for task in "${tasks[@]}"; do
    for arm in $(tr , '\n' <<<"$arms" | shuf); do
      echo "$task $arm $rep"
    done
  done
done | xargs -P "$jobs" -L 1 bash -c 'run_one "$@"' _
rm -f "$record.lock"
echo "results: $record"
