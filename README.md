# deeper

A depth-first interview agent. It does **not** expand the discussion. It picks one thread and drills until bedrock — root cause, axiom, physical constraint, or deliberate design choice — then stops.

Most existing interview frameworks (`superpowers:brainstorming`, `omx:deep-interview`, `ouroboros`) include explicit anti-tunneling guards (e.g. ouroboros has a `breadth-keeper` agent). `deeper` is what you get when you flip those guards. The single-thread tunneling **is** the feature.

## Core idea

```
loop:
  q = next_depth_question(current_claim)   # Ontologist 4Q + pressure ladder
  a = ask_user(q)                          # one question per round, no batching
  tag a with [from-user | from-code | from-research]
  if a opens a new topic:  REFUSE and re-anchor
  depth_meter += depth_delta(a)
  if bedrock_reached(a) and user_confirms_axiom(): EXIT
```

Output is a single artifact: `depth-trace-<topic>-<ts>.md` — a chain of `claim → why → deeper why → ... → bedrock`, with source tags, refused breadth detours logged, and a one-sentence bedrock declaration at the top.

## Why not just use one of the existing skills

| Skill | Posture | Problem for our use |
|---|---|---|
| `superpowers:brainstorming` | Diverge then converge ("propose 2-3 approaches") | Expansion is built in |
| `omx:deep-interview` | Multi-dimension ambiguity sweep | Rotates dimensions; intentionally broad |
| `pegasus-init` | 15-question Socratic for project briefing | Whole-project scope, not single-claim drill |
| `gstack:office-hours` | YC-style six forcing questions | Strategic, not root-cause |
| `ouroboros` | Has a depth-first Ontologist but a `breadth-keeper` overrides it | Anti-tunneling is enforced |

`deeper` borrows freely from all of them but inverts the breadth gate.

## Status

Pre-implementation. See `spec/current.md` for the locked mission, `spec/tasks/` for next steps, the skill draft at `skills/deeper/SKILL.md`, and attributions in `docs/ATTRIBUTION.md`.
