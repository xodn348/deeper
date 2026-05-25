# Example — Address Clustering (Creative Methods)

A worked `/deeper` run that drilled the seed claim **"find a creative way to do address clustering well"** for 50 rounds.

- **Run ID:** `deeper-20260525T201112Z`
- **Mode:** auto · Q=claude haiku · A=claude sonnet
- **Final depth:** 48 · stall=0 · violations=0
- **Status:** `auto_cap` (extended cap=50, all rounds completed)

## Trajectory summary

The original intent was "find creative methods," but depth-first drilling converged onto **methodological limits**. The 50-round flow:

- **R1–R5 (practical layer)** — "doing clustering well" = a trilemma of precision/recall × CoinJoin resistance × computational efficiency → reframing as *satisficing* (rather than maximization) opens a Pareto region → BlockSci (Kalodner et al., 2017) is effectively that case → but the "detect-then-exclude" pipeline is structurally fragile against undetected CoinJoin.
- **R6–R10 (empirical layer)** — Union-Find itself just computes a transitive closure → false-merge avoidance depends on the premise that mixed inputs "overwhelmingly belong to different components" → that premise reduces to a circular argument from CoinJoin participation motive → independent ground truth is required → KYC / law-enforcement seizure data exists but suffers from selection bias.
- **R11–R15 (epistemic layer)** — Researcher-controlled experiments achieve causal independence → adding JoinMarket makers only shifts the granularity of the substitution problem → Manski-style partial identification (interval estimation) relaxes the strong-independence requirement.
- **R16–R25 (meta-epistemic)** — The trilemma is an artifact of over-specified objective functions → justifying the choice of standards triggers infinite regress → Münchhausen trilemma → Neurath's boat → Wittgenstein's *Lebensform*.
- **R26–R40 (philosophy)** — Sellars, Brandom, Lewis Carroll's tortoise, Kantian conditions of possibility, self-referential structure.
- **R41–R50 (recursive meta)** — Sealing / self-effacement, defeasible closure.

## Concrete clustering ideas extracted along the way

The trace went toward limits, but several actionable angles surfaced en route:

1. **Satisficing reframe** (R3) — Predefine practical thresholds on the Pareto frontier (e.g., "95% precision, 80% CoinJoin resistance, O(n log n) scalability") to sidestep the trilemma.
2. **Layered pipeline** (R2) — Run cheap Union-Find first, then apply expensive ML only to suspect clusters (Chainalysis's actual pattern — reproducible by anyone).
3. **Researcher-controlled experiments** (R12) — Participate in CoinJoin (e.g., JoinMarket) with your own key pairs, then measure false-merge directly against the preconstructed ground truth.
4. **Manski partial identification** (R15) — Give up point estimation, use interval estimation — bounded results obtainable with only weak independence.
5. **Natural experiments** (R15) — Exploit exogenous protocol shocks (BIP-141 activation, fee-market shifts) as quasi-experiments.
6. **JoinMarket maker partial labels** (R12) — Identify maker addresses from the public orderbook as a partial ground-truth augmentation.
7. **Hybrid ground truth** — Combine KYC (R10) + law-enforcement seizure data + self-attribution tags (Reid & Harrigan 2013) + researcher experiments + maker identification *orthogonally*.

## Files

- [`digest-r1-r50.md`](./digest-r1-r50.md) — All 50 Q/A pairs in reading order (~50 KB). **Raw transcript is in Korean** — the drill ran in Korean to match the seed's language (PROMPT.md guard G3 enforces language match between active claim and question).
- [`outcome.json`](./outcome.json) — Final run metadata
- [`tree.json`](./tree.json) — Full tree state with cursor + claim nodes
- [`events.jsonl`](./events.jsonl) — Raw event log (question_emitted / answer_emitted / judge_result)

## Reproducing

```bash
/deeper find a creative way to do address clustering well
# then at the cap=10 prompt: "Resume with +10 rounds" (re-extend as needed)
```

Original Korean seed: `address clustering 잘하고 창의적으로 할수 있는 방법 찾아봐`
