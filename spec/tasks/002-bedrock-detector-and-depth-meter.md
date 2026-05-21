# Task 002: Bedrock detector and depth meter — formal rules

## Goal

Lock down the two scoring/decision components so the skill's behavior is reproducible across models.

## Bedrock detector

A claim is bedrock if and only if it falls into one of six categories (see `skills/deeper/SKILL.md` § Bedrock taxonomy). The detector is a question, not a heuristic:

> If the next `Why?` is asked and the honest answer is one of {"because we chose to", "because physics/economics/time", "because the law", "because the contract", "because the math", "because the measurement (cited)"}, this is bedrock.
> Otherwise it is still a claim. Drill.

The user, not the agent, makes the final call. The agent's role is to propose a candidate and capture the category tag.

## Depth meter

Round-by-round `depth_delta` table — copied into SKILL.md, single source of truth here:

| Signal | Δ |
|---|---|
| Surfaces a previously hidden assumption | +0.30 |
| Names a concrete boundary / failure case | +0.30 |
| Cites a concrete instance (file:line, log line, fact, user behavior) | +0.20 |
| Hits a candidate axiom | +0.40 |
| Restates the prior claim in new words | 0 |
| Opens a new topic | -0.50 |
| Generic / class-level answer where one example was requested | -0.10 |

Gating rules:

- Meter is **informational** — does not by itself trigger exit.
- Three consecutive rounds with `delta <= 0` triggers a stall check: ask the user to continue / accept lowest / abort.
- Hard cap at 12 rounds regardless of meter.

## Acceptance

- Both components specified in `skills/deeper/SKILL.md` exactly as written here.
- 3 of the 5 evaluation topics (task 003) exercise the stall check OR the hard cap path, not just the happy path.

## Constraints

- No additional categories of bedrock without updating `docs/ATTRIBUTION.md` (ouroboros's seed-readiness taxonomy is the parent).
- No automatic bedrock declaration — always user-confirmed.
