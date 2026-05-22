# Node contract

Every node that plugs into the self-improving harness MUST provide the following. The harness (`harness/loop.sh`, `harness/feedback.sh`, `harness/meta-loop.sh`) is task-agnostic and depends only on this contract.

## Layout

```
nodes/<node-name>/
├── PROMPT.md          # Fixed instructions read every ralph iteration
├── BANS.md            # Accumulated lessons; the harness appends here (auto or curated)
├── judge.sh           # Reads a run dir, emits judge events to events.jsonl
└── (optional) hard-cap.txt  # max ralph iterations per run; default 12
```

## Per-run directory

```
runs/<node-name>/<run-id>/
├── seed.md            # The locked input (single source of truth for this run)
├── state.md           # Mutable working state (e.g. the trace, the draft, the WIP)
├── events.jsonl       # Append-only structured events
└── outcome.json       # Terminal record (status, rounds, final_score, exit_reason)
```

`<run-id>` format: `<node-name>-<YYYYMMDDTHHMMSSZ>-<seq>`. Never reused.

## Events schema

Every line in `events.jsonl` is one JSON object:

```json
{"ts": "ISO8601", "run_id": "...", "node": "...", "round": <int>, "type": "<event-type>", ...}
```

Required event types:

- `agent_output` — `{type, output: "<text>"}` written by the harness after each model call.
- `judge_result` — `{type, score: <0..1>, violations: ["<key1>", ...], detail: {...}}` written by `judge.sh`.
- `ralph_iter_end` — `{type, done: <bool>, reason: "<short>"}` written by the harness.

Nodes MAY emit additional event types (e.g. `depth_delta` for deeper). They MUST be parseable JSON lines.

## Outcome schema

```json
{
  "run_id": "...",
  "node": "...",
  "status": "passed" | "failed" | "hard_cap" | "aborted",
  "rounds": <int>,
  "final_score": <float|null>,
  "exit_reason": "<short>",
  "violations_total": {"<key>": <count>}
}
```

## Judge contract

`judge.sh <run-dir>`:

- Reads `state.md` (and optionally `seed.md`, `events.jsonl`).
- Emits ONE `judge_result` event to `events.jsonl`.
- Exit code: 0 = the run can continue or terminate, 1 = the run should terminate immediately (catastrophic failure).
- Sets `done=true` in a `ralph_iter_end` event ONLY indirectly: the harness reads the latest `judge_result` and decides based on rules in PROMPT.md frontmatter (or default: `done` when `score >= 0.9` and no `violations`).

## Model contract

The harness invokes `$MODEL_CMD` for each ralph iteration, passing the full prompt on stdin and reading the output from stdout.

- Default: `claude -p` (Claude Code CLI in headless mode).
- Override for tests: `MODEL_CMD=harness/lib/mock-model.sh`.
- The model MUST output exactly one of:
  - A working-state update (free text appended to `state.md`).
  - A `DONE` line on its own.
  - A `BLOCKED: <reason>` line on its own.

## Lessons / BANS lifecycle

1. `feedback.sh <node>` reads the last N runs' `events.jsonl`.
2. Aggregates violations by `<key>`.
3. If a key appears in `>= LESSON_THRESHOLD` runs (default 2), it becomes a lesson candidate.
4. Lesson candidates are appended to `BANS.md` UNLESS already present (idempotent).
5. Each lesson carries a short rationale: `(promoted from N runs in last M; example: <run-id>)`.

PROMPT.md MUST include `BANS.md` content verbatim near the top so every fresh iteration sees the accumulated lessons.

## Non-goals of the contract

- Does not prescribe the LLM (any `MODEL_CMD` works).
- Does not prescribe how state.md is structured (each node decides).
- Does not prescribe parallelism (single-node runs are sequential; multiple nodes can run concurrently if their run directories don't collide).
- Does not prescribe a UI. The artifacts are files; observability is `tail -f events.jsonl`.

## Reference nodes

- `nodes/commit-msg/` — autonomous, fast, deterministic mock-model demo. Proves the harness end-to-end.
- `nodes/deeper/` — human-in-loop interview node (to be added). Uses the same harness with human-as-judge.
