#!/usr/bin/env bash
# render-dispatch.sh — ASCII view of the subagent dispatch chain for a deeper run.
# Reads events.jsonl, prints one block per round showing the Q-subagent and
# A-subagent calls plus the outcome.
#
# Usage: render-dispatch.sh <run-dir>

set -euo pipefail

RUN_DIR="${1:?run-dir required}"
EVENTS="$RUN_DIR/events.jsonl"
SEED="$RUN_DIR/seed.md"

[ -f "$EVENTS" ] || { echo "(no events.jsonl yet)"; exit 0; }

python3 - "$RUN_DIR" <<'PYEOF'
import json, sys, pathlib, re, textwrap

run_dir = pathlib.Path(sys.argv[1])
events = (run_dir / "events.jsonl").read_text().splitlines()
seed = ""
seed_path = run_dir / "seed.md"
if seed_path.exists():
    for line in seed_path.read_text().splitlines():
        if line and not line.startswith("#"):
            seed = line.strip()
            break

mode_path = run_dir / ".mode"
mode = mode_path.read_text().strip() if mode_path.exists() else "interactive"

rounds = {}
for line in events:
    try:
        e = json.loads(line)
    except Exception:
        continue
    r = e.get("round")
    if r is None:
        continue
    rounds.setdefault(r, {"question": None, "answer": None, "judge": None, "outcome": None})
    t = e.get("type")
    if t == "question_emitted":
        rounds[r]["question"] = e
    elif t == "answer_emitted":
        rounds[r]["answer"] = e
    elif t == "judge_result":
        rounds[r]["judge"] = e

def shorten(s, n=90):
    s = (s or "").replace("\n", " ").strip()
    return s if len(s) <= n else s[:n-1] + "…"

print()
print(f"deeper run: {run_dir.name}  [mode={mode}]")
print(f"seed: {shorten(seed, 100)}")
print()

ordered = sorted(rounds.keys())
for i, r in enumerate(ordered):
    is_last = (i == len(ordered) - 1)
    trunk = "└─" if is_last else "├─"
    pipe = "  " if is_last else "│ "
    block = rounds[r]
    print(f"{trunk} R{r}")
    q = block["question"]
    if q:
        print(f"{pipe}   [Q] claude -p (haiku)")
        print(f"{pipe}       → {shorten(q.get('question'), 110)}")
    a = block["answer"]
    if a:
        src = a.get("source", "?")
        label = {
            "subprocess": "claude -p (sonnet)",
            "subprocess-opus-retry": "claude -p (opus retry)",
            "subagent": "Explore subagent (legacy)",
            "subagent-opus-retry": "Explore subagent opus retry (legacy)",
            "stall-stop-sentinel": "stall STOP",
        }.get(src, "user")
        print(f"{pipe}   [A] {label}")
        print(f"{pipe}       → {shorten(a.get('answer'), 110)}")
    j = block["judge"]
    if j:
        viols = j.get("violations", []) or []
        det = j.get("detail", {}) or {}
        cursor = det.get("cursor")
        depth = det.get("max_depth")
        score = j.get("score")
        v_str = (" violations=" + ",".join(viols)) if viols else ""
        print(f"{pipe}   [judge] score={score} depth={depth} cursor={cursor}{v_str}")
    if not is_last:
        print(pipe)

print()
PYEOF
