#!/usr/bin/env bash
# test-fanout-loop-mock.sh — exercise fanout-loop.sh end-to-end with mock
# Q and A responses. No LLM, no tokens. Verifies wiring of ask.sh, answer.sh,
# the per-round events.jsonl, the run-scoped improvements log, and the four
# loop termination paths (BEDROCK, hard_cap, single BLOCKED, two-blocked fail).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FANOUT_SH="$REPO_ROOT/nodes/deeper/fanout-loop.sh"
[[ -x "$FANOUT_SH" ]] || { echo "fanout-loop.sh not executable: $FANOUT_SH" >&2; exit 2; }

TMPROOT="$(mktemp -d -t deeper-fanout-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0
failures=()

assert() {
  local label="$1" cond="$2"
  if eval "$cond"; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "$label"
  else
    fail=$((fail + 1))
    failures+=("$label")
    printf '  FAIL %s\n' "$label"
  fi
}

count_events() {
  local file="$1" type="$2"
  python3 -c '
import json,sys
n=0
for line in open(sys.argv[1]):
    try:
        if json.loads(line).get("type")==sys.argv[2]: n+=1
    except: pass
print(n)
' "$file" "$type"
}

outcome_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
}

# Shared seed.
SEED="$TMPROOT/seed.md"
printf 'why does the system keep regressing on the same bug?\n' > "$SEED"

# -----------------------------------------------------------------------------
# Case 1 — BEDROCK terminator: round 1 answer ends the loop early.
# -----------------------------------------------------------------------------
echo "case 1: BEDROCK terminator"
ASK1='which prior decision pinned this behaviour?'
ANSWER1='{
  "synthesis": "BEDROCK: prior-decision. We committed to this schema in 2023 and chose not to revisit.",
  "completed": ["evidence","counterexample","boundary","mechanism","precedent"],
  "force_killed": [],
  "blocked": false,
  "elapsed_seconds": 64
}'
GLOBAL1="$TMPROOT/case1.IMPROVEMENTS.md"
: > "$GLOBAL1"
run_dir1="$(DEEPER_ASK_MOCK="$ASK1" DEEPER_ANSWER_MOCK="$ANSWER1" \
            DEEPER_GLOBAL_IMPROVEMENTS="$GLOBAL1" DEEPER_HARD_CAP=3 \
            "$FANOUT_SH" "$SEED" "case1-run")"
assert "run dir created"          "[ -d '$run_dir1' ]"
assert "outcome status passed"    "[ \"\$(outcome_field '$run_dir1/outcome.json' status)\" = 'passed' ]"
assert "rounds == 1"              "[ \"\$(outcome_field '$run_dir1/outcome.json' rounds)\" = '1' ]"
assert "exit reason terminal"     "grep -q 'terminal_token\|terminal token' '$run_dir1/outcome.json'"
assert "ancestors has Q1"         "grep -q '^## Q1: ' '$run_dir1/ancestors.md'"
assert "ancestors has A1 BEDROCK" "grep -q 'BEDROCK: prior-decision' '$run_dir1/ancestors.md'"
assert "5 subagent_completed events" "[ \"\$(count_events '$run_dir1/events.jsonl' subagent_completed)\" = '5' ]"
assert "no force_kill events"     "[ \"\$(count_events '$run_dir1/events.jsonl' subagent_force_killed)\" = '0' ]"
assert "loop_done event present"  "[ \"\$(count_events '$run_dir1/events.jsonl' loop_done)\" = '1' ]"
assert "global improvements empty" "[ ! -s '$GLOBAL1' ]"

# -----------------------------------------------------------------------------
# Case 2 — partial fanout, no terminator → hard_cap=1, improvements logged.
# -----------------------------------------------------------------------------
echo "case 2: partial fanout, hard_cap=1"
ASK2='what evidence supports this?'
ANSWER2='{
  "synthesis": "Evidence and mechanism converge on incentive lock-in. [angle: boundary — collection failed: tool_loop] [angle: precedent — collection failed: network_timeout]",
  "completed": ["evidence","counterexample","mechanism"],
  "force_killed": [
    {"angle":"boundary","subagent_id":"t1","reason":"tool_loop","last_tool":"WebFetch","snippet":"WebFetch x12"},
    {"angle":"precedent","subagent_id":"t2","reason":"network_timeout","last_tool":"WebSearch","snippet":"dns"}
  ],
  "blocked": false,
  "elapsed_seconds": 188
}'
GLOBAL2="$TMPROOT/case2.IMPROVEMENTS.md"
: > "$GLOBAL2"
run_dir2="$(DEEPER_ASK_MOCK="$ASK2" DEEPER_ANSWER_MOCK="$ANSWER2" \
            DEEPER_GLOBAL_IMPROVEMENTS="$GLOBAL2" DEEPER_HARD_CAP=1 \
            "$FANOUT_SH" "$SEED" "case2-run")"
