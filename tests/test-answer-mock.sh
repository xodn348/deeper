#!/usr/bin/env bash
# test-answer-mock.sh — verify answer.sh shell wiring without invoking claude.
# Uses DEEPER_ANSWER_MOCK to inject canned JSON envelopes and asserts the
# observable side effects: stdout, exit code, improvements.md writes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANSWER_SH="$REPO_ROOT/nodes/deeper/answer.sh"
[[ -x "$ANSWER_SH" ]] || { echo "answer.sh not executable: $ANSWER_SH" >&2; exit 2; }

TMPROOT="$(mktemp -d -t deeper-answer-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0
failures=()

run_case() {
  local name="$1" mock="$2" round="$3"
  local case_dir="$TMPROOT/$name"
  local run_dir="$case_dir/run"
  local global_imp="$case_dir/GLOBAL_IMPROVEMENTS.md"
  mkdir -p "$run_dir"
  printf 'A1: ancestor answer one\n' > "$case_dir/ancestors.md"
  printf 'why does X keep happening?\n' > "$case_dir/question.md"
  : > "$global_imp"

  local stdout_file="$case_dir/stdout.txt"
  local stderr_file="$case_dir/stderr.txt"
  local exit_code=0
  DEEPER_ANSWER_MOCK="$mock" \
  DEEPER_GLOBAL_IMPROVEMENTS="$global_imp" \
    "$ANSWER_SH" "$case_dir/ancestors.md" "$case_dir/question.md" "$run_dir" "$round" \
    >"$stdout_file" 2>"$stderr_file" || exit_code=$?

  printf '%s\0' "$stdout_file" "$stderr_file" "$run_dir/improvements.md" "$global_imp" "$exit_code"
}

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

# -----------------------------------------------------------------------------
# Case 1 — clean: 5 completed, 0 killed → stdout = synthesis, no improvements.
# -----------------------------------------------------------------------------
echo "case 1: clean (5/0)"
MOCK1='{
  "synthesis": "The pattern repeats because the underlying incentive is unchanged.",
  "completed": ["evidence","counterexample","boundary","mechanism","precedent"],
  "force_killed": [],
  "blocked": false,
  "elapsed_seconds": 91
}'
out1="$TMPROOT/case1"
mkdir -p "$out1/run"
: > "$out1/GLOBAL_IMPROVEMENTS.md"
printf 'A1: prior\n' > "$out1/ancestors.md"
printf 'why does X keep happening?\n' > "$out1/question.md"
ec=0
DEEPER_ANSWER_MOCK="$MOCK1" DEEPER_GLOBAL_IMPROVEMENTS="$out1/GLOBAL_IMPROVEMENTS.md" \
  "$ANSWER_SH" "$out1/ancestors.md" "$out1/question.md" "$out1/run" 1 \
  >"$out1/stdout.txt" 2>"$out1/stderr.txt" || ec=$?
assert "exit 0" "[ $ec -eq 0 ]"
assert "stdout contains synthesis" "grep -q 'pattern repeats because' '$out1/stdout.txt'"
assert "stdout does not start with BLOCKED" "! grep -q '^BLOCKED' '$out1/stdout.txt'"
assert "envelope file written" "[ -f '$out1/run/answer-r1.json' ]"
assert "run improvements has only header" "! grep -q 'angle \`' '$out1/run/improvements.md'"
assert "global improvements untouched" "[ ! -s '$out1/GLOBAL_IMPROVEMENTS.md' ]"

# -----------------------------------------------------------------------------
# Case 2 — partial: 3 completed, 2 killed → synthesis emitted, 2 improvements.
# -----------------------------------------------------------------------------
echo "case 2: partial (3/2)"
MOCK2='{
  "synthesis": "Evidence and mechanism both point to incentive lock-in. [angle: boundary — collection failed: tool_loop] [angle: precedent — collection failed: network_timeout]",
  "completed": ["evidence","counterexample","mechanism"],
  "force_killed": [
    {"angle":"boundary","subagent_id":"task_a","reason":"tool_loop","last_tool":"WebFetch","snippet":"loop on WebFetch x12"},
    {"angle":"precedent","subagent_id":"task_b","reason":"network_timeout","last_tool":"WebSearch","snippet":"DNS timeout"}
  ],
  "blocked": false,
  "elapsed_seconds": 188
}'
out2="$TMPROOT/case2"
mkdir -p "$out2/run"
: > "$out2/GLOBAL_IMPROVEMENTS.md"
printf 'A1: prior\n' > "$out2/ancestors.md"
printf 'why does X keep happening?\n' > "$out2/question.md"
ec=0
DEEPER_ANSWER_MOCK="$MOCK2" DEEPER_GLOBAL_IMPROVEMENTS="$out2/GLOBAL_IMPROVEMENTS.md" \
  "$ANSWER_SH" "$out2/ancestors.md" "$out2/question.md" "$out2/run" 2 \
  >"$out2/stdout.txt" 2>"$out2/stderr.txt" || ec=$?
