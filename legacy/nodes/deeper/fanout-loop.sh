#!/usr/bin/env bash
# fanout-loop.sh — end-to-end Q→A drill for deeper using the fanout A-driver.
#
# Per round:
#   1. ask.sh emits Qₖ (one line, haiku by default).
#   2. answer.sh runs the 5-investigator fanout and synthesises Aₖ.
#   3. Q/A pair appended to ancestors.md, state.md, events.jsonl.
#   4. Loop terminates on STOP / BEDROCK: in Aₖ, on two consecutive BLOCKED
#      rounds, or when HARD_CAP is reached.
#
# Usage:
#   fanout-loop.sh <seed-file> [run-id]
#
# Output:
#   $DEEPER_HOME/runs/deeper/<run-id>/ (default ~/.deeper/runs/deeper/<run-id>/)  — populated run directory.
#   Path printed to stdout on exit.
#
# Env:
#   DEEPER_Q_MODEL          Q-subagent model      (default: haiku)
#   DEEPER_ANSWER_MODEL     A-driver model        (default: opus)
#   DEEPER_SUB_MODEL        investigator model    (default: opus)
#   DEEPER_SUB_DEADLINE     per-subagent seconds  (default: 180)
#   DEEPER_FANOUT           investigator count    (default: 5)
#   DEEPER_KILL_THRESHOLD   force-kill threshold  (default: 3)
#   DEEPER_HARD_CAP         max rounds            (default: 12)
#   DEEPER_ASK_MOCK         if set, ask.sh emits this verbatim each round
#   DEEPER_ANSWER_MOCK      if set, answer.sh emits this verbatim each round
#   DEEPER_GLOBAL_IMPROVEMENTS   override global accumulator path

set -euo pipefail

SEED_FILE="${1:?seed file required}"
RUN_ID="${2:-deeper-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

[ -r "$SEED_FILE" ] || { echo "fanout-loop.sh: seed not readable: $SEED_FILE" >&2; exit 2; }

NODE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$NODE_DIR/../.." && pwd)"
DEEPER_HOME="${DEEPER_HOME:-$HOME/.deeper}"
RUN_DIR="$DEEPER_HOME/runs/deeper/$RUN_ID"

ASK_SH="$NODE_DIR/ask.sh"
ANSWER_SH="$NODE_DIR/answer.sh"
PROMPT_Q="$NODE_DIR/PROMPT.md"
BANS_FILE="$NODE_DIR/BANS.md"

[ -x "$ASK_SH"    ] || { echo "fanout-loop.sh: ask.sh missing/not exec: $ASK_SH"       >&2; exit 2; }
[ -x "$ANSWER_SH" ] || { echo "fanout-loop.sh: answer.sh missing/not exec: $ANSWER_SH" >&2; exit 2; }
[ -r "$PROMPT_Q"  ] || { echo "fanout-loop.sh: PROMPT.md missing: $PROMPT_Q"           >&2; exit 2; }

Q_MODEL="${DEEPER_Q_MODEL:-haiku}"
HARD_CAP="${DEEPER_HARD_CAP:-12}"

mkdir -p "$RUN_DIR"
cp "$SEED_FILE" "$RUN_DIR/seed.md"
ANCESTORS="$RUN_DIR/ancestors.md"
STATE="$RUN_DIR/state.md"
EVENTS="$RUN_DIR/events.jsonl"
: > "$ANCESTORS"
: > "$STATE"
: > "$EVENTS"

{
  echo "## Root claim"
  cat "$SEED_FILE"
  echo
} > "$ANCESTORS"

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

emit_event() {
  # $1 = round, $2 = JSON payload object (no run_id/ts/round keys)
  python3 -c '
import json, sys
ts, run_id, rnd, payload_str = sys.argv[1:]
payload = json.loads(payload_str)
event = {"ts": ts, "run_id": run_id, "node": "deeper", "round": int(rnd)}
event.update(payload)
print(json.dumps(event, separators=(",",":")))
' "$(iso_now)" "$RUN_ID" "$1" "$2" >> "$EVENTS"
}

json_str() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

prev_blocked=false
final_status="hard_cap"
exit_reason="reached hard cap of $HARD_CAP rounds"
LAST_A=""
last_round=0

