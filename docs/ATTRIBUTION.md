# Attribution

`deeper` synthesizes patterns from four open-source interview / intent-extraction frameworks. License posture varies — read this before lifting any **verbatim** text from upstream sources.

## Sources

### superpowers (Anthropic Claude plugins-official) — MIT

- Copyright (c) 2025 Jesse Vincent.
- Local install: `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0/`.
- Patterns lifted (verbatim text permitted under MIT, attribution retained):
  - **One question per round** discipline (`skills/brainstorming/`).
  - **No-placeholders rule** for output artifacts — no `TBD`, no `implement later`, no vague placeholders (`skills/writing-plans/`).
  - **Red-flags self-monitoring table** format (`skills/using-superpowers/`). Re-instantiated for `deeper`'s anti-patterns.

### oh-my-codex (omx) — MIT

- Local install: `~/code/oh-my-codex/`.
- Patterns lifted (verbatim text permitted under MIT, attribution retained):
  - **Pressure ladder** — example → assumption → boundary → root cause (`skills/deep-interview/`).
  - **Stage-priority discipline** — intent before constraints before implementation.
  - **"Stay on the same thread until one layer deeper"** posture — `deeper` takes this as a hard rule, not a preference.
  - Single-question-per-round, source-tagged transcripts.
- Also informs: `pegasus-init` (already-installed Claude skill) is itself an omx-rigor lift; `deeper` reuses some shape from it (single output artifact, explicit decision boundaries).

### ouroboros (Q00) — MIT

- Source: https://github.com/Q00/ouroboros.
- Copyright (c) 2025 Q00.
- Patterns lifted (verbatim text permitted under MIT, attribution retained):
  - **Source-tag protocol** — `[from-user]`, `[from-code]`, `[from-research]`, `[from-user][refined]`. Reused as-is.
  - **Ontologist 4Q** — "What IS this? Root cause or symptom? What must exist first? What are we assuming?" Reused as-is.
  - **Dialectic Rhythm Guard** — after 3 consecutive non-user turns, next must go to user.
  - **`breadth-keeper` agent** — explicitly **inverted** into `depth-keeper`. This is the single most load-bearing borrowing.
  - **Restate gate** — collapse to one sentence and require user confirmation before exit (in `deeper`: the bedrock-confirmation question).
  - **Stall-as-convergence-signal** — repeated generic answers treated as exit signal, not progress.
  - **Bedrock-as-axiom** taxonomy — refined from ouroboros's seed-readiness gate.

### oh-my-openagent (omo) — Sustainable Use License v1.0 (n8n-style)

- Source: https://github.com/code-yeongyu/oh-my-openagent (branch `dev`).
- **Restriction**: non-commercial / internal-business-only; modifications must carry notice; verbatim prompt text is restricted for commercial reuse.
- **Posture in `deeper`: ideas only, no verbatim text.** Specifically reimplemented in our own wording:
  - The idea of **smart binary questions** ("I see X, should I also do Y?") in place of open-ended "what do you want?". `deeper` enforces this as a pressure-ladder discipline.
  - The idea of a **turn-termination contract** with a banned-closer list. `deeper`'s Contract section is our own wording of this concept.
  - The idea of a **clearance checklist** before exit. `deeper`'s bedrock-confirmation step is our own structural cousin (single axiom + category, not a 6-box checklist).
- No prompt fragments from omo are copied. If you find any near-verbatim text in `skills/deeper/SKILL.md` against `oh-my-openagent`'s prompts, file an issue — we'll rewrite.

## Patterns deliberately NOT lifted

- **Multi-persona deliberation** (omx `ralplan` planner/architect/critic). Out of scope — `deeper` is single-thread.
- **Multi-dimension ambiguity sweep** (omx `deep-interview`'s 5-7 dimension scoring). Out of scope — `deeper` doesn't rotate dimensions.
- **Spec short-circuit** (omo). Not applicable — `deeper` always starts from a single claim, not a project brief.
- **8-way intent router** (omo). Over-engineered for a single-claim drill.
- **Diverge-then-converge** (superpowers `brainstorming` "propose 2-3 approaches"). Antithetical to `deeper`'s mission.

## Maintenance

When upstream sources update, re-check this file. The Sustainable Use License on omo in particular is the one most likely to drift — re-verify the license version (currently v1.0) and re-confirm that no verbatim borrowings exist.
