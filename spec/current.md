# Project spec — deeper

## One-sentence mission

A depth-first interview agent that drives a single claim to bedrock without ever expanding the discussion.

## Goal (original, in user's words)

논의를 확장하는게 아니고 깊이를 지구끝까지 파고드는 에이전트.

## Goal (operational restatement)

Build an interview skill (`deeper`) for Claude Code / Codex / OpenAgent that, given any starting claim, picks one thread and drills `claim → why → deeper why → ... → bedrock`, refusing breadth detours, and emits one `depth-trace-*.md` artifact whose top line is the discovered bedrock.

## Why this exists

Every interview framework available locally — `superpowers:brainstorming`, `omx:deep-interview`, `pegasus-init`, `gstack:office-hours`, `ouroboros` — explicitly **fights** runaway depth. Ouroboros even ships a `breadth-keeper` agent that "forces periodic zoom-outs before the interview overfits one detail." That guard is correct for general-purpose discovery and wrong for root-cause investigation. `deeper` removes that guard and replaces it with a `depth-keeper` that does the opposite.

## Scope (in)

- `skills/deeper/SKILL.md` — the operational skill, callable from Claude Code (`/deeper`) and reusable as a prompt in Codex/OpenAgent.
- A single output artifact format: `depth-trace-<slug>-<ts>.md`.
- A bedrock-detection rule: what counts as an axiom (user-stated value, physical/economic constraint, deliberate design choice, external regulation, mathematical identity). Anything else is still a claim and gets drilled.
- A `depth_meter` scoring rubric so each round measurably advances or the loop stops.
- A `depth-keeper` micro-agent (inverted `breadth-keeper` from ouroboros) that triggers when a turn opens a new topic, and refuses with a re-anchor message.
- Banned-moves table: the breadth phrases the agent must refuse.
- An evaluation harness: ≥5 sample topics with expected bedrock-line + max-rounds budget.

## Scope (out — non-goals)

- Not a project-briefing tool. `pegasus-init` already covers that.
- Not a planning / decomposition tool. `superpowers:writing-plans`, `omx:plan`, `prometheus` cover that.
- Not a debate / multi-persona deliberation tool. `ralplan` covers that.
- Not a research / exploration tool. `omx:autoresearch`, `librarian` cover that.
- No multi-thread management. If multiple threads exist, the agent picks one and parks the rest with one line each in the artifact's "Open shallow threads" section.
- No mid-interview implementation. Reaching bedrock is the deliverable; what to do about it is the next skill's job.

## Decision boundaries

- The agent decides which of the user's recent claims to drill if not specified.
- The agent decides which depth-question rung to use (`example | assumption | boundary | root-cause`).
- The agent does **not** decide that something is bedrock — the user confirms each candidate bedrock explicitly before exit.
- The agent does **not** decide to switch topics. A topic switch always requires a user gate.

## Done when

- `skills/deeper/SKILL.md` exists and the skill loads cleanly when invoked from Claude Code.
- The 5 evaluation topics under `eval/` each produce a depth-trace whose bedrock line is judged correct (by the user) and whose round count is `<= budget`.
- `docs/ATTRIBUTION.md` credits superpowers (MIT, Jesse Vincent), omx (MIT), ouroboros (MIT, Q00), with a note that omo (oh-my-openagent, Sustainable Use License) contributed ideas only — no verbatim text.
- `workflow/status.md` reports `verified` against the eval set.

## Source-of-truth files

- This file.
- `spec/tasks/*.md` — task-by-task spec.
- `spec/updates.md` — append-only change log when the mission shifts.
- `workflow/status.md` — live phase.
- `skills/deeper/SKILL.md` — the skill itself once written.
- `eval/` — evaluation topics + expected bedrock lines.