assert "exit 0" "[ $ec -eq 0 ]"
assert "stdout has synthesis" "grep -q 'incentive lock-in' '$out2/stdout.txt'"
assert "stdout inlines boundary failure" "grep -q 'boundary — collection failed' '$out2/stdout.txt'"
assert "run improvements has 2 entries" "[ \$(grep -c '^- angle ' '$out2/run/improvements.md') -eq 2 ]"
assert "global improvements has 2 entries" "[ \$(grep -c '^- angle ' '$out2/GLOBAL_IMPROVEMENTS.md') -eq 2 ]"
assert "improvements include tool_loop reason" "grep -q 'reason \`tool_loop\`' '$out2/run/improvements.md'"
assert "improvements include network_timeout reason" "grep -q 'reason \`network_timeout\`' '$out2/run/improvements.md'"

# -----------------------------------------------------------------------------
# Case 3 — threshold breach: 1 completed, 4 killed → BLOCKED, 4 improvements.
# -----------------------------------------------------------------------------
echo "case 3: threshold breach (1/4)"
MOCK3='{
  "synthesis": "",
  "completed": ["evidence"],
  "force_killed": [
    {"angle":"counterexample","subagent_id":"t1","reason":"context_limit","last_tool":"Read","snippet":"ctx exhausted"},
    {"angle":"boundary","subagent_id":"t2","reason":"tool_loop","last_tool":"Grep","snippet":"repeat grep"},
    {"angle":"mechanism","subagent_id":"t3","reason":"ambiguous_task","last_tool":"","snippet":"task unclear"},
    {"angle":"precedent","subagent_id":"t4","reason":"network_timeout","last_tool":"WebFetch","snippet":"504"}
  ],
  "blocked": true,
  "elapsed_seconds": 195
}'
out3="$TMPROOT/case3"
mkdir -p "$out3/run"
: > "$out3/GLOBAL_IMPROVEMENTS.md"
printf 'A1: prior\n' > "$out3/ancestors.md"
printf 'why does X keep happening?\n' > "$out3/question.md"
ec=0
DEEPER_ANSWER_MOCK="$MOCK3" DEEPER_GLOBAL_IMPROVEMENTS="$out3/GLOBAL_IMPROVEMENTS.md" \
  "$ANSWER_SH" "$out3/ancestors.md" "$out3/question.md" "$out3/run" 3 \
  >"$out3/stdout.txt" 2>"$out3/stderr.txt" || ec=$?
assert "exit 0" "[ $ec -eq 0 ]"
assert "stdout starts with BLOCKED" "grep -q '^BLOCKED' '$out3/stdout.txt'"
assert "BLOCKED reports 4 force-kills" "grep -q '4 angle' '$out3/stdout.txt'"
assert "improvements has 4 entries" "[ \$(grep -c '^- angle ' '$out3/run/improvements.md') -eq 4 ]"
assert "global improvements has 4 entries" "[ \$(grep -c '^- angle ' '$out3/GLOBAL_IMPROVEMENTS.md') -eq 4 ]"

# -----------------------------------------------------------------------------
# Case 4 — malformed JSON → exit 3.
# -----------------------------------------------------------------------------
echo "case 4: malformed JSON"
MOCK4='not json at all { definitely broken'
out4="$TMPROOT/case4"
mkdir -p "$out4/run"
: > "$out4/GLOBAL_IMPROVEMENTS.md"
printf 'A1: prior\n' > "$out4/ancestors.md"
printf 'why does X keep happening?\n' > "$out4/question.md"
ec=0
DEEPER_ANSWER_MOCK="$MOCK4" DEEPER_GLOBAL_IMPROVEMENTS="$out4/GLOBAL_IMPROVEMENTS.md" \
  "$ANSWER_SH" "$out4/ancestors.md" "$out4/question.md" "$out4/run" 4 \
  >"$out4/stdout.txt" 2>"$out4/stderr.txt" || ec=$?
assert "exit 3" "[ $ec -eq 3 ]"
assert "stderr explains parse failure" "grep -q 'envelope is not JSON' '$out4/stderr.txt'"

# -----------------------------------------------------------------------------
# Case 5 — empty synthesis, no kills → BLOCKED: empty synthesis.
# -----------------------------------------------------------------------------
echo "case 5: empty synthesis"
MOCK5='{
  "synthesis": "",
  "completed": ["evidence","counterexample","boundary","mechanism","precedent"],
  "force_killed": [],
  "blocked": false,
  "elapsed_seconds": 50
}'
out5="$TMPROOT/case5"
mkdir -p "$out5/run"
: > "$out5/GLOBAL_IMPROVEMENTS.md"
printf 'A1: prior\n' > "$out5/ancestors.md"
printf 'why does X keep happening?\n' > "$out5/question.md"
ec=0
DEEPER_ANSWER_MOCK="$MOCK5" DEEPER_GLOBAL_IMPROVEMENTS="$out5/GLOBAL_IMPROVEMENTS.md" \
  "$ANSWER_SH" "$out5/ancestors.md" "$out5/question.md" "$out5/run" 5 \
  >"$out5/stdout.txt" 2>"$out5/stderr.txt" || ec=$?
assert "exit 0" "[ $ec -eq 0 ]"
assert "stdout BLOCKED on empty synthesis" "grep -q 'BLOCKED: empty synthesis' '$out5/stdout.txt'"

# -----------------------------------------------------------------------------
echo
echo "summary: $pass passed, $fail failed"
if [ $fail -gt 0 ]; then
  printf 'failed assertions:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
