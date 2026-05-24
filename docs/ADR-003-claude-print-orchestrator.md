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

Default `DEEPER_AUTO_CAP` raised 8 → 10.

## Measured latency

### Floor probe (empty prompt)

`claude -p --no-session-persistence --disable-slash-commands --tools "" --model haiku "Reply with: 1" </dev/null`, three sequential cold calls:

| Call | wall-clock |
|---|---|
| 1 | 9.6s |
| 2 | 9.2s |
| 3 | 10.1s |

### Full e2e drill, 3 rounds (run `deeper-e2e-20260524T200031Z`, 2026-05-24)

Seed: `Python의 GIL은 멀티스레딩 성능을 제한한다`. Q system prompt = PROMPT.md (~5 KB) + role framing; A system prompt = inline A1–A5 guards only (~600 B).

| Round | Q (haiku) | A (sonnet) | Round total |
|---|---|---|---|
| R1 | 40s | 18s | 58s |
| R2 | 57s | 13s | 70s |
| R3 | 42s | 14s | 56s |

**Per-round wall-clock: ~60s. Ten-round drill: ~10 minutes.**

### Reading the numbers

The floor-probe latency (~10s) was the cost of CC boot for a near-empty prompt. The Q latency under load (~45s avg) is **4× the floor**, despite using the smaller model — because the 5 KB PROMPT.md goes through the system-prompt path on every call. A's latency (~15s avg) is **lower than Q's** despite using sonnet, because A's system prompt is only the short A1–A5 guards.

**System-prompt size, not model size, is the dominant per-call cost.** The prediction in this ADR's first draft (~10s/call → 22s/round → 3.7 min for 10 rounds) was based on the floor probe and did not account for system-prompt overhead.

### Comparison to the prior Agent-dispatch path

The prior path was never measured end-to-end in production, so the original "5–10 minute" estimate was inferred from subagent boot times observed in isolated rounds, not from a full drill. The honest accounting: this ADR delivers (a) no API-key requirement, (b) a simple subprocess call shape that's easy to inspect and debug, and (c) `DEEPER_AUTO_CAP=10` as the new default. The *speed gain* over the Agent path is unclear without a controlled benchmark of both. Users should plan for ~10 minutes for a 10-round drill.

### Follow-up optimization (out of scope for this ADR)

System-prompt size is the lever. Likely interventions, in order of expected payoff:

1. **Trim PROMPT.md to model-facing content.** Much of the current file is documentation for human readers. A ~500-byte synthesis of (a) the rung ladder, (b) HARD GUARDS G1–G7, (c) bedrock categories should be sufficient for the Q model and would likely 3–4× the per-call speed.
2. **Move PROMPT.md content into the user-turn prompt** instead of the system prompt — at least until prompt caching is wired up. Anthropic's prompt cache hashes the system prompt; if Q's system prompt becomes stable (PROMPT.md text without the round-N substitution), the cache hit on call 2+ should be nearly instant. The current shape has `round-N` baked into the system prompt, which breaks that.
3. **Investigate `claude -p` prompt-cache flags.** If exposed, mark the PROMPT.md block as cacheable explicitly.

These optimizations may roll into ADR-004 once measured.

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

- ~~Real-run validation~~ — done. 3-round e2e drill (`deeper-e2e-20260524T200031Z`) executed via `/tmp/deeper-e2e.sh` (a Bash driver that replays the SKILL.md round-handler protocol directly). tree.json well-formed, events.jsonl has expected event sequence, model.py mutations correct, judge.sh produces clean `judge_result` events, render-dispatch labels show `claude -p (haiku)` / `claude -p (sonnet)` as designed. See **Measured latency → Full e2e drill** above for the numbers.
- ~~`harness/feedback.sh` source-key check~~ — done. feedback.sh only reads `judge_result.violations`; no dependency on `answer_emitted.source` values. No breakage from the "subagent" → "subprocess" rename.
- **Latency optimization** — the e2e drill showed system-prompt size dominates per-call latency (Q-haiku at 45s avg vs A-sonnet at 15s avg, despite the larger model — see Measured latency). Trim PROMPT.md or move it to the user-turn prompt to recover the predicted speed. Filed for ADR-004.
- **Connection warmup** — fire a no-op `claude -p` at run start to prime any OAuth-token / model-routing cache, hopefully amortizing the cold-start. Cheap, may shave the R1 outlier.
