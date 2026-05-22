# Task 005: deeper as iteration-tree node (v1, mechanical)

## Goal

Plug the depth-first interview into the harness as a node. State = a tree (`tree.json`); traversal = iteration with a single cursor; LLM presence = none yet (v1 is mechanical, just asks "Why <claim>?" and captures the human answer). Proves the iteration-tree shape end-to-end before any LLM intelligence is added on top.

## Status

**Built and verified end-to-end.** Files at `nodes/deeper/`. Evidence in `runs/deeper/{smoke-chain,smoke-branch,harness-smoke}/`.

## What was built

- `nodes/deeper/PROMPT.md` — node intent + v1/v2 split.
- `nodes/deeper/model.py` — the mechanical driver. Reads/initializes `tree.json`, walks to cursor, prompts user via `/dev/tty` (or `DEEPER_AUTO_ANSWER` env for tests), mutates tree, prints one-line summary. Handles `BEDROCK:<cat>`, `BRANCH:<sibling>`, `STOP`, free-text answer.
- `nodes/deeper/judge.sh` — reads `tree.json`, computes score = `closed_leaves / total_leaves`, flags `shallow-bedrock` (depth < 2) as a violation, sets `done=true` when cursor is null and all leaves are closed.
- `nodes/deeper/render.sh` — view-only renderer (`tree.json` → indented markdown).
- `nodes/deeper/sample-seed.md` — seed claim (drilling the project's own purpose).
- `nodes/deeper/BANS.md` (empty) + `nodes/deeper/hard-cap.txt` (20).
- Harness fix: `loop.sh` + `feedback.sh` now grep `"type"[[:space:]]*:[[:space:]]*"judge_result"` (was strict `"type":"judge_result"` — broke against Python's default `json.dumps` spacing).

## Verification

### Smoke 1 — `runs/deeper/smoke-chain` (4 rounds, single thread)

Drilled the project's own raison d'être 3 levels deep, then `BEDROCK:stated-value` at round 4. Cursor advanced `[] → [0] → [0,0] → [0,0,0] → null`. Final score 1.0, depth 4.

### Smoke 2 — `runs/deeper/smoke-branch` (5 rounds, branched tree)

Two parallel branches from the root claim: one closed at depth 2 (`constraint`), the other at depth 3 (`prior-decision`). Cursor jumped correctly between branches after each `BEDROCK`. Final score 1.0, 2 closed leaves.

### Smoke 3 — `runs/deeper/harness-smoke` (1 round, full harness pipeline)

`loop.sh deeper sample-seed.md` invoked with `MODEL_CMD="python3 nodes/deeper/model.py"`. `outcome.json` produced, all 3 event types emitted (`agent_output`, `judge_result`, `ralph_iter_end`). `shallow-bedrock` violation correctly recorded (bedrock declared at depth 1).

## Design choices, locked

- **JSON canonical, markdown view.** `tree.json` is the only mutable artifact the model touches. `render.sh` is for humans. Avoids markdown-regex fragility.
- **Single cursor.** Multiple open leaves can exist (branching is supported) but only one is "active" at any iteration. `find_next_open_leaf` does a deepest-first DFS after each bedrock.
- **Bedrock detection = user, always.** Model never auto-declares. `BEDROCK:<category>` is a literal user input.
- **`shallow-bedrock` heuristic.** Bedrock at depth < 2 flagged as a violation so feedback.sh promotes the lesson if it recurs. The lesson once promoted will only affect v2 (LLM-driven) — v1's mechanical model doesn't read BANS.

## What's intentionally NOT in v1

- **No LLM-generated questions.** v1 just asks "Why <claim>?" mechanically. v2 will read PROMPT.md + BANS.md + the cursor's ancestor chain (NOT the whole tree, preserving fresh-context) and emit a targeted pressure-ladder or Ontologist-4Q question.
- **No autonomous run via `meta-loop.sh`.** Interactive only (`/dev/tty`). Autonomous integration requires the v2 LLM model.
- **No depth-meter scoring per round.** That's a v2 feature, layered on top of LLM-generated questions.
- **No automatic detour refusal.** v1 trusts the user. v2 adds a guard that detects topic switches in user answers and asks "park this, finish current thread?"

## v2 next steps (separate task to write)

1. Replace `model.py`'s "ask Why X?" with an LLM call that builds the prompt from PROMPT.md + BANS.md + the cursor's ancestor chain only, and emits one targeted depth question.
2. Wire `BANS.md` into the LLM prompt so feedback-loop lessons actually shape behavior.
3. Add the `depth_meter` rubric from `skills/deeper/SKILL.md` § Depth meter to score each round; meter-stall triggers a stall check.
4. Add the depth-keeper (inverted breadth-keeper) guard inside `model.py` that detects when a user answer opens a new topic vs deepens the current one.

## Acceptance (this task)

- [x] `nodes/deeper/` follows `node-contract.md`.
- [x] Single-thread drill to bedrock works (smoke-chain).
- [x] Branching works (smoke-branch).
- [x] Harness integration works (smoke-harness).
- [x] Bug fix: JSON-format mismatch between Python and grep — fixed.
- [x] Evidence committed under `runs/deeper/`.

## Constraints

- No node-specific code in the harness (verified — only the grep regex was widened, which is contract-compatible).
- Python 3 stdlib only. No external deps.
- Markdown rendering optional (`render.sh` is convenience, not required for correctness).
