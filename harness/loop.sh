#!/usr/bin/env bash
# loop.sh — one ralph run for a node.
# Reads PROMPT.md + BANS.md + seed.md + state.md → calls $MODEL_CMD → appends to state.md
# → invokes judge.sh → loops until done or hard cap.
#
# Usage: loop.sh <node-name> <seed-file> [run-id-override]
# Env: MODEL_CMD (default: claude -p), HARD_CAP (default from node or 12), DONE_THRESHOLD (default 0.9)

set -euo pipefail

NODE="${1:?node name required}"
SEED_FILE="${2:?seed file required}"
RUN_ID="${3:-${NODE}-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_DIR="$REPO_ROOT/nodes/$NODE"
RUN_DIR="$REPO_ROOT/runs/$NODE/$RUN_ID"

[ -d "$NODE_DIR" ] || { echo "loop.sh: node not found: $NODE_DIR" >&2; exit 2; }
[ -f "$NODE_DIR/PROMPT.md" ] || { echo "loop.sh: PROMPT.md missing" >&2; exit 2; }
[ -f "$NODE_DIR/judge.sh" ] || { echo "loop.sh: judge.sh missing" >&2; exit 2; }

MODEL_CMD="${MODEL_CMD:-claude -p}"
HARD_CAP="${HARD_CAP:-$(cat "$NODE_DIR/hard-cap.txt" 2>/dev/null || echo 12)}"
DONE_THRESHOLD="${DONE_THRESHOLD:-0.9}"

mkdir -p "$RUN_DIR"
cp "$SEED_FILE" "$RUN_DIR/seed.md"
: > "$RUN_DIR/state.md"
: > "$RUN_DIR/events.jsonl"

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
emit_event() {
  printf '{"ts":"%s","run_id":"%s","node":"%s","round":%d,%s}\n' \
    "$(iso_now)" "$RUN_ID" "$NODE" "$1" "$2" >> "$RUN_DIR/events.jsonl"
}

round=0
final_status="hard_cap"
exit_reason="reached hard cap of $HARD_CAP rounds"
final_score=""

while [ "$round" -lt "$HARD_CAP" ]; do
  round=$((round + 1))

  prompt_file="$RUN_DIR/.prompt-$round.txt"
  {
    cat "$NODE_DIR/PROMPT.md"
    echo
    echo "## Accumulated lessons (BANS.md)"
    cat "$NODE_DIR/BANS.md" 2>/dev/null || echo "(none yet)"
    echo
    echo "## Seed (locked input)"
    cat "$RUN_DIR/seed.md"
    echo
    echo "## State so far (round $round)"
    cat "$RUN_DIR/state.md"
  } > "$prompt_file"

  output="$(NODE_NAME="$NODE" RUN_ID="$RUN_ID" ROUND="$round" \
            BANS_FILE="$NODE_DIR/BANS.md" SEED_FILE="$RUN_DIR/seed.md" \
            $MODEL_CMD < "$prompt_file")"
  rm -f "$prompt_file"

  printf '\n--- round %d ---\n%s\n' "$round" "$output" >> "$RUN_DIR/state.md"
  esc_out=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  emit_event "$round" "\"type\":\"agent_output\",\"output\":$esc_out"

  bash "$NODE_DIR/judge.sh" "$RUN_DIR" "$round" || {
    final_status="failed"; exit_reason="judge.sh exited nonzero"; break
  }

  last_judge=$(grep -E '"type"[[:space:]]*:[[:space:]]*"judge_result"' "$RUN_DIR/events.jsonl" | tail -1)
  score=$(printf '%s' "$last_judge" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("score",0))')
  done_flag=$(printf '%s' "$last_judge" | python3 -c 'import json,sys; e=json.loads(sys.stdin.read()); print("true" if e.get("score",0)>='"$DONE_THRESHOLD"' and not e.get("violations") else "false")')

  emit_event "$round" "\"type\":\"ralph_iter_end\",\"done\":$done_flag,\"reason\":\"judge_score=$score\""

  if [ "$done_flag" = "true" ]; then
    final_status="passed"; exit_reason="judge_score=$score >= $DONE_THRESHOLD"; final_score="$score"; break
  fi
  final_score="$score"

  if printf '%s' "$output" | grep -q '^BLOCKED:'; then
    final_status="aborted"; exit_reason="model emitted BLOCKED"; break
  fi
done

violations_aggregate=$(grep -E '"type"[[:space:]]*:[[:space:]]*"judge_result"' "$RUN_DIR/events.jsonl" \
  | python3 -c '
import json, sys
agg = {}
for line in sys.stdin:
    try: e = json.loads(line)
    except: continue
    for v in e.get("violations", []):
        agg[v] = agg.get(v, 0) + 1
print(json.dumps(agg))
')

cat > "$RUN_DIR/outcome.json" <<EOF
{
  "run_id": "$RUN_ID",
  "node": "$NODE",
  "status": "$final_status",
  "rounds": $round,
  "final_score": ${final_score:-null},
  "exit_reason": "$exit_reason",
  "violations_total": $violations_aggregate
}
EOF

echo "$RUN_DIR"
