#!/usr/bin/env bash
# deeper e2e validator — runs the SKILL.md round-handler protocol directly
# (no launcher tool calls). Stops after N_CAP rounds or judge done.
set -euo pipefail

DEEPER="${DEEPER:-$HOME/code/deeper}"
RUN_ID="deeper-e2e-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$DEEPER/runs/deeper/$RUN_ID"
N_CAP="${N_CAP:-3}"
SEED="${SEED:-Python의 GIL은 멀티스레딩 성능을 제한한다}"

mkdir -p "$RUN_DIR"
printf '# Starting claim\n\n%s\n' "$SEED" > "$RUN_DIR/seed.md"
: > "$RUN_DIR/state.md"
: > "$RUN_DIR/events.jsonl"
echo "auto" > "$RUN_DIR/.mode"

emit_event() {  # arg1 = body json
  RUN_ID="$RUN_ID" BODY="$1" python3 - <<'PY' >> "$RUN_DIR/events.jsonl"
import json, os, time
ev = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
      "run_id": os.environ["RUN_ID"], "node": "deeper"}
ev.update(json.loads(os.environ["BODY"]))
print(json.dumps(ev, separators=(",", ":")))
PY
}

build_ancestor_chain() {  # round-N — uses tree.json if present
  if [[ -f "$RUN_DIR/tree.json" ]]; then
    python3 - "$RUN_DIR" <<'PY'
import json, sys, pathlib
t = json.loads((pathlib.Path(sys.argv[1])/'tree.json').read_text())
root = t['root']
cursor = t.get('cursor')

def find(node, target, trail):
    trail.append(node)
    if node.get('id') == target:
        return list(trail)
    for c in node.get('children', []):
        r = find(c, target, trail)
        if r: return r
    trail.pop()
    return None

if cursor:
    chain = find(root, cursor, []) or [root]
else:
    chain = [root]
for i, n in enumerate(chain, 1):
    print(f"{i}. {n.get('claim','')}")
PY
  else
    echo "1. $SEED"
  fi
}

active_claim() {
  if [[ -f "$RUN_DIR/tree.json" ]]; then
    python3 - "$RUN_DIR" <<'PY'
import json, sys, pathlib
t = json.loads((pathlib.Path(sys.argv[1])/'tree.json').read_text())
cursor = t.get('cursor')
root = t['root']
def find(node, target):
    if node.get('id') == target: return node
    for c in node.get('children', []):
        r = find(c, target)
        if r: return r
    return None
node = find(root, cursor) if cursor else root
print(node.get('claim', '') if node else '')
PY
  else
    echo "$SEED"
  fi
}

echo "=== e2e run: $RUN_ID (cap=$N_CAP) ==="
echo "Seed: $SEED"

