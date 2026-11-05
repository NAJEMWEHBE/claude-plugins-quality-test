#!/usr/bin/env bash
# Runs prompt.txt with Claude Code once per arm. The "plugins-on" arm uses every
# installed plugin; each settings file you pass (default: plugins-off.json) is one
# more arm, named after the file, with those settings applied for that run only.
# Your global settings are not changed. Needs a signed-in `claude` CLI and node.
#
# Usage: bash run.sh [--sequential] [--runs N] [settings.json ...]
#   --sequential  run the arms one after the other, so they don't share rate limits
#                 (recommended; the reported run used the parallel default)
#   --runs N      run every arm N times (default 1)
set -euo pipefail
cd "$(dirname "$0")"

# Pinned: the `opus` alias moves to whatever Opus is current.
MODEL=claude-opus-5-5

sequential=0
runs=1
settings=()
while [ $# -gt 0 ]; do
  case $1 in
    --sequential) sequential=1 ;;
    --runs) runs=${2:?--runs needs a number}; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) settings+=("$1") ;;
  esac
  shift
done
[ ${#settings[@]} -gt 0 ] || settings=(plugins-off.json)
case $runs in ''|*[!0-9]*|0) echo "--runs must be a positive number" >&2; exit 2 ;; esac

# Arm list: "name|absolute settings path" (empty path = plugins on).
arms=("plugins-on|")
for f in "${settings[@]}"; do
  [ -f "$f" ] || { echo "settings file not found: $f" >&2; exit 2; }
  arms+=("$(basename "$f" .json)|$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
done

# run <name> <settings path or empty>: one headless build into out/<name>/,
# its log to out/<name>.jsonl and a trimmed evidence file to out/<name>.evidence.json.
run() {
  local name=$1 cfg=$2 code=0
  local extra=()
  [ -z "$cfg" ] || extra=(--settings "$cfg")
  rm -rf "out/$name" && mkdir -p "out/$name"
  (cd "out/$name" && claude -p "$(cat ../../prompt.txt)" \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "Write Edit Read Glob Grep Skill" \
    --max-turns 30 \
    --output-format stream-json --verbose \
    --no-session-persistence ${extra[@]+"${extra[@]}"} < /dev/null > "../$name.jsonl") || code=$?
  node evidence.mjs "out/$name.jsonl" > "out/$name.evidence.json" \
    || echo "$name: could not write evidence" >&2
  return $code
}

names=()
for ((i = 1; i <= runs; i++)); do
  for arm in "${arms[@]}"; do
    name=${arm%%|*}
    [ "$runs" -eq 1 ] || name="$name-$i"
    names+=("$name|${arm#*|}")
  done
done

mkdir -p out
failed=0
report() { echo "$1: exit $2"; [ "$2" -eq 0 ] || failed=1; }

if [ "$sequential" -eq 1 ]; then
  for entry in "${names[@]}"; do
    if run "${entry%%|*}" "${entry#*|}"; then report "${entry%%|*}" 0; else report "${entry%%|*}" $?; fi
  done
else
  pids=()
  for entry in "${names[@]}"; do
    run "${entry%%|*}" "${entry#*|}" &
    pids+=($!)
  done
  # Wait on each PID: a bare `wait` returns 0 even when a run failed.
  for i in "${!pids[@]}"; do
    entry=${names[$i]}
    if wait "${pids[$i]}"; then report "${entry%%|*}" 0; else report "${entry%%|*}" $?; fi
  done
fi

if [ "$failed" -ne 0 ]; then
  echo "At least one run failed: see its out/<name>.jsonl." >&2
  exit 1
fi
echo "Done. Open each out/<name>/index.html in a browser; out/<name>.evidence.json has the start-up plugin list, tool calls, time and cost."