assert "outcome status hard_cap"     "[ \"\$(outcome_field '$run_dir2/outcome.json' status)\" = 'hard_cap' ]"
assert "rounds == 1"                 "[ \"\$(outcome_field '$run_dir2/outcome.json' rounds)\" = '1' ]"
assert "3 subagent_completed"        "[ \"\$(count_events '$run_dir2/events.jsonl' subagent_completed)\" = '3' ]"
assert "2 subagent_force_killed"     "[ \"\$(count_events '$run_dir2/events.jsonl' subagent_force_killed)\" = '2' ]"
assert "run improvements has 2"      "[ \$(grep -c '^- angle ' '$run_dir2/improvements.md') -eq 2 ]"
assert "global improvements has 2"   "[ \$(grep -c '^- angle ' '$GLOBAL2') -eq 2 ]"
assert "ancestors A inlines failure" "grep -q 'collection failed: tool_loop' '$run_dir2/ancestors.md'"
assert "answer source = fanout"      "grep -q '\"source\":\"fanout\"' '$run_dir2/events.jsonl'"
assert "no loop_done"                "[ \"\$(count_events '$run_dir2/events.jsonl' loop_done)\" = '0' ]"

# -----------------------------------------------------------------------------
# Case 3 — threshold breach, single BLOCKED round, HARD_CAP=1.
# -----------------------------------------------------------------------------
echo "case 3: single BLOCKED round, hard_cap=1"
ASK3='which assumption breaks?'
ANSWER3='{
  "synthesis": "",
  "completed": ["evidence"],
  "force_killed": [
    {"angle":"counterexample","subagent_id":"x1","reason":"context_limit","last_tool":"Read","snippet":"ctx"},
    {"angle":"boundary","subagent_id":"x2","reason":"tool_loop","last_tool":"Grep","snippet":"grep"},
    {"angle":"mechanism","subagent_id":"x3","reason":"ambiguous_task","last_tool":"","snippet":"unclear"},
    {"angle":"precedent","subagent_id":"x4","reason":"network_timeout","last_tool":"WebFetch","snippet":"504"}
  ],
  "blocked": true,
  "elapsed_seconds": 195
}'
GLOBAL3="$TMPROOT/case3.IMPROVEMENTS.md"
: > "$GLOBAL3"
run_dir3="$(DEEPER_ASK_MOCK="$ASK3" DEEPER_ANSWER_MOCK="$ANSWER3" \
            DEEPER_GLOBAL_IMPROVEMENTS="$GLOBAL3" DEEPER_HARD_CAP=1 \
            "$FANOUT_SH" "$SEED" "case3-run")"
assert "outcome status hard_cap"     "[ \"\$(outcome_field '$run_dir3/outcome.json' status)\" = 'hard_cap' ]"
assert "rounds == 1"                 "[ \"\$(outcome_field '$run_dir3/outcome.json' rounds)\" = '1' ]"
assert "A is BLOCKED line"           "grep -q '^BLOCKED:' '$run_dir3/a-r1.txt'"
assert "answer source fanout-blocked" "grep -q '\"source\":\"fanout-blocked\"' '$run_dir3/events.jsonl'"
assert "4 subagent_force_killed"     "[ \"\$(count_events '$run_dir3/events.jsonl' subagent_force_killed)\" = '4' ]"
assert "run improvements has 4"      "[ \$(grep -c '^- angle ' '$run_dir3/improvements.md') -eq 4 ]"

# -----------------------------------------------------------------------------
# Case 4 — two consecutive BLOCKED rounds → failed.
# -----------------------------------------------------------------------------
echo "case 4: two consecutive BLOCKED → failed"
GLOBAL4="$TMPROOT/case4.IMPROVEMENTS.md"
: > "$GLOBAL4"
run_dir4="$(DEEPER_ASK_MOCK="$ASK3" DEEPER_ANSWER_MOCK="$ANSWER3" \
            DEEPER_GLOBAL_IMPROVEMENTS="$GLOBAL4" DEEPER_HARD_CAP=4 \
            "$FANOUT_SH" "$SEED" "case4-run")"
assert "outcome status failed"       "[ \"\$(outcome_field '$run_dir4/outcome.json' status)\" = 'failed' ]"
assert "rounds == 2"                 "[ \"\$(outcome_field '$run_dir4/outcome.json' rounds)\" = '2' ]"
assert "exit reason two consecutive" "grep -q 'two consecutive BLOCKED' '$run_dir4/outcome.json'"
assert "loop_aborted event present"  "[ \"\$(count_events '$run_dir4/events.jsonl' loop_aborted)\" = '1' ]"
assert "8 force-kill events total"   "[ \"\$(count_events '$run_dir4/events.jsonl' subagent_force_killed)\" = '8' ]"
assert "run improvements has 8"      "[ \$(grep -c '^- angle ' '$run_dir4/improvements.md') -eq 8 ]"

echo
echo "summary: $pass passed, $fail failed"
if [ $fail -gt 0 ]; then
  printf 'failed assertions:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
