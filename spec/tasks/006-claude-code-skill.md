# Task 006: /deeper Claude Code slash command (v2 of the deeper node)

## Goal

Wrap the iteration-tree harness as a native Claude Code slash command (`/deeper`). The skill is the v2 of the deeper node: same state schema as v1, but with an LLM-generated depth question per round via subagent-per-round dispatch.

## What was built

- `skills/deeper/SKILL.md` — the new orchestrator skill (thin: dispatch + I/O + tree mutation; no content reasoning).
- `docs/deeper-v0-design.md` — preserved the original v0 design doc (the 205-line synthesis from 4 sources).
- `nodes/deeper/PROMPT.md` — upgraded from v1's minimal "use Why?" instructions to the rich question-engine content (pressure ladder, Ontologist 4Q, forbidden questions, bedrock taxonomy, RED FLAGS). The same file is now used by both v1 mechanical model and v2 skill subagent.
- `nodes/deeper/model.py` — added `DEEPER_ANSWER_FILE` env var support so the skill can pass user answers via file (avoids shell-quoting headaches with multiline / quoted user replies).
- `README.md` — added install + use sections for `/deeper`.

## Architecture (per round)

1. Orchestrator reads `tree.json`, walks to cursor, builds ancestor chain.
2. Dispatches Explore subagent with: PROMPT.md + BANS.md + ancestor chain + active claim. Subagent outputs ONE question.
3. Orchestrator shows the question to the user with the four-action reply menu (free text / BEDROCK:<cat> / BRANCH:<sibling> / STOP).
4. User replies. Orchestrator writes reply to a file, calls `model.py` with `DEEPER_ANSWER_FILE=<file>` — model.py mutates tree.json.
5. Orchestrator calls `judge.sh`, checks `done` from the latest event.
6. If done: render tree, write outcome.json, suggest `feedback.sh`. Else: increment N, loop.

## Why per-round dispatch (not in-session)

In-session execution lets the orchestrator's context accumulate across rounds, causing drift and rationalization of prior reasoning. Per-round dispatch keeps each question-generation cold: subagent sees PROMPT.md + BANS.md + ancestor chain only. Huntley's fresh-context principle made interactive.

## Acceptance

- [x] `skills/deeper/SKILL.md` written with full orchestrator instructions.
- [x] `nodes/deeper/PROMPT.md` upgraded with question-engine content.
- [x] `nodes/deeper/model.py` accepts `DEEPER_ANSWER_FILE` env var.
- [x] `docs/deeper-v0-design.md` preserves the synthesis design doc.
- [x] README install + use instructions added.
- [ ] Symlink installed (`ln -s ~/code/deeper/skills/deeper ~/.claude/skills/deeper`).
- [ ] First live `/deeper` invocation verified end-to-end (user-driven, post-deploy).

## Constraints

- Skill assumes `~/code/deeper/` install path (hardcoded). For broader distribution, a future task would resolve repo location dynamically (e.g. via env var or skill manifest).
- Subagent type is `Explore` (read-only). The orchestrator handles all writes via Bash + Write tools.
- `model.py` retains all three input modes: `DEEPER_ANSWER_FILE` (skill), `DEEPER_AUTO_ANSWER` (autonomous tests), `/dev/tty` (bash CLI). No backward-incompat change.

## Open questions for future work

- Should the v2 skill also run `feedback.sh` automatically on exit, or leave it as a user-suggested next step? Current: suggest.
- Should the AskUserQuestion tool be used for the four-action reply menu, or is the plain text prompt sufficient? Current: plain text (fewer clicks, matches bash UX, sidesteps AskUserQuestion's 4-option limit).
- Should `/deeper` accept additional flags like `--profile=quick|standard|deep` for different hard-caps? Future.
