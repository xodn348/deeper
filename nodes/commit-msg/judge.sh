#!/usr/bin/env bash
# judge.sh — judges the latest model output in state.md against four rules.
# Appends a single judge_result event to events.jsonl.
#
# Usage: judge.sh <run-dir> <round>

set -euo pipefail

RUN_DIR="${1:?run-dir required}"
ROUND="${2:?round required}"
STATE="$RUN_DIR/state.md"
EVENTS="$RUN_DIR/events.jsonl"

# Extract last round's output: from last "--- round N ---" to EOF, minus the header line.
latest=$(awk '/^--- round /{buf=""; next} {buf=buf $0 "\n"} END{printf "%s", buf}' "$STATE" | sed 's/[[:space:]]*$//')
# Strip trailing newline
latest=$(printf '%s' "$latest" | awk 'NF' | tail -1)

violations=()
score_raw=4   # 4 rules, deduct 1 per violation

# Rule 1: Conventional Commits prefix
if ! printf '%s' "$latest" | grep -qE '^(feat|fix|refactor|docs|test|chore|perf)(\([a-z0-9._-]+\))?: '; then
  violations+=("no-conv-format")
  score_raw=$((score_raw - 1))
fi

# Rule 2: Length <= 70
len=$(printf '%s' "$latest" | awk '{print length}')
if [ "$len" -gt 70 ]; then
  violations+=("length")
  score_raw=$((score_raw - 1))
fi

# Rule 3: Imperative mood / lowercase verb after the colon
verb=$(printf '%s' "$latest" | sed -E 's/^[a-z]+(\([^)]*\))?: ([A-Za-z]+).*/\2/')
if [ "$verb" != "$latest" ]; then
  first_char=${verb:0:1}
  if [ "$first_char" != "$(printf '%s' "$first_char" | tr '[:upper:]' '[:lower:]')" ]; then
    violations+=("verb-tense")
    score_raw=$((score_raw - 1))
  elif printf '%s' "$verb" | grep -qE '^(Added|added|Adds|adds|Adding|adding|Fixed|fixed|Fixes|fixes|Refactored|refactored)$'; then
    violations+=("verb-tense")
    score_raw=$((score_raw - 1))
  fi
fi

# Rule 4: No trailing period
if printf '%s' "$latest" | grep -q '\.$'; then
  violations+=("trailing-period")
  score_raw=$((score_raw - 1))
fi

score=$(python3 -c "print(round($score_raw/4, 3))")

iso_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
node=$(basename "$(cd "$RUN_DIR/../.." && pwd)/$(basename "$(dirname "$RUN_DIR")")")
run_id=$(basename "$RUN_DIR")

violations_json=$(printf '%s\n' "${violations[@]+"${violations[@]}"}" | python3 -c '
import json, sys
vs = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(vs))
')

esc_latest=$(printf '%s' "$latest" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

printf '{"ts":"%s","run_id":"%s","node":"%s","round":%d,"type":"judge_result","score":%s,"violations":%s,"detail":{"latest":%s,"length":%d}}\n' \
  "$iso_now" "$run_id" "$node" "$ROUND" "$score" "$violations_json" "$esc_latest" "$len" >> "$EVENTS"
