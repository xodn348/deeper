# deeper

Originally: a depth-first interview agent that drives one claim to bedrock without expanding the discussion.

As of this commit: also the substrate for a self-improving agent harness built on Huntley's ralph loop. `deeper` is now **one node** in a general `ralph → feedback → ralph → feedback` system. The interview is the marquee node; the harness underneath is the load-bearing infrastructure.

## Two layers

### Layer 1 — self-improving harness (built, verified end-to-end)

```
harness/
├── loop.sh          # one ralph run: read PROMPT+BANS+state → call $MODEL_CMD → judge → repeat until done or cap
├── feedback.sh      # read N recent runs' events.jsonl → promote repeated violations to BANS.md
├── meta-loop.sh     # run M ralph runs, calling feedback after each
└── lib/mock-model.sh   # deterministic state-machine fake, for free demos
node-contract.md     # what every node must provide
nodes/<name>/        # node-specific: PROMPT.md, BANS.md, judge.sh, hard-cap.txt
runs/<name>/<id>/    # per-run artifacts: seed.md, state.md, events.jsonl, outcome.json
```

The harness is task-agnostic. It uses no node-specific code. Plug in a node by satisfying `node-contract.md`.

**Verified.** The `commit-msg` reference node starts at score 0.25 (3 hard-cap runs producing the wrong-format, wrong-length, period-trailing output) and converges to score 1.0 in 1 round after 4 lessons accumulate in `BANS.md`. Trajectory recorded in `runs/commit-msg/` and summarized in `spec/tasks/004-self-improving-harness.md`.

### Layer 2 — deeper, the depth-first interview node (skill draft only, not yet refactored into the harness)

```
skills/deeper/SKILL.md   # the original Claude Code skill — operational core, hand-runnable
docs/ATTRIBUTION.md      # per-source IP posture (superpowers / omx / ouroboros MIT; omo ideas-only)
```

This needs to be ported into the `nodes/deeper/` shape so it can ride the harness. The judge for `deeper` is the user (human-in-loop), not a script — the harness already supports this via a `judge.sh` that simply prompts on stdin.

## Why this exists

1. **Depth-first interviewing is missing.** Every existing interview skill (`superpowers:brainstorming`, `omx:deep-interview`, `pegasus-init`, `gstack:office-hours`, `ouroboros`) explicitly fights tunneling. We need the opposite for root-cause work. → Layer 2.
2. **Skills written into long markdown drift as conversations accumulate.** Huntley's ralph fixes this by re-injecting the same prompt every iteration with fresh context. Combining ralph with a feedback loop over structured logs gives you a system that genuinely improves run-over-run without anyone editing the prompt by hand. → Layer 1.

## Quick demo (no LLM cost)

```bash
cd ~/code/deeper
MODEL_CMD="bash harness/lib/mock-model.sh" \
  bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 6 1
```

Watch BANS.md fill up and the run score climb from 0.25 to 1.0.

## Swap to real Claude

```bash
MODEL_CMD="claude -p" bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 3 1
```

(Anything that reads a prompt on stdin and writes the response on stdout works — `gemini`, `codex exec`, etc.)

## Status

See `workflow/status.md`.
