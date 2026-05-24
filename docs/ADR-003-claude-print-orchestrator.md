# ADR-003: `claude -p` subprocess replaces Agent / Explore-subagent dispatch

**Status**: Accepted (2026-05-24)
**Supersedes**: the Q / A dispatch *mechanism* in ADR-002 (which dispatched fresh `Explore` subagents per round via the `Agent` tool). Keeps everything else from ADR-002 — main session is still the orchestrator, single-turn round loop still applies, judge.sh exit code is still the authoritative done/continue signal (post-`aa47b3a`).
**Affects**: `skills/deeper/SKILL.md`, new helper `nodes/deeper/ask.sh`.

## Context

ADR-002 made the main Claude session the orchestrator and dispatched a fresh `Agent(subagent_type="Explore")` per round for Q (haiku) and another for A (sonnet). This satisfied the cold-context discipline (each round starts from PROMPT.md + BANS.md + ancestor chain with no prior-round residue) but inherited the full Claude Code subagent boot cost per call — system prompt assembly, tool harness loading, plugin / MCP wiring, CLAUDE.md auto-discovery. Observed per-call latency in production drills: ~15–30s per subagent dispatch, totaling ~30–60s per round (Q + A). At the prior `DEEPER_AUTO_CAP=8` that meant ~4–8 minute drills; the user wanted ≥10 rounds and a noticeably faster loop.

The user also specified the auth constraint: **no ANTHROPIC_API_KEY**. The drill must use the existing Claude Code session (the user's logged-in subscription), not API-key-billed calls.

## Decision

Replace per-round `Agent` dispatch with per-round `claude -p` subprocess invocation, wrapped by a tiny helper at `nodes/deeper/ask.sh`. The helper:

```bash
claude -p \
  --no-session-persistence \
  --disable-slash-commands \
  --tools "" \
  --model "$MODEL" \
  --system-prompt "$(cat "$SYS_FILE")" \
  "$(cat "$USER_FILE")" </dev/null
```

Each flag is load-bearing:

- `--system-prompt` *replaces* the default Claude Code system prompt entirely, skipping the plugin / hook / MCP / CLAUDE.md boot baggage. We supply just PROMPT.md + BANS.md + role framing.
- `--tools ""` disables every tool. Q and A are pure text in / text out — no tool calls needed, and the tool list is part of the default-prompt overhead we want to skip.
- `--no-session-persistence` keeps the call from polluting the user's `/resume` picker with one entry per round.
- `--disable-slash-commands` skips skill resolution.
- `</dev/null` is mandatory — without it, `claude -p` waits 3s on stdin even when the prompt is passed as an argument (observed during the smoke test).

Session auth is the default behavior — `claude -p` reads the OAuth token / keychain entry the user already established via `claude /login`. No API key.

The main session writes per-round prompt files (`.q-sys-{N}.txt` + `.q-user-{N}.txt` for Q, `.a-sys-{N}.txt` + `.a-user-{N}.txt` for A) and runs ask.sh as a `Bash` tool call, capturing stdout to `.q-raw-{N}.txt` / `.a-raw-{N}.txt`. Everything downstream (model.py, judge.sh, the launcher loop's done/continue branch, the stall self-heal path) is unchanged.

Default `DEEPER_AUTO_CAP` raised 8 → 10 to match the per-round latency drop.

## Measured latency (smoke test, 2026-05-24)

Floor probe (`claude -p --no-session-persistence --disable-slash-commands --tools "" --model haiku "Reply with: 1" </dev/null`), three sequential cold calls:

| Call | wall-clock |
|---|---|
| 1 | 9.6s |
| 2 | 9.2s |
| 3 | 10.1s |

Real round-shaped probe with full system prompt (~5 KB):

| Call | wall-clock |
|---|---|
| Q haiku, real prompt + active claim | ~10s |
| A sonnet, real prompt + active claim + question | ~10s |

Per-round cost: Q + A + model.py (<0.5s) + judge.sh (<0.5s) + bookkeeping ≈ **22s/round**. Ten-round drill ≈ **3.7 minutes**. Prior Agent-dispatch path was an estimated 4–8 minutes for eight rounds; this is roughly 2× faster *and* extends to ten rounds.

## Why not `--bare`

`claude --bare` skips even more boot (hooks, plugins, MCP, CLAUDE.md, auto-memory, attribution, keychain reads). It is the obvious next step for latency. But the `--bare` documentation states: *"Anthropic auth is strictly ANTHROPIC_API_KEY or apiKeyHelper via --settings (OAuth and keychain are never read)."* That breaks the no-API-key constraint. ask.sh therefore stops at the maximum boot reduction compatible with session auth.

If the user ever switches to API-key auth, swapping ask.sh to use `--bare` is a one-line change and would likely shave another 3–5s per call (the 5s user-CPU floor we measured is largely module-loading overhead that `--bare` would skip).

## Why not a long-lived subprocess (one daemon, many rounds)

Considered: spawn one `claude` process at run start, feed Q and A prompts through stdin via `--input-format=stream-json`, read responses from stdout. This would eliminate the per-call CC boot entirely and probably cut per-round to ~5s.

Rejected for v1 because:

1. **Cold-context discipline is the whole point.** A long-lived session accumulates context across rounds — exactly the drift this skill fights. Each Q and A must start cold; spawning a fresh process is the simplest way to guarantee it.
2. **Complexity.** Stream-JSON framing, session id management, error recovery, partial-message handling. The per-round subprocess pays a ~10s boot tax that buys back fresh-context-by-construction.

May be revisited if (a) per-round latency becomes the binding constraint *and* (b) we find a clean way to reset model context between Q/A without losing the boot savings (e.g., `claude` exposes a hypothetical `--reset-context` flag).

## Why this preserves ADR-002

ADR-002's core decision — *"the main session IS the orchestrator, single-turn round loop, judge.sh exit code is authoritative"* — is unchanged. ADR-003 swaps one line in the round handler (the Q / A dispatch mechanism) and leaves the surrounding control flow intact. The `aa47b3a` race-resilience hardening (judge.sh exit codes 0/100/1, stuck-run pre-flight) also unchanged.

## Open work

- Real-run validation: trigger a full `/deeper <claim>` drill end-to-end and confirm wall-clock ≈ 3.7 min for 10 rounds. The smoke test only ran Q and A standalone; the full launcher loop, model.py mutations, judge.sh checks, and Monitor streaming have not been exercised together with the new ask.sh path.
- `harness/feedback.sh` and `nodes/deeper/judge.sh` reference the `source` field on `answer_emitted` events. ask.sh-era values are `"subprocess"`, `"subprocess-opus-retry"`, `"stall-stop-sentinel"` (replacing `"subagent"` etc.). Check that feedback.sh's aggregation doesn't key on the old values.
- Eventually consider a `claude -p` connection-warmup trick: fire a no-op call at run start to prime any OAuth-token or model-routing cache, hopefully amortizing the cold-start across the run rather than paying it per round.
