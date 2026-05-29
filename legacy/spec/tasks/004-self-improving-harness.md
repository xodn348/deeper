# Task 004: Self-improving ralph harness

## Goal

Build the `ralph → feedback → ralph → feedback` loop as task-agnostic infrastructure. Prove it works end-to-end on a simple autonomous node before plugging in `deeper`.

## Status

**Built and verified end-to-end with a deterministic mock model.** See `harness/`, `nodes/commit-msg/`, `runs/commit-msg/`.

## Architecture

Three layers, each in its own file:

1. `harness/loop.sh` — one ralph run (M ralph-iterations until done or hard cap, judge-checked each iteration). Task-agnostic; depends only on the node contract.
2. `harness/feedback.sh` — reads the last N runs' `events.jsonl`, aggregates violations, promotes any that appear in ≥ `LESSON_THRESHOLD` runs to the node's `BANS.md` (idempotent).
3. `harness/meta-loop.sh` — composes the above: run N ralph runs, calling feedback after each (or every K).

Plus `harness/lib/mock-model.sh` — a deterministic state-machine fake LLM. Reads `BANS.md` and adjusts output based on which lessons exist. Proves the harness pipework without LLM cost.

## Node contract (`node-contract.md`)

Every node provides:
- `PROMPT.md`, `BANS.md`, `judge.sh`, optional `hard-cap.txt`.
- Writes per-run state to `runs/<node>/<run-id>/{seed.md, state.md, events.jsonl, outcome.json}`.
- Events follow a fixed JSON-lines schema (`agent_output`, `judge_result`, `ralph_iter_end`).

## Verification trajectory (commit-msg node, mock model)

| meta-iter | status | score | rounds | BANS size at start |
|---|---|---|---|---|
| 1 | hard_cap | 0.25 | 3 | 0 |
| 2 | hard_cap | 0.25 | 3 | 0 (threshold not yet met) |
| 3 | hard_cap | 0.75 | 3 | 3 |
| 4 | hard_cap | 0.75 | 3 | 3 (verb-tense not yet promoted) |
| 5 | **passed** | **1.0** | **1** ✓ | 4 |
| 6 | passed | 1.0 | 1 ✓ | 4 |

Final BANS.md ends with 4 promoted lessons (length, no-conv-format, trailing-period, verb-tense). The system started at 0.25 and converged to perfect performance through pure file-based feedback. No human intervention between runs.

## Acceptance

- [x] `harness/loop.sh` runs a node end-to-end and emits valid `events.jsonl` + `outcome.json`.
- [x] `harness/feedback.sh` correctly identifies repeated violations and updates BANS.md idempotently.
- [x] `harness/meta-loop.sh` composes the two with no glue code beyond invocation.
- [x] Reference node `commit-msg` plugged in via the contract — no harness edits required.
- [x] Self-improvement trajectory observable: score monotonically non-decreasing across meta-iterations.
- [ ] `deeper` node plugged in following the same contract (next task).

## Constraints

- No node-specific code in the harness. All node specifics live in `nodes/<name>/`.
- Mock model is for demos only. Real runs use `MODEL_CMD="claude -p"` (or any CLI taking prompt on stdin, returning output on stdout).
- The harness must remain runnable with only bash + python3 (already present on every dev machine here). No new deps.

## What's intentionally NOT in v1

- No web UI / dashboard.
- No parallel ralph runs of the same node (would need run-id locking).
- No automatic lesson curation beyond "appeared in ≥ threshold runs." A future task may add an LLM-based lesson summarizer that consolidates duplicate lessons.
- No cross-node lesson sharing. Each node has its own BANS.md.

## Next

- Plug `deeper` node in (task 005, to be created when we tackle it): refactor `skills/deeper/SKILL.md` into `nodes/deeper/PROMPT.md` + a human-in-loop judge that reads the user's response from stdin instead of running a script.
