# Status

Phase: harness-verified

Updated: 2026-05-22T06:20:00Z

## What's done

- 4-source interview pattern audit (superpowers / omx / oh-my-openagent / ouroboros).
- `skills/deeper/SKILL.md` v0 draft (single-thread depth interview).
- `docs/ATTRIBUTION.md` IP posture per source.
- **`harness/{loop,feedback,meta-loop}.sh` + `harness/lib/mock-model.sh`** — task-agnostic ralph + feedback infrastructure.
- **`node-contract.md`** — what every node must provide.
- **`nodes/commit-msg/`** — reference node (autonomous, deterministic mock).
- **End-to-end demo: 0.25 → 1.0 across 6 meta-iterations**, 4 lessons auto-promoted to BANS.md, recorded in `runs/commit-msg/`.

## What's next

- Task 005 (to write): port `skills/deeper/SKILL.md` into `nodes/deeper/` shape — split into PROMPT.md (single-iteration instructions) + judge.sh (human-in-loop reader) + a `depth-trace`-shaped state.md format.
- Decide: real-LLM demo for `commit-msg` (swap `MODEL_CMD="claude -p"`) before or after `deeper` node port.
- Optional: lessons consolidator (LLM pass over BANS.md to merge duplicates) once BANS files start growing.

## Verification path

- Harness: verified end-to-end with mock. See `spec/tasks/004-self-improving-harness.md` for trajectory.
- `deeper` skill: still unverified. Verification deferred until ported into harness shape so it runs the same way as `commit-msg`.
