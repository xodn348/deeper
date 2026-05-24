# ADR-002: Main-session orchestrator replaces worktree-isolated orchestrator

**Status**: Accepted (2026-05-24)
**Replaces**: PR #4's worktree-isolated launcher design
**Affects**: `skills/deeper/SKILL.md` auto mode
**Depends on**: `docs/ADR-001-recursive-agent-dispatch.md` (constraint)

## Context

ADR-001 documents that Claude Code blocks Agent dispatch from inside a
subagent (`"Agent is not available inside subagents"`). PR #4's design —
main session dispatches one Agent for the orchestrator, which then
dispatches per-round Q/A subagents — is structurally impossible.

## Decision

The main Claude session IS the orchestrator. It runs the round loop
directly, one round per turn, dispatching a fresh Explore subagent per
round for Q and another for A. The launcher never produces content — that
discipline is preserved.

Turn structure:

- **Turn 1**: pre-flight, run-dir setup, arm Monitor, run Round handler for
  N=1, end turn.
- **Turn N+1 (woken by Monitor judge_result notification)**: read last
  events.jsonl line; if `done` or N==CAP → exit handler; else → run Round
  handler for N+1, end turn.

Monitor armed unconditionally in Turn 1, persistent for the run duration.
Each event surfaces to the user as one chat line via `format-events.py`.

## Why one round per turn (not all in single turn)

Focus mode shows only the last text message of a turn. If all rounds ran
in one turn the user would see no progress until completion. Multi-turn
lets Monitor's stream become user-visible — each round's events surface
between turns. It also gives the user a natural interrupt point: sending a
message between rounds triggers the wake handler's `user_interrupt` path
and ends the drill cleanly.

## Trade-off accepted

PR #4 set out to prevent "round-1 dropouts" — user messages mid-drill
breaking the protocol. In the new design, a mid-drill user message ends the
drill via the `user_interrupt` path with status `aborted`. This is the
correct semantic: the user only interrupts when they want to stop. STOP is
a legitimate turn boundary, not an enemy of one.

PR #4 also wanted to "move the drill out of the main session" for context
hygiene. The new design accepts a ~200-byte cost per round (raw Q + raw A
text written to the main-session context for I/O purposes). 8 rounds ×
~200 bytes ≈ 1.6 KB. On a 1M context window this is irrelevant — the
fresh-context discipline lives in the per-round Explore subagents, which
remain cold per ADR-001.

## Alternatives considered

**Option B — Bash + Claude CLI subprocess**: orchestrator is a bash script
that shells out to `claude --print --model haiku ...` for each Q/A. True
background, preserves PR #4's launcher / orchestrator separation. Rejected
for iteration 2 because the implementation cost (CLI invocation patterns,
prompt-size handling, JSON output parsing, error handling) exceeds the
value vs the main-session approach, which works immediately and is verified
by the existing probe (`probe2`, agentId `a5ac5d17351658c26`). May be
revisited if main-session context cost grows non-trivial in practice.

## Open work

- Smoke test for the new flow: fixture seed, scripted answers via
  `DEEPER_AUTO_ANSWER`, assert round-trip integrity.
- `DEEPER_AUTO_CAP` propagation from invocation environment to the wake
  handler (currently assumed; verify in implementation pass).
- `judge.sh` and `model.py` are unchanged. PROMPT.md and BANS.md are
  unchanged. Only `skills/deeper/SKILL.md` and `docs/` change.
