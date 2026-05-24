# ADR-004: Trim PROMPT.md to model-facing content

**Status**: Accepted with a negative latency result (2026-05-24). The trim ships for code-quality reasons; it does not move per-round wall-clock measurably.
**Supersedes**: nothing. Builds on ADR-003 (`claude -p` subprocess dispatch). The "Latency optimization" open item filed by ADR-003 is **not closed** — re-filed for ADR-005 with a revised hypothesis.
**Affects**: `nodes/deeper/PROMPT.md`, `nodes/deeper/model.py` (docstring).

## Context

ADR-003 shipped `claude -p` subprocess dispatch and measured ~60s per round (Q-haiku ~45s + A-sonnet ~15s). The diagnostic was clear: **system-prompt size, not model size, dominates per-call cost**. Q-haiku ran *slower* than A-sonnet because Q embeds the full PROMPT.md (~8.7 KB) while A embeds only inline A1–A5 guards (~600 B).

PROMPT.md was written when the deeper node had a dual-purpose contract: (v1) `model.py` consumed the file as a mechanical specification, (v2) the Q subagent consumed the same file as a system prompt. ADR-003 collapsed that — `ask.sh haiku` is now the single PROMPT.md consumer. The v1-only sections — output protocol, tree mutation rules, dual-purpose framing — became dead documentation living in the Q model's system prompt, paid for on every round.

## Decision

Trim PROMPT.md to model-facing content only. Drop:

- **L1–7 dual-purpose header** — "this file is read by v1 model.py OR v2 subagent." ADR-003 made it v2-only. Header is obsolete.
- **L110–119 RED FLAGS** — every item duplicates a HARD GUARD (G1–G7) or a Forbidden-questions entry. Redundancy at the end of the prompt costs tokens without adding signal.
- **L121–130 Output protocol** — describes the `round N: cursor=... outcome=...` line that `model.py` emits. `model.py` does not read PROMPT.md; the description is documentation for humans, misplaced inside the Q model's system prompt. Moved to `model.py` docstring.
- **L131–137 Tree mutation rules** — describes how `model.py` mutates `tree.json` based on `BEDROCK:` / `BRANCH:` / `STOP` / normal inputs. Same reasoning — the Q model does not perform tree mutations. Moved to `model.py` docstring.

Keep verbatim:

- Role + language + fresh-context preamble (restructured as the file's opening, no longer hidden under a dual-purpose header)
- HARD GUARDS G1–G7 (binary self-check invariants — load-bearing for question quality)
- Pressure ladder + Ontologist 4Q (decision framework for rung selection)
- Forbidden questions (negative examples the model must refuse)
- Bedrock axiom categories (needed for ladder rung 5)

## Measured latency

Both runs used seed `Python의 GIL은 멀티스레딩 성능을 제한한다`, N_CAP=3, sequential cold `claude -p` calls via `harness/e2e.sh`. e2e.sh was patched to honor `DEEPER` from env so the trimmed PROMPT.md in this worktree could be exercised.

### Baseline — PROMPT.md = 8735 B (run `deeper-e2e-20260524T210943Z`)

| Round | Q (haiku) | A (sonnet) | Round total |
|---|---|---|---|
| R1 | 40s | 19s | 60s |
| R2 | 41s | 12s | 53s |
| R3 | 40s | 18s | 58s |
| **Avg** | **40.3s** | **16.3s** | **57s** |

### Post-trim — PROMPT.md = 7031 B (run `deeper-e2e-20260524T211337Z`)

| Round | Q (haiku) | A (sonnet) | Round total |
|---|---|---|---|
| R1 | 48s | 17s | 65s |
| R2 | 38s | 14s | 52s |
| R3 | 61s | 15s | 76s |
| **Avg** | **49.0s** | **15.3s** | **64.3s** |

### Reading the numbers — the trim did not move latency

PROMPT.md shrunk 8735 B → 7031 B = **19.5% reduction**. Q-haiku per-call wall-clock went 40.3s → 49.0s. The delta is **the wrong direction**, and R3's 61s Q-call is an outlier that drives most of the gap. Total round wall-clock 57s → 64.3s.

With n=3 per condition, single-round variance dominates: post-trim R2 (38s Q) was the fastest Q-call we have measured, and post-trim R3 (61s Q) was the slowest. The standard deviation across these six Q-calls is ~8s — larger than the mean shift. **A 19.5% prompt-size cut produced no measurable latency improvement.**

This contradicts ADR-003's diagnostic that "system-prompt size dominates per-call cost." More likely:

- **Floor effects.** ADR-003's floor probe (empty prompt → ~10s) plus model token-processing has a soft floor in the 30–40s range for the Q-haiku call shape. At 7 KB we are still well above the floor where size→latency becomes linear.
- **Server-side variance.** Per-call latency varies by ±10s round-to-round on the same prompt; the cost of model inference at this scale is dominated by queueing and routing, not token count.
- **Cache misses.** Each call is cold (`--no-session-persistence`, fresh subprocess). The system prompt is rehashed, retokenized, and re-fed every round.

The trim still ships for code-quality reasons — dead documentation should not live in a per-round system prompt regardless of speed — but the **speed promise from ADR-003 is unfulfilled by trim alone**. Real latency wins require attacking the cold-call floor itself, not the prompt content.

## Out-of-scope levers (filed for ADR-005)

This trim was a controlled-variable test of ADR-003's hypothesis. Result: prompt size at this scale is not the binding constraint. ADR-005 should attack the cold-call floor directly. Candidate angles in order of expected payoff:

1. **Long-lived `claude` subprocess with context reset between rounds.** Eliminates the ~10s CC boot per call. Considered and rejected in ADR-003 for complexity reasons; the negative result here strengthens the case for revisiting it.
2. **Connection / model warmup.** Fire a no-op `claude -p` at run start to prime OAuth/model-routing caches. Cheap; may shave the R1 outlier specifically.
3. **Move per-round context to the user-turn prompt** so the system prompt stabilizes across rounds. Prompt caching (if available via `claude -p`) hashes the system prompt; a stable system prompt could turn calls 2+ into cache hits. Requires confirming whether session-auth `claude -p` participates in prompt caching at all.
4. **Aggressive guard compression** (G1–G7 to checklist form) — only worth attempting if (3) provides caching and the next prompt-size reduction can push the system prompt below the model's cache-line boundary. Not a useful lever in isolation.

## Open work

- Validate that trimmed PROMPT.md does not regress question quality. Three-round drill emitted clean G1–G7-compliant questions matching baseline shape; further validation across diverse seeds is wise before raising `DEEPER_AUTO_CAP` further.
- `loop.sh` (legacy v1 ralph harness) still concatenates PROMPT.md into its prompt for non-deeper nodes. For deeper specifically, ADR-003 deprecated that path; the dropped output-protocol section was only relevant when `MODEL_CMD="claude -p"` was driving the deeper node directly through loop.sh, which is no longer the active path. Other nodes (e.g. `commit-msg`) maintain their own PROMPT.md files and are unaffected.
