# Task 003: Evaluation harness

## Goal

5 sample interview topics under `eval/` with expected bedrock category, expected round budget, and a one-line "good bedrock" exemplar. Without this, "done" is unfalsifiable.

## Topics (proposed — pick or replace)

1. **`eval/01-deeper-itself.md`** — "Why does this project exist?" Expected bedrock category: `stated-value`. Budget: ≤ 6 rounds. Exemplar: "Because no existing interview skill enforces single-thread drilling — they all include explicit anti-tunneling guards, and root-cause work needs the opposite."

2. **`eval/02-merge-conflict.md`** — "A specific merge conflict keeps coming back in our auth module." Expected: `prior-decision` or `constraint` (likely the team's branching model). Budget: ≤ 8.

3. **`eval/03-latency-regression.md`** — "p99 doubled last week." Expected: `empirical` or `constraint`. Budget: ≤ 10.

4. **`eval/04-feature-pushback.md`** — "Why won't engineering build this feature?" Expected: `stated-value` or `prior-decision`. Budget: ≤ 8.

5. **`eval/05-anti-test.md`** — A topic the user expects to NOT reach bedrock in budget (stress test of the hard-cap path). Expected: hard cap triggers, partial trace emitted, lowest unresolved claim flagged.

## File format per topic

```markdown
# Eval topic <N>: <slug>

## Starting claim (one sentence)
<...>

## Expected bedrock category
<one of the six>

## Round budget
<= N

## Exemplar bedrock line (for grading)
<one sentence>

## Grading rubric (binary)
- [ ] Round count <= budget OR hard-cap path exercised correctly
- [ ] Bedrock category matches expected
- [ ] No verbatim refused-detour appears in chain
- [ ] depth-trace artifact exists and has all required sections
- [ ] Source tags present on every claim
```

## Acceptance

- 5 topic files exist under `eval/`.
- Running `/deeper` on each topic produces a `depth-trace-*.md` that passes the grading rubric by user judgment.
- Results recorded in `workflow/status.md` as `verified` once all five pass.

## Constraints

- Eval topics must be real (something the user actually cares about), not synthetic. Synthetic topics don't expose the failure modes that matter.
