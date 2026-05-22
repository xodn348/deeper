#!/usr/bin/env bash
# feedback.sh — read the last N runs of a node, extract repeated violations,
# auto-append new lessons to nodes/<node>/BANS.md (idempotent).
#
# Usage: feedback.sh <node-name>
# Env: LESSONS_WINDOW (default 5), LESSON_THRESHOLD (default 2)

set -euo pipefail

NODE="${1:?node name required}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_DIR="$REPO_ROOT/nodes/$NODE"
RUNS_DIR="$REPO_ROOT/runs/$NODE"
BANS_FILE="$NODE_DIR/BANS.md"

WINDOW="${LESSONS_WINDOW:-5}"
THRESHOLD="${LESSON_THRESHOLD:-2}"

[ -d "$RUNS_DIR" ] || { echo "feedback.sh: no runs yet for $NODE"; exit 0; }

recent_runs=$(ls -1t "$RUNS_DIR" | head -n "$WINDOW")
[ -z "$recent_runs" ] && { echo "feedback.sh: no runs in $RUNS_DIR"; exit 0; }

touch "$BANS_FILE"

# Aggregate violation counts across recent runs (count: in how many DISTINCT runs each violation appeared)
agg=$(
  for r in $recent_runs; do
    if [ -f "$RUNS_DIR/$r/events.jsonl" ]; then
      grep -E '"type"[[:space:]]*:[[:space:]]*"judge_result"' "$RUNS_DIR/$r/events.jsonl" \
        | python3 -c '
import json, sys
seen = set()
for line in sys.stdin:
    try: e = json.loads(line)
    except: continue
    for v in e.get("violations", []):
        seen.add(v)
for v in seen:
    print(v)
'
    fi
  done | sort | uniq -c | awk '{ printf "%d %s\n", $1, $2 }'
)

new_lessons=0
echo "feedback.sh: violation counts across last $WINDOW runs of $NODE:"
echo "$agg" | sed 's/^/  /'

while read -r count key; do
  [ -z "$count" ] && continue
  if [ "$count" -ge "$THRESHOLD" ]; then
    # Idempotent: only append if not already present
    if ! grep -q "^- \`$key\`" "$BANS_FILE" 2>/dev/null; then
      example_run=$(for r in $recent_runs; do
        if grep -q "\"$key\"" "$RUNS_DIR/$r/events.jsonl" 2>/dev/null; then
          echo "$r"; break
        fi
      done)
      printf -- '- `%s` — promoted from %d of last %d runs (example: %s)\n' \
        "$key" "$count" "$WINDOW" "$example_run" >> "$BANS_FILE"
      new_lessons=$((new_lessons + 1))
      echo "  -> PROMOTED: $key"
    fi
  fi
done <<< "$agg"

echo "feedback.sh: $new_lessons new lesson(s) appended to $BANS_FILE"
