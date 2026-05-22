#!/usr/bin/env bash
# deeper judge — reads tree.json, decides done vs. continue, emits judge_result event.
# Score = closed_leaves / total_leaves. Done when no open leaves remain.
# Violations: leaves that are too shallow (depth < 2) get tagged "shallow-bedrock" so
# future runs' feedback can promote that lesson into BANS.md if it recurs.

set -euo pipefail

RUN_DIR="${1:?run-dir required}"
ROUND="${2:?round required}"
TREE="$RUN_DIR/tree.json"
EVENTS="$RUN_DIR/events.jsonl"

if [ ! -f "$TREE" ]; then
  # First-round case before model has run? Treat as continue.
  printf '{"ts":"%s","run_id":"%s","node":"deeper","round":%d,"type":"judge_result","score":0,"violations":[],"detail":{"reason":"no tree yet"}}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(basename "$RUN_DIR")" "$ROUND" >> "$EVENTS"
  exit 0
fi

python3 - <<PYEOF >> "$EVENTS"
import json, sys, time

tree = json.load(open("$TREE"))

violations = []
total_leaves = 0
closed_leaves = 0
max_depth = 0

def visit(node, depth):
    global total_leaves, closed_leaves, max_depth
    max_depth = max(max_depth, depth)
    if not node["children"]:
        total_leaves += 1
        if node.get("bedrock") is not None:
            closed_leaves += 1
            if depth < 2:
                violations.append("shallow-bedrock")
        return
    for c in node["children"]:
        visit(c, depth + 1)

visit(tree["root"], 0)

cursor_done = tree.get("cursor") is None
done = cursor_done and closed_leaves == total_leaves and total_leaves > 0
score = round(closed_leaves / total_leaves, 3) if total_leaves else 0

event = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "run_id": "$(basename "$RUN_DIR")",
    "node": "deeper",
    "round": $ROUND,
    "type": "judge_result",
    "score": 1.0 if done else score,
    "violations": violations,
    "detail": {
        "total_leaves": total_leaves,
        "closed_leaves": closed_leaves,
        "max_depth": max_depth,
        "cursor": tree.get("cursor"),
        "done": done,
    },
}
print(json.dumps(event, separators=(",", ":")))
PYEOF
