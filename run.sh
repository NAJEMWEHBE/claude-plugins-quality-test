#!/usr/bin/env bash
# Runs the same prompt twice with Claude Code: once with every installed plugin,
# once with three plugins switched off for that run only (plugins-off.json).
# Your global settings are not changed. Needs a signed-in `claude` CLI.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out/plugins-on out/plugins-off

run() {
  local dir=$1; shift
  (cd "out/$dir" && claude -p "$(cat ../../prompt.txt)" \
    --model opus \
    --permission-mode acceptEdits \
    --allowedTools "Write Edit Read Glob Grep Skill" \
    --max-turns 30 \
    --output-format stream-json --verbose \
    --no-session-persistence "$@" < /dev/null > ../$dir.jsonl)
}

run plugins-on &
run plugins-off --settings ../../plugins-off.json &
wait
echo "Done. Open out/plugins-on/index.html and out/plugins-off/index.html in a browser."
