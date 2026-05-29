# deeper v1 (origins) — the bash ralph + feedback framework

This directory is the **original** implementation of deeper: a task-agnostic
[ralph loop](https://ghuntley.com/ralph/) harness plus the `/deeper` Claude Code
slash command. It is where the philosophy — *cold context per round, depth-first
to bedrock, disciplined termination, self-improvement via promoted lessons* — was
first built and proven.

**The live product is v2 (`deeper-native`) at the repo root.** v2 re-homes this
same philosophy onto the dynamic Workflow runtime, so the bash scaffolding here
(single-turn launcher loop, `judge.sh` exit-code signalling, `Monitor`, the cwd
contract) is no longer needed. See [`../README.md`](../README.md) and
[`../workflows/README.md`](../workflows/README.md).

This tree is kept as a **reference implementation and archive**, with its internal
layout preserved intact:

```
legacy/
├── harness/            # loop.sh · feedback.sh · meta-loop.sh · lib/mock-model.sh
├── node-contract.md    # what every node must provide
├── nodes/
│   ├── deeper/         # model.py · judge.sh · PROMPT*.md · BANS.md · ask.sh · answer.sh · fanout-loop.sh · render*.sh · format-events.py
│   └── commit-msg/     # reference verification node (autonomous, mock-driven)
├── skills/deeper/      # SKILL.md — the v1 /deeper orchestrator
├── tests/              # test-answer-mock.sh · test-fanout-loop-mock.sh (bash, $0)
├── spec/               # design + task specs
├── workflow/           # status.md (framework changelog)
└── runs/               # recorded run artifacts incl. the commit-msg 0.25→1.0 trajectory
```

## Running v1

The scripts resolve their own files via `$DEEPER` (default `~/code/deeper`).
Because this tree preserves the original relative structure, point `DEEPER` at
this `legacy/` directory and everything resolves as before:

```bash
export DEEPER=~/code/deeper/legacy

# self-improvement demo (deterministic mock, no LLM, $0)
MODEL_CMD="bash $DEEPER/harness/lib/mock-model.sh" \
  bash "$DEEPER/harness/meta-loop.sh" commit-msg "$DEEPER/nodes/commit-msg/sample-seed.md" 6 1

# bash CLI depth-first drill (no Claude Code)
MODEL_CMD="python3 $DEEPER/nodes/deeper/model.py" \
  bash "$DEEPER/harness/loop.sh" deeper "$DEEPER/nodes/deeper/sample-seed.md" my-first-drill

# bash test suites
bash "$DEEPER/tests/test-answer-mock.sh"        # 22 assertions on answer.sh
bash "$DEEPER/tests/test-fanout-loop-mock.sh"   # 31 assertions on the full Q→A loop
```

The `/deeper` **slash command** was installed by symlinking `skills/deeper`. After
this move that symlink target is `~/code/deeper/legacy/skills/deeper`; re-point it
to keep v1's `/deeper` working:

```bash
ln -sfn ~/code/deeper/legacy/skills/deeper ~/.claude/skills/deeper
```
