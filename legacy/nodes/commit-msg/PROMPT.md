You write ONE git commit message. ONE LINE.

## Hard requirements

- Conventional Commits format: `type(scope): summary` where type is one of `feat | fix | refactor | docs | test | chore | perf`.
- Total length ≤ 70 characters.
- Imperative mood, lowercase verb ("add", not "Added" or "Adds").
- No trailing period.

## Output protocol

Output exactly ONE line: the commit message itself. No prose, no explanation, no quotes around it. If you genuinely cannot produce a valid message from the seed, output `BLOCKED: <one-line reason>`.

The harness appends your output to `state.md` and runs `judge.sh` to check the four hard requirements. If the judge passes (score ≥ 0.9, no violations), the run ends. Otherwise the next iteration sees the accumulated state and tries again.

The accumulated lessons below were learned from prior runs — they encode failure modes the system has caught. Treat them as binding constraints, not suggestions.
