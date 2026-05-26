# Example — ECDSA & Drift (the cautionary case)

A worked `/deeper` run that drilled the seed claim **"solve ECDSA cryptocraphy scheme"** for 50 rounds. Unlike [`address-clustering`](../address-clustering/), this one is interesting because **the drill drifted off-seed around R20** — and surfaced a real bug in the BEDROCK-closure mechanism.

- **Run ID:** `deeper-20260526T152911Z`
- **Mode:** auto · Q=claude haiku · A=claude sonnet
- **Final depth:** 50 · stall=0 · violations=1 (`missing-question-mark` at R48)
- **Status:** `auto_cap` (extended cap=50, never reached organic terminate)

## What actually happened, by phase

```
R1  ─ ECDSA seed
R2  ─┐
…    │ (a) Math layer — pure ECDSA crypto
R5  ─┘
R6  ─┐
…    │ (b) Algebra-vs-info layer — z₁=z₂ degeneracy, field structure
R12 ─┘
R13 ─┐
…    │ (c) Information-theoretic layer — H(k|obs), channel from k to s
R18 ─┘
R19 ─┐
…    │ (d) Foundation chase — curve group law → finite field 𝔽_p → ℤ → ZFC
R23 ─┘  (R23 declared BEDROCK:stated-value on ZFC — but drill did not close)
R24 ─┐
…    │ (e) DRIFT — Hempel's ravens, Bayesianism, pragmatism, holism
R32 ─┘  (R32 declared BEDROCK:stated-value again — drill still did not close)
R33 ─┐
…    │ (f) Meta-system — drilling deeper's own BEDROCK-closure mechanism
R44 ─┘  (R44 A explicitly recommended "STOP")
R45 ─┐
…    │ (g) Universal/particular asymmetry — and yet another BEDROCK
R50 ─┘  (R46 declared BEDROCK:identity — drill still did not close; cap hit)
```

**The drift is the story.** The first 19 rounds are textbook depth-first reduction: ECDSA → curve group law → finite field → ℤ → ZFC. The next 30 rounds are an unrelated philosophy seminar that the A-subprocess produced because each round's ancestor chain accumulated verbatim, and once R20 pivoted into Hempel's ravens, every subsequent `claude -p sonnet` call received that off-seed chain and naturally drilled there.

## What we learned

1. **The math sequence (R1–R19) works.** As a depth-first reduction of "solving ECDSA," it bottoms out cleanly: `ECDSA signing equation` → `elliptic curve scalar mult` → `chord-and-tangent over 𝔽_p` → `ring axioms of ℤ/pℤ` → `Peano + ZFC`. R23 correctly identified ZFC as `stated-value` bedrock.

2. **BEDROCK closure is broken.** Three separate `BEDROCK:<cat>` declarations (R25 stated-value, R32 stated-value, R46 identity) all failed to terminate the drill — the cursor kept advancing. This is now a confirmed bug in `nodes/deeper/model.py` worth filing.

3. **There is no topical re-anchoring mechanism.** Once a chain drifts off-seed, the ancestor-chain accumulation locks the new topic in. The only intervention is operator-side: STOP and surgical tree.json edit. A future `BANS.md` lesson should require the Q-subprocess to weight the seed claim, not just the active claim.

4. **The A subprocess can self-diagnose.** R44 explicitly said "STOP. The thread is now drilling its own meta-structure (cursor logic, regex bugs, drift mechanics)…" — the A-subprocess recognized drift and recommended abort. The launcher currently ignores answer-text recommendations (by design — only `BLOCKED:` sentinel from model.py terminates).

## Dispatch model — what runs per round

`/deeper` does NOT dispatch 5 sub-agents per round. Per round, exactly **two** `claude -p` subprocesses fire (Q and A), plus two local Python scripts:

```
Round N
├── claude -p --model haiku  --tools ""  --system-prompt …  →  Q          (~3-8s)
├── claude -p --model sonnet --tools ""  --system-prompt …  →  A          (~8-15s)
├── python3 nodes/deeper/model.py  (mutates tree.json, appends events)    (~0.1s)
└── bash   nodes/deeper/judge.sh   (emits judge_result event)             (~0.1s)
```

Total per-round wall-clock: ~22–28s. The launcher (the main Claude session) does only mechanical I/O between calls — it never produces Q or A content. Cold-context discipline: each `claude -p` call gets only `PROMPT.md` + `BANS.md` + the ancestor chain (no siblings, no full tree).

## Files

- [`digest-r1-r50.md`](./digest-r1-r50.md) — All 50 Q/A pairs in reading order. Raw transcript in English (seed and entire chain are English; PROMPT.md guard G3 enforced language match).
- [`outcome.json`](./outcome.json) — Final run metadata
- [`tree.json`](./tree.json) — Tree state with cursor + claim nodes (single-branch linear chain, depth 50)
- [`events.jsonl`](./events.jsonl) — Raw event log (50 × question_emitted + 50 × answer_emitted + 50 × judge_result + 1 × run_finished = 151 events)

## Reproducing

```bash
/deeper solve ECDSA cryptocraphy scheme
# then in chat: extend cap to 50
```

The drift is largely model-stochastic — re-running may bottom out at ZFC cleanly without drifting into Hempel's ravens. The reproducible part is the BEDROCK-closure bug: any `BEDROCK:<cat>` answer fails to set cursor=null in the current `model.py`.