for ((N=1; N<=N_CAP; N++)); do
  echo
  echo "--- round $N ---"
  T_ROUND_START=$(date +%s)
  ACTIVE_CLAIM=$(active_claim)
  ANCESTOR_CHAIN=$(build_ancestor_chain)
  echo "active claim: $ACTIVE_CLAIM"

  # ----- Q -----
  Q_SYS="$RUN_DIR/.q-sys-$N.txt"
  Q_USER="$RUN_DIR/.q-user-$N.txt"
  Q_RAW="$RUN_DIR/.q-raw-$N.txt"

  {
    echo "ROLE: deeper-Q-round-$N. Output exactly ONE depth question — no preamble, no \"Question:\", nothing else."
    echo
    cat "$DEEPER/nodes/deeper/PROMPT.md"
    echo
    echo "BINDING LESSONS (may be empty):"
    cat "$DEEPER/nodes/deeper/BANS.md" 2>/dev/null || true
    echo
    echo "HARD GUARDS (binary self-check before you emit):"
    echo "G1 one non-empty line · G2 no forbidden first tokens · G3 language matches ACTIVE CLAIM ·"
    echo "G4 exactly one \"?\", no conjunction joiners · G5 not a restatement of the claim ·"
    echo "G6 stay on the active claim · G7 no breadth-extension framing."
  } > "$Q_SYS"
  {
    echo "ANCESTOR CHAIN:"
    printf '%s\n' "$ANCESTOR_CHAIN"
    echo
    echo "ACTIVE CLAIM to drill: \"$ACTIVE_CLAIM\""
    echo
    echo "Output exactly ONE line: the depth question."
  } > "$Q_USER"

  T0=$(date +%s)
  bash "$DEEPER/nodes/deeper/ask.sh" haiku "$Q_SYS" "$Q_USER" > "$Q_RAW"
  T1=$(date +%s)
  Q_LATENCY=$((T1-T0))
  Q_LINE=$(tail -n 1 "$Q_RAW" | sed 's/[[:space:]]*$//')
  RAW_CHARS=$(wc -c < "$Q_RAW" | tr -d ' ')
  RAW_LINES=$(grep -c . "$Q_RAW" || true)
  Q_EVENT=$(N=$N Q_LINE="$Q_LINE" RAW_CHARS=$RAW_CHARS RAW_LINES=$RAW_LINES Q_LATENCY=$Q_LATENCY \
    python3 -c 'import json,os; print(json.dumps({"round":int(os.environ["N"]),"type":"question_emitted","question":os.environ["Q_LINE"],"raw_chars":int(os.environ["RAW_CHARS"]),"raw_lines":int(os.environ["RAW_LINES"]),"latency_s":int(os.environ["Q_LATENCY"])}))')
  emit_event "$Q_EVENT"
  echo "[R$N Q ${Q_LATENCY}s] $Q_LINE"

  # ----- A -----
  A_SYS="$RUN_DIR/.a-sys-$N.txt"
  A_USER="$RUN_DIR/.a-user-$N.txt"
  A_RAW="$RUN_DIR/.a-raw-$N.txt"

  {
    echo "ROLE: deeper-A-round-$N. The interview is autonomous — you stand in for the human respondent."
    echo
    echo "HARD GUARDS for your answer (binary self-check before emit):"
    echo "- A1: Your response is EXACTLY ONE of: (a) 1–3 sentence free-text answer (NO BEDROCK:/BRANCH: prefix), (b) a single line starting BEDROCK:, (c) a single line starting BRANCH:. Mixed forms = fail."
    echo "- A2: Forbidden first tokens: Sure, Here, OK, Answer, A:, 먼저, 우선, 답, 답변, 이."
    echo "- A3: Language match — Hangul in ACTIVE CLAIM → Hangul in your answer."
    echo "- A4: If you emit BEDROCK:<cat>, <cat> MUST be EXACTLY one of: stated-value | constraint | prior-decision | external-rule | identity | empirical."
    echo "- A5: Honest uncertainty — if you don't know a fact, say \"I don't know X\" concretely. No hedge-filler."
    echo
    echo "If your draft fails any guard, REWRITE before emitting."
  } > "$A_SYS"
  {
    echo "ANCESTOR CHAIN:"
    printf '%s\n' "$ANCESTOR_CHAIN"
    echo
    echo "ACTIVE CLAIM: \"$ACTIVE_CLAIM\""
    echo "QUESTION TO ANSWER: \"$Q_LINE\""
    echo
    echo "Output exactly one response, one of:"
    echo "  (a) free-text answer (1–3 sentences) drilling deeper. Concrete, specific."
    echo "  (b) BEDROCK:<category> if this active claim IS an axiom."
    echo "  (c) BRANCH:<sibling claim> if a parallel cause under the same parent is worth opening."
    echo
    echo "No preamble. No \"Answer:\". No reasoning about which option you picked."
  } > "$A_USER"

  T0=$(date +%s)
  bash "$DEEPER/nodes/deeper/ask.sh" sonnet "$A_SYS" "$A_USER" > "$A_RAW"
  T1=$(date +%s)
  A_LATENCY=$((T1-T0))
  A_TEXT=$(cat "$A_RAW")
  A_EVENT=$(N=$N A_TEXT="$A_TEXT" A_LATENCY=$A_LATENCY \
    python3 -c 'import json,os; print(json.dumps({"round":int(os.environ["N"]),"type":"answer_emitted","answer":os.environ["A_TEXT"][:500],"source":"subprocess","latency_s":int(os.environ["A_LATENCY"])}))')
  emit_event "$A_EVENT"
  echo "[R$N A ${A_LATENCY}s] $(echo "$A_TEXT" | head -c 200)..."

  # ----- model.py -----
  MODEL_OUT=$(DEEPER_ANSWER_FILE="$A_RAW" SEED_FILE="$RUN_DIR/seed.md" ROUND=$N \
    python3 "$DEEPER/nodes/deeper/model.py")
  MODEL_BLOCKED=0
  case "$MODEL_OUT" in BLOCKED:*) MODEL_BLOCKED=1 ;; esac
  printf '\n--- round %d ---\n%s\n' "$N" "$MODEL_OUT" >> "$RUN_DIR/state.md"
  echo "[R$N model] $MODEL_OUT"

  if [[ $MODEL_BLOCKED -eq 1 ]]; then
    echo "BLOCKED — stopping."
    break
  fi

  # ----- judge.sh -----
  JUDGE_EXIT=0
  bash "$DEEPER/nodes/deeper/judge.sh" "$RUN_DIR" "$N" || JUDGE_EXIT=$?
  T_ROUND_END=$(date +%s)
  ROUND_LATENCY=$((T_ROUND_END-T_ROUND_START))
  echo "[R$N judge] exit=$JUDGE_EXIT (round wall-clock: ${ROUND_LATENCY}s)"

  if [[ $JUDGE_EXIT -eq 100 ]]; then
    echo "judge says DONE — drill complete."
    break
  elif [[ $JUDGE_EXIT -ne 0 ]]; then
    echo "judge error — aborting."
    break
  fi
done

echo
echo "=== run dir: $RUN_DIR ==="
echo "=== events.jsonl ==="
cat "$RUN_DIR/events.jsonl"
echo
echo "=== render ==="
bash "$DEEPER/nodes/deeper/render.sh" "$RUN_DIR" 2>&1 || true
echo
echo "=== render-dispatch ==="
bash "$DEEPER/nodes/deeper/render-dispatch.sh" "$RUN_DIR" 2>&1 || true
