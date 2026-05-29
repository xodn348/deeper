#!/usr/bin/env bash
# deeper judge — emits judge_result event combining tree-shape and question-shape checks.
#
# Tree-shape (always): score = closed_leaves / total_leaves, done = no open leaves.
#   Violation: shallow-bedrock — leaf closed at depth < 2.
#
# Question-shape (when latest question_emitted event for this round is present):
#   compound-conjunction  — question joins sub-questions with `~고`, ` and `, `;`, ` — `, etc.
#   preamble-leak         — subagent emitted >1 non-empty line or >250 chars raw.
#   missing-question-mark — final question doesn't end in `?` / `？`.
#
# This closes the self-improvement loop for question-shape lessons — feedback.sh promotes
# recurring keys to BANS.md the same way it does for tree-shape violations.
#
# Exit codes (let the launcher loop decide done/continue WITHOUT re-reading events.jsonl
# or parsing stdout — guards against any future event-stream/wake race condition):
#   0   → continue: not done, keep looping
#   100 → done: detail.done == true (all leaves closed, cursor==null)
#   1   → internal error (default from set -e)
# The launcher OR's in a separate BLOCKED check from model.py's stdout before judge runs.

set -euo pipefail

RUN_DIR="${1:?run-dir required}"
ROUND="${2:?round required}"
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

# Run the judge into a tmp file first, then append atomically to events.jsonl so we can
# also inspect the JSON to set the exit code. Two-step write avoids partial appends if
# the python block dies mid-write.
python3 - "$RUN_DIR" "$ROUND" >"$TMP_OUT" <<'PYEOF'
import json, re, sys, time, pathlib

run_dir = pathlib.Path(sys.argv[1])
rnd = int(sys.argv[2])
tree_path = run_dir / "tree.json"
events_path = run_dir / "events.jsonl"
run_id = run_dir.name

violations = []
detail = {}
score = 0

# Tree-shape check (skip if tree.json absent — pre-first-round)
if tree_path.exists():
    tree = json.loads(tree_path.read_text())
    total_leaves = closed_leaves = max_depth = 0
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
    score = 1.0 if done else (round(closed_leaves / total_leaves, 3) if total_leaves else 0)
    detail.update({
        "total_leaves": total_leaves,
        "closed_leaves": closed_leaves,
        "max_depth": max_depth,
        "cursor": tree.get("cursor"),
        "done": done,
    })
else:
    detail["reason"] = "no tree yet"

# Question-shape check — find latest question_emitted event for this round
question = None
raw_chars = raw_lines = 0
if events_path.exists():
    for line in events_path.read_text().splitlines():
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("type") == "question_emitted" and e.get("round") == rnd:
            question = e.get("question", "")
            raw_chars = e.get("raw_chars", 0)
            raw_lines = e.get("raw_lines", 0)

if question is not None:
    q = question.strip()
    # preamble-leak: subagent emitted more than one non-empty line, or excessive raw chars
    if raw_lines > 1 or raw_chars > 250:
        violations.append("preamble-leak")
    # compound-conjunction: two sub-questions joined
    compound_patterns = [
        r"고\s+\S+[가이는은를을도]?\s*\S*\s*(뭔가요|인가요|입니까|뭐예요|뭐인가요|무엇입니까|무엇인가요)\s*\?",
        r"\?\s*그리고\s+",
        r"\band\b.+\?.+\?",
        r"[?？][^?？]+[?？]",
        r";\s+\S+.+\?",
        r"\s—\s+\S+.+\?",
    ]
    if any(re.search(p, q) for p in compound_patterns):
        violations.append("compound-conjunction")
    # missing-question-mark
    if q and not re.search(r"[?？]\s*$", q):
        violations.append("missing-question-mark")
    detail["question"] = q
    detail["question_chars"] = len(q)
    detail["raw_chars"] = raw_chars
    detail["raw_lines"] = raw_lines

event = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "run_id": run_id,
    "node": "deeper",
    "round": rnd,
    "type": "judge_result",
    "score": score,
    "violations": violations,
    "detail": detail,
}
print(json.dumps(event, separators=(",", ":")))
PYEOF

# Atomic-ish append: the python block already finished, the file is a single line.
cat "$TMP_OUT" >> "$RUN_DIR/events.jsonl"

# Decide exit code from the emitted event so the launcher never has to re-read state.
DONE=$(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    e = json.loads(f.read())
print("1" if e.get("detail", {}).get("done") else "0")
' "$TMP_OUT")

if [ "$DONE" = "1" ]; then
  exit 100
fi
exit 0
