#!/usr/bin/env bash
# meta-loop.sh — the (ralph -> feedback -> ralph -> feedback) loop.
#
# Runs N ralph runs in series, executing feedback.sh after each (or every K runs),
# so accumulated lessons influence subsequent runs.
#
# Usage: meta-loop.sh <node-name> <seed-file> [<n-runs>] [<feedback-every>]
# Env: forwards MODEL_CMD / HARD_CAP / DONE_THRESHOLD to loop.sh.

set -euo pipefail

NODE="${1:?node name required}"
SEED_FILE="${2:?seed file required}"
N_RUNS="${3:-5}"
FEEDBACK_EVERY="${4:-1}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOOP="$REPO_ROOT/harness/loop.sh"
FEEDBACK="$REPO_ROOT/harness/feedback.sh"

echo "meta-loop: node=$NODE seed=$SEED_FILE n=$N_RUNS feedback_every=$FEEDBACK_EVERY"
echo

for i in $(seq 1 "$N_RUNS"); do
  echo "=== meta-iter $i / $N_RUNS ==="
  RUN_ID="${NODE}-$(date -u +%Y%m%dT%H%M%SZ)-meta$i"
  RUN_DIR=$(bash "$LOOP" "$NODE" "$SEED_FILE" "$RUN_ID")
  outcome=$(cat "$RUN_DIR/outcome.json")
  status=$(printf '%s' "$outcome" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
  rounds=$(printf '%s' "$outcome" | python3 -c 'import json,sys; print(json.load(sys.stdin)["rounds"])')
  score=$(printf '%s' "$outcome" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("final_score"))')
  echo "  -> $status in $rounds rounds (score=$score)"

  if [ $((i % FEEDBACK_EVERY)) -eq 0 ]; then
    echo
    bash "$FEEDBACK" "$NODE"
  fi
  echo
done

echo "meta-loop: done. Final BANS.md:"
echo "-----"
cat "$REPO_ROOT/nodes/$NODE/BANS.md" 2>/dev/null || echo "(empty)"
echo "-----"