for ((round=1; round<=HARD_CAP; round++)); do
  last_round=$round
  emit_event "$round" "$(printf '{"type":"round_start"}')"

  # ---- Q-phase ----
  SYS_FILE_TMP="$(mktemp -t deeper-q-sys.XXXXXX)"
  USER_FILE_TMP="$(mktemp -t deeper-q-user.XXXXXX)"

  {
    cat "$PROMPT_Q"
    echo
    echo "## Accumulated lessons (BANS.md)"
    if [ -s "$BANS_FILE" ]; then cat "$BANS_FILE"; else echo "(none yet)"; fi
  } > "$SYS_FILE_TMP"

  if [ "$round" -eq 1 ]; then
    ACTIVE_CLAIM="$(cat "$SEED_FILE")"
  else
    ACTIVE_CLAIM="$LAST_A"
  fi

  {
    echo "## ACTIVE CLAIM"
    printf '%s\n' "$ACTIVE_CLAIM"
    echo
    echo "## ANCESTOR CHAIN"
    cat "$ANCESTORS"
  } > "$USER_FILE_TMP"

  if Q="$(bash "$ASK_SH" "$Q_MODEL" "$SYS_FILE_TMP" "$USER_FILE_TMP")"; then :; else
    final_status="failed"
    exit_reason="ask.sh failed on round $round"
    emit_event "$round" "$(printf '{"type":"loop_aborted","reason":"ask_failed"}')"
    rm -f "$SYS_FILE_TMP" "$USER_FILE_TMP"
    break
  fi
  rm -f "$SYS_FILE_TMP" "$USER_FILE_TMP"

  # Sanitize Q to one line (defensive — PROMPT.md already mandates this).
  Q_FIRST_LINE="$(printf '%s' "$Q" | awk 'NF{print; exit}')"
  Q="${Q_FIRST_LINE:-$Q}"

  Q_FILE="$RUN_DIR/q-r${round}.txt"
  printf '%s\n' "$Q" > "$Q_FILE"

  q_chars=${#Q}
  q_lines=1
  emit_event "$round" "$(printf '{"type":"question_emitted","question":%s,"raw_chars":%d,"raw_lines":%d}' \
                          "$(json_str "$Q")" "$q_chars" "$q_lines")"

  # ---- A-phase ----
  if A="$(bash "$ANSWER_SH" "$ANCESTORS" "$Q_FILE" "$RUN_DIR" "$round")"; then :; else
    final_status="failed"
    exit_reason="answer.sh failed on round $round"
    emit_event "$round" "$(printf '{"type":"loop_aborted","reason":"answer_failed"}')"
    break
  fi

  A_FIRST_LINE="$(printf '%s' "$A" | awk 'NF{print; exit}')"
  if [[ "$A_FIRST_LINE" == BLOCKED:* ]]; then
    source_label="fanout-blocked"
  else
    source_label="fanout"
  fi

  A_FILE="$RUN_DIR/a-r${round}.txt"
  printf '%s\n' "$A" > "$A_FILE"

  emit_event "$round" "$(printf '{"type":"answer_emitted","answer":%s,"source":"%s"}' \
                          "$(json_str "$A")" "$source_label")"

  # Fanout-detail events from the JSON envelope.
  ENVELOPE="$RUN_DIR/answer-r${round}.json"
  if [ -f "$ENVELOPE" ]; then
    python3 - "$ENVELOPE" "$round" "$RUN_ID" "$EVENTS" <<'PYEOF'
import json, sys, pathlib, time
env_path, rnd, run_id, events_path = sys.argv[1:]
try:
    env = json.loads(pathlib.Path(env_path).read_text())
except Exception:
    sys.exit(0)
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
out = []
for angle in env.get("completed", []) or []:
    out.append({"ts":ts,"run_id":run_id,"node":"deeper","round":int(rnd),
                "type":"subagent_completed","angle":angle})
for fk in env.get("force_killed", []) or []:
    out.append({"ts":ts,"run_id":run_id,"node":"deeper","round":int(rnd),
                "type":"subagent_force_killed",
                "angle":fk.get("angle","?"),
                "reason":fk.get("reason","unknown"),
                "last_tool":fk.get("last_tool",""),
                "snippet":(fk.get("snippet") or "")[:200]})
with open(events_path, "a") as f:
    for e in out:
        f.write(json.dumps(e, separators=(",",":")) + "\n")
PYEOF
  fi

  {
    echo "## Q${round}: $Q"
    echo
    echo "## A${round}:"
    printf '%s\n' "$A"
    echo
  } >> "$ANCESTORS"

  {
    echo "--- round $round ---"
    echo "Q: $Q"
    echo "A: $A"
    echo
  } >> "$STATE"

  LAST_A="$A"

  # Termination conditions.
  if [[ "$A_FIRST_LINE" == BLOCKED:* ]]; then
    if $prev_blocked; then
      final_status="failed"
      exit_reason="two consecutive BLOCKED rounds"
      emit_event "$round" "$(printf '{"type":"loop_aborted","reason":"two_blocked"}')"
      break
    fi
    prev_blocked=true
  else
    prev_blocked=false
  fi

  if printf '%s' "$A" | grep -Eq '^(STOP|BEDROCK:)'; then
    final_status="passed"
    exit_reason="terminal token in answer (STOP/BEDROCK)"
    emit_event "$round" "$(printf '{"type":"loop_done","reason":"terminal_token"}')"
    break
  fi
done

ROUNDS_ACTUAL=$last_round

python3 -c '
import json, sys
out = {
  "run_id": sys.argv[1],
  "node":   "deeper",
  "status": sys.argv[2],
  "rounds": int(sys.argv[3]),
  "exit_reason": sys.argv[4],
}
print(json.dumps(out, indent=2))
' "$RUN_ID" "$final_status" "$ROUNDS_ACTUAL" "$exit_reason" > "$RUN_DIR/outcome.json"

echo "$RUN_DIR"
