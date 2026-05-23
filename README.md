# deeper

A self-improving [ralph loop](https://ghuntley.com/ralph/) framework. One harness, pluggable nodes, lessons that compound across runs.

The marquee node is **deeper** itself — a depth-first interview that drills ONE claim to its bedrock (first principle / axiom / source of truth), exposed as a Claude Code slash command. Every existing interview skill (`superpowers:brainstorming`, `omx:deep-interview`, `pegasus-init`, `gstack:office-hours`, `ouroboros`) is built to *keep breadth* and fight tunneling. `deeper` does the opposite — it commits to one claim and refuses to widen until that claim reaches bedrock. The reference verification node, `commit-msg`, runs autonomously against a deterministic mock so the self-improvement loop is testable for free.

## The framework — ralph + structured feedback

A ralph loop re-injects the same prompt every iteration with fresh context. This repo wraps that with a feedback step that reads structured logs and promotes recurring rule violations to a binding-lessons file. Next run starts smarter without anyone editing the prompt by hand.

```
run N:    walk task   →  judge logs violations  →  feedback.sh aggregates
                                                          ↓
                                              promotes to BANS.md if recurring
                                                          ↓
run N+1:  model reads new BANS  →  behavior changes  →  better outcome
```

```
harness/
├── loop.sh          # one ralph run: read PROMPT+BANS+state → call $MODEL_CMD → judge → repeat until done or cap
├── feedback.sh      # read N recent runs' events.jsonl → promote repeated violations to BANS.md
├── meta-loop.sh     # run M ralph runs, calling feedback after each
└── lib/mock-model.sh   # deterministic state-machine fake — for $0 verification

node-contract.md     # what every node must provide: PROMPT.md, BANS.md, judge.sh, hard-cap.txt
nodes/<name>/        # node-specific files
runs/<name>/<id>/    # per-run artifacts: seed.md, state.md, events.jsonl, outcome.json
```

The harness is task-agnostic. It has no node-specific code. Plug in a node by satisfying `node-contract.md`. The model is whatever you put in `$MODEL_CMD` — `claude -p`, `gemini`, `codex exec`, a deterministic mock for tests, or (for the `deeper` node) a Claude Code orchestrator that dispatches a fresh subagent every round.

**Verified.** The `commit-msg` reference node starts at score 0.25 (3 hard-cap runs producing wrong-format, wrong-length, period-trailing output) and converges to score 1.0 in 1 round after 4 lessons accumulate in `BANS.md`. Trajectory recorded in `runs/commit-msg/`, summarized in `spec/tasks/004-self-improving-harness.md`.

## The marquee node — `/deeper`

A Claude Code slash command. Per round, a **fresh subagent** generates one targeted depth question from:

- the node prompt (`nodes/deeper/PROMPT.md` — pressure ladder + Ontologist 4Q)
- the binding lessons (`nodes/deeper/BANS.md` — accumulated "don't do this again" rules)
- the **ancestor chain only** (root → … → active claim — never siblings, never the whole tree)

You answer. The state mutates. Next round dispatches a new subagent with fresh context. The orchestrator (the main Claude session) does pure I/O + dispatch — it never reasons about your claim.

**Why per-round fresh subagent.** In a single long Claude session, context grows across rounds and the model starts rationalizing its own prior reasoning — the exact drift Huntley's ralph fixes. Per-round dispatch keeps each question generation **cold**: only PROMPT.md + BANS.md + the ancestor chain enter the subagent's context. The orchestrator stays pure I/O. This is the only known way to hold depth-first discipline across many rounds without drift.

## Mechanism — one drill, many rounds

```
●  "Why does X?"
└── ● "because A"
    ├── ● "A traces to design choice"
    │   └── ◆ [BEDROCK: prior-decision]
    └── ● "also: time pressure"
        └── ◆ [BEDROCK: stated-value]
```

Per round:

1. Read `tree.json`, find `cursor` (DFS-deepest open leaf).
2. Build the **ancestor chain** — root → … → cursor. NOT the whole tree, NOT siblings.
3. Dispatch fresh subagent with `PROMPT.md` + `BANS.md` + ancestor chain.
4. Subagent emits ONE depth question (pressure ladder / Ontologist 4Q).
5. User answers — free text `|` `BEDROCK:<cat>` `|` `BRANCH:<sibling>` `|` `STOP`.
6. Mutate `tree.json`:
   - **normal** → append child, cursor descends (deeper)
   - **BEDROCK** → close current leaf, cursor pops to next open leaf
   - **BRANCH** → append sibling under parent, cursor jumps (parallel cause)
7. Run `judge.sh`, append events. Done when `cursor=null` AND every leaf closed.

## How BANS.md shapes paths

BANS does **not** walk the tree directly — user answers + cursor rules do. BANS shapes the *questions* the subagent generates, which shapes the answers, which shapes the path. Indirect bias, compounding across runs.

Example: a `shallow-bedrock` violation (bedrock declared at depth < 2) fires in run 3 and run 5 → `feedback.sh` promotes it → run 6's subagent reads BANS and probes deeper before letting any bedrock candidate through → run 6's trees tend to close at depth 3+.

Path *bias*, not path *forcing*. Each run is still user-driven; the *quality distribution* of paths drifts toward less-shallow shapes.

## Quick demos

### Self-improvement loop, autonomous, $0

```bash
cd ~/code/deeper
MODEL_CMD="bash harness/lib/mock-model.sh" \
  bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 6 1
```

Watch `nodes/commit-msg/BANS.md` fill up and the run score climb from 0.25 to 1.0. The mock is a deterministic state machine — no LLM, no tokens. This is how the framework's self-improvement claim is verified.

### Depth-first interview — Claude Code skill (recommended)

Install (one-time):

```bash
mkdir -p ~/.claude/skills
ln -s ~/code/deeper/skills/deeper ~/.claude/skills/deeper
```

Two modes:

```
/deeper why does X keep happening?            # interactive — user answers each round
/deeper auto why does X keep happening?       # autonomous — A-subagent answers, orchestrator loops
```

**Interactive** (default): a fresh Q-subagent generates each depth question; you reply in chat with free text / `BEDROCK:<cat>` / `BRANCH:<sibling>` / `STOP`.

**Auto**: same Q-subagent, but a second A-subagent stands in for the human respondent and writes the answer. The orchestrator loops until done or `DEEPER_AUTO_CAP` (default 8 rounds). After each round it prints the cumulative dispatch tree via `nodes/deeper/render-dispatch.sh` so you watch the drill grow live. Useful for testing the harness, sanity-checking BANS evolution, or generating a candidate drill to edit later — not a replacement for interactive when the user is the source of truth.

State persists in `runs/deeper/<run-id>/tree.json`. Resume with `/deeper resume <run-id>`. Full orchestrator spec in `skills/deeper/SKILL.md`.

After a drill, the skill suggests running `bash harness/feedback.sh deeper` to roll the run's violations into BANS — closing the self-improvement loop.

### Depth-first interview — bash CLI (no Claude Code)

```bash
cd ~/code/deeper
MODEL_CMD="python3 nodes/deeper/model.py" \
  bash harness/loop.sh deeper nodes/deeper/sample-seed.md my-first-drill
bash nodes/deeper/render.sh runs/deeper/my-first-drill   # view the tree
```

This mode uses `model.py`'s mechanical "Why X?" prompt — no LLM, no targeted pressure-ladder questions. Same `tree.json` state files as the skill, so you can start in bash and resume in `/deeper`. Useful for offline, scripted, or smoke-test runs.

### Swap to real Claude on `commit-msg`

```bash
MODEL_CMD="claude -p" bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 3 1
```

Anything that reads a prompt on stdin and writes the response on stdout works — `gemini`, `codex exec`, etc.

## Repo layout

```
harness/                    # task-agnostic ralph + feedback loop (above)
node-contract.md            # what every node must provide

nodes/
├── deeper/                 # marquee node: depth-first interview
│   ├── PROMPT.md           # role + pressure ladder + Ontologist 4Q
│   ├── BANS.md             # accumulated lessons (read by subagent every round)
│   ├── model.py            # iteration-tree driver: mutates tree.json after each user reply
│   ├── judge.sh            # done = no open leaves; flags shallow-bedrock
│   ├── render.sh           # tree.json → human-readable view
│   ├── sample-seed.md
│   └── hard-cap.txt        # 20
└── commit-msg/             # reference verification node (autonomous, mock-driven)

skills/deeper/SKILL.md      # Claude Code orchestrator for the deeper node
runs/<node>/<run-id>/       # per-run state: seed.md, tree.json, state.md, events.jsonl, outcome.json
docs/ATTRIBUTION.md         # per-source IP posture (superpowers / omx / ouroboros MIT; omo ideas-only)
```

## Why this exists

1. **Skills written into long markdown drift as conversations accumulate.** Huntley's ralph fixes this by re-injecting the same prompt every iteration with fresh context. Combining ralph with a feedback loop over structured logs gives a system that genuinely improves run-over-run without anyone editing the prompt by hand. → the framework.
2. **Depth-first interviewing is missing.** Every existing interview skill explicitly fights tunneling. Root-cause work needs the opposite. → the `deeper` node.

## Status

See `workflow/status.md`.
