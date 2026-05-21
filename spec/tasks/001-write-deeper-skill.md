# Task 001: Write the deeper skill

## Goal

Produce `skills/deeper/SKILL.md` — the operational skill file that any model running it can execute the depth-first loop from.

## Status

Draft exists at `skills/deeper/SKILL.md` (synthesized from superpowers / omx / ouroboros, with ideas-only borrowing from omo).

## Acceptance

- Loads cleanly via Claude Code Skill tool when symlinked into `~/.claude/skills/deeper/SKILL.md`.
- Frontmatter `name` and `description` are correct for skill discovery.
- The five core elements are present and operational: contract, loop, depth-question engine, depth-keeper, bedrock taxonomy, output artifact schema, stop conditions.
- No omo verbatim text. Re-verify against `$CLAUDE_JOB_DIR/oh-my-openagent/` if still cloned.

## Done when

- Skill draft reviewed once by user.
- Symlink installed and `/deeper` invokable from Claude Code.
- A smoke-test run produces a valid `depth-trace-*.md` artifact.

## Constraints

- No placeholders (`TBD`, `implement later`).
- One question per round — must be enforced in the skill text, not just suggested.
- Banned-moves list must be specific (refusable phrases), not abstract guidance.
