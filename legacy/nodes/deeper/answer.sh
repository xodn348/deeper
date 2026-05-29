#!/usr/bin/env bash
# answer.sh — A-driver for deeper. Runs one `claude -p` invocation that uses
# the Agent tool to fan out 5 parallel investigator subagents, monitors them
# against a deadline, force-kills stragglers, and synthesizes the survivors'
# outputs into one answer (Aₖ).
#
# Usage:
#   answer.sh <ancestors-file> <question-file> <run-dir> <round>
#
# Output:
#   stdout  — the synthesis text (one logical answer; may span multiple lines).
#             OR `BLOCKED: …` if the driver could not produce a synthesis.
#   <run-dir>/answer-r<round>.json — verbatim JSON envelope from the driver.
#   <run-dir>/improvements.md      — appended-to when angles are force-killed.
#   nodes/deeper/IMPROVEMENTS.md   — global accumulator (same content appended).
#
# Env:
#   DEEPER_ANSWER_MODEL    driver model            (default: opus)
#   DEEPER_SUB_MODEL       investigator model      (default: opus)
#   DEEPER_SUB_DEADLINE    per-subagent deadline s (default: 180)
#   DEEPER_FANOUT          investigator count      (default: 5)
#   DEEPER_KILL_THRESHOLD  ≥ N force-kills → BLOCKED (default: 3)
#   DEEPER_ANSWER_MOCK     if set, used verbatim as the JSON envelope and the
#                          real `claude -p` call is skipped — for tests.

set -euo pipefail

if [[ $# -ne 4 ]]; then
  printf 'answer.sh: expected 4 args (ancestors question run-dir round), got %d\n' "$#" >&2
  exit 2
fi

ANCESTORS_FILE="$1"
QUESTION_FILE="$2"
RUN_DIR="$3"
ROUND="$4"

[[ -r "$ANCESTORS_FILE" ]] || { echo "answer.sh: ancestors not readable: $ANCESTORS_FILE" >&2; exit 2; }
[[ -r "$QUESTION_FILE"  ]] || { echo "answer.sh: question not readable: $QUESTION_FILE"   >&2; exit 2; }
[[ -d "$RUN_DIR"        ]] || { echo "answer.sh: run-dir missing: $RUN_DIR"               >&2; exit 2; }
[[ "$ROUND" =~ ^[0-9]+$ ]] || { echo "answer.sh: round must be integer, got: $ROUND"      >&2; exit 2; }

DRIVER_MODEL="${DEEPER_ANSWER_MODEL:-opus}"
SUB_MODEL="${DEEPER_SUB_MODEL:-opus}"
DEADLINE="${DEEPER_SUB_DEADLINE:-180}"
FANOUT="${DEEPER_FANOUT:-5}"
KILL_THRESHOLD="${DEEPER_KILL_THRESHOLD:-3}"

NODE_DIR="$(cd "$(dirname "$0")" && pwd)"
SYS_FILE="$NODE_DIR/PROMPT.answer.md"
[[ -r "$SYS_FILE" ]] || { echo "answer.sh: PROMPT.answer.md missing: $SYS_FILE" >&2; exit 2; }

# Tests redirect the global accumulator with DEEPER_GLOBAL_IMPROVEMENTS so they
# do not pollute the in-repo file.
GLOBAL_IMPROVEMENTS="${DEEPER_GLOBAL_IMPROVEMENTS:-$NODE_DIR/IMPROVEMENTS.md}"
RUN_IMPROVEMENTS="$RUN_DIR/improvements.md"
ENVELOPE_OUT="$RUN_DIR/answer-r${ROUND}.json"

if [[ ! -f "$RUN_IMPROVEMENTS" ]]; then
  printf '# Run-scoped improvements — %s\n\n' "$(basename "$RUN_DIR")" > "$RUN_IMPROVEMENTS"
fi
if [[ ! -f "$GLOBAL_IMPROVEMENTS" ]]; then
  printf '# deeper IMPROVEMENTS — aggregated across runs\n\n' > "$GLOBAL_IMPROVEMENTS"
fi

USER_FILE="$(mktemp -t deeper-answer-user.XXXXXX)"
trap 'rm -f "$USER_FILE"' EXIT

{
  echo "## ACTIVE QUESTION"
  cat "$QUESTION_FILE"
  echo
  echo "## ANCESTOR CHAIN"
  cat "$ANCESTORS_FILE"
  echo
  echo "## RUN_DIR: $RUN_DIR"
  echo "## ROUND: $ROUND"
  echo "## DEADLINE_SECONDS: $DEADLINE"
  echo "## SUB_MODEL: $SUB_MODEL"
  echo "## FANOUT: $FANOUT"
} > "$USER_FILE"

if [[ -n "${DEEPER_ANSWER_MOCK:-}" ]]; then
  ENVELOPE="$DEEPER_ANSWER_MOCK"
else
  ENVELOPE="$(claude -p \
    --no-session-persistence \
    --disable-slash-commands \
    --tools "Agent,Monitor,TaskGet,TaskList,TaskOutput,TaskStop" \
    --model "$DRIVER_MODEL" \
    --system-prompt "$(cat "$SYS_FILE")" \
    "$(cat "$USER_FILE")" </dev/null)"
fi

printf '%s\n' "$ENVELOPE" > "$ENVELOPE_OUT"

python3 - "$ENVELOPE_OUT" "$RUN_IMPROVEMENTS" "$GLOBAL_IMPROVEMENTS" "$RUN_DIR" "$ROUND" "$KILL_THRESHOLD" <<'PYEOF'
import json, sys, pathlib, time

envelope_path, run_imp_path, glob_imp_path, run_dir, rnd, kill_threshold = sys.argv[1:]
rnd = int(rnd)
kill_threshold = int(kill_threshold)

text = pathlib.Path(envelope_path).read_text().strip()
if text.startswith("```"):
    text = text.strip("`")
    if text.lower().startswith("json"):
        text = text[4:]
    text = text.strip()

try:
    env = json.loads(text)
except json.JSONDecodeError as e:
    sys.stderr.write(f"answer.sh: envelope is not JSON: {e}\n--- envelope ---\n{text}\n")
    sys.exit(3)

synthesis    = env.get("synthesis", "") or ""
force_killed = env.get("force_killed", []) or []
blocked      = bool(env.get("blocked", False))

if force_killed:
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    lines = [f"\n## {pathlib.Path(run_dir).name} · round {rnd} · {ts}"]
    for fk in force_killed:
        angle   = fk.get("angle", "?")
        reason  = fk.get("reason", "unknown")
        ltool   = fk.get("last_tool", "")
        snippet = (fk.get("snippet") or "").replace("\n", " ")
        lines.append(f"- angle `{angle}` · reason `{reason}` · last_tool `{ltool}` · snippet: {snippet}")
    chunk = "\n".join(lines) + "\n"
    for p in (run_imp_path, glob_imp_path):
        with open(p, "a") as f:
            f.write(chunk)

if blocked or len(force_killed) >= kill_threshold:
    print(f"BLOCKED: {len(force_killed)} angle(s) force-killed (threshold={kill_threshold})")
    sys.exit(0)

if not synthesis.strip():
    print("BLOCKED: empty synthesis")
    sys.exit(0)

print(synthesis)
PYEOF
