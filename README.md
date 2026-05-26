# deeper

![License](https://img.shields.io/badge/license-Sustainable%20Use%201.0-blue)

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
/deeper why does X keep happening?              # default — worktree-isolated auto drill
/deeper interactive why does X keep happening?  # legacy — human answers each round in chat
```

**Default (worktree auto)**: the main session is a thin launcher. It sets up `$DEEPER_HOME/runs/deeper/<run-id>/` (default `~/.deeper/runs/deeper/<run-id>/`), then dispatches ONE Agent call with `isolation: "worktree"` and `subagent_type: "general-purpose"`. That orchestrator subagent runs the entire drill inside an isolated worktree — spawning fresh Q-subagents and A-subagents per round (Agent tool + `Explore`), feeding answers to `model.py`, running `judge.sh`, looping until done or `DEEPER_AUTO_CAP` (default 8). When it returns, the main session surfaces the final dispatch tree + tree render + outcome.json. The main session never sees the claim content and never falls back to answering. Round 1 cannot "end the session" because there is no per-round turn boundary in the main session — the whole drill is one Agent dispatch.

**Interactive (legacy)**: the main session is the orchestrator, dispatching a fresh Q-subagent each round, asking you in chat, ending its turn to await your reply. Use when the user is the source of truth and the system needs your answers to walk the tree.

State persists in `$DEEPER_HOME/runs/deeper/<run-id>/tree.json`. Resume with `/deeper resume <run-id>`. Full orchestrator spec in `skills/deeper/SKILL.md`.

## A-phase fanout (experimental)

The legacy A-phase produces Aₖ from a single `claude -p` call. The fanout
A-phase replaces that single call with a **driver** that dispatches five
parallel investigator subagents (one per angle), gates synthesis on every
investigator reaching a terminal state, and force-kills stragglers past the
deadline. The driver lives at `nodes/deeper/answer.sh`; its system prompt is
`nodes/deeper/PROMPT.answer.md`.

The Q-phase is unchanged — one cold `claude -p` (haiku) emits one question.
Only the A-phase changes. The end-to-end Q→A drill is wrapped by
`nodes/deeper/fanout-loop.sh`.

### Data flow per round

```
   seed.md ─┐
            ▼
   ┌──────────────┐    Qₖ    ┌─────────────────────────────────┐    Aₖ    ┌──────┐
   │   ask.sh     │ ───────▶ │  answer.sh  (A-driver, opus)    │ ───────▶ │Judge │
   │ (cold,haiku) │          │                                 │          └──────┘
   └──────────────┘          │   ┌─────────────────────────┐   │
        ▲                    │   │  Agent × 5 (parallel)   │   │
        │                    │   │  sub-A₁ … sub-A₅ (opus) │   │
        │                    │   └────────────┬────────────┘   │
        │                    │                │ outputs[5]     │
        │                    │                ▼                │
        │                    │   [ termination gate +          │
        │                    │     improvements.md append +    │
        │                    │     simple synthesis ]          │
        │                    └────────────────┬────────────────┘
        │                                     │
        └─────── ancestor chain (Q₁,A₁,…,Qₖ₋₁,Aₖ₋₁) ◀
```

### Termination gate

Before synthesis, every investigator must have reached a terminal state.
Any subagent still running at the deadline is:

1. Inspected via `TaskGet` / `TaskOutput` for last activity.
2. Classified into a fixed reason vocabulary:
   `context_limit` · `tool_loop` · `stuck_on_permission` · `network_timeout`
   · `ambiguous_task` · `unknown`.
3. Force-killed via `TaskStop`.
4. Appended to `runs/<run-id>/improvements.md` AND
   `nodes/deeper/IMPROVEMENTS.md` for later review and BANS promotion.

If `force_killed.length >= DEEPER_KILL_THRESHOLD` (default 3) the driver
emits `BLOCKED: …` to stdout and the round fails. Otherwise the survivors
are synthesized into one prose answer with inline annotations for the
failed angles.

### Files

```
nodes/deeper/
├── ask.sh                  # Q-phase (DEEPER_ASK_MOCK env added for tests)
├── answer.sh               # A-driver shell wrapper
├── fanout-loop.sh          # full Q→A drill loop using ask.sh + answer.sh
├── PROMPT.answer.md        # A-driver system prompt
├── IMPROVEMENTS.md         # global force-kill accumulator

$DEEPER_HOME/runs/deeper/<run-id>/  (default ~/.deeper/runs/deeper/<run-id>/)
├── seed.md
├── ancestors.md            # running root + (Q₁/A₁ … Qₖ/Aₖ) chain
├── state.md
├── events.jsonl            # round_start / question_emitted / answer_emitted /
│                           #   subagent_completed / subagent_force_killed /
│                           #   loop_done / loop_aborted
├── q-r<round>.txt          # raw Qₖ
├── a-r<round>.txt          # raw Aₖ (synthesis or BLOCKED line)
├── answer-r<round>.json    # verbatim JSON envelope from the A-driver
├── improvements.md         # run-scoped force-kill log
└── outcome.json            # final {status, rounds, exit_reason}

tests/
├── test-answer-mock.sh        # 22 assertions on answer.sh in isolation
└── test-fanout-loop-mock.sh   # 31 assertions on the full Q→A loop
```

### Call accounting per round

```
ask.sh    : claude -p × 1   — haiku   (Q)
answer.sh : claude -p × 1   — opus    (A-driver)
            └─ Agent × 5    — opus    (investigators, parallel)
─────────────────────────────────────────────────────
total LLM calls / round  =  haiku × 1  +  opus × 6
HARD_CAP = 12            →  worst-case haiku × 12 + opus × 72
```

### Tunables

| Env var                       | Default | Purpose                                      |
|-------------------------------|---------|----------------------------------------------|
| `DEEPER_Q_MODEL`              | `haiku` | Q-subagent model                             |
| `DEEPER_ANSWER_MODEL`         | `opus`  | A-driver model                               |
| `DEEPER_SUB_MODEL`            | `opus`  | Investigator-subagent model                  |
| `DEEPER_SUB_DEADLINE`         | `180`   | Per-subagent deadline (seconds)              |
| `DEEPER_FANOUT`               | `5`     | Investigator count                           |
| `DEEPER_KILL_THRESHOLD`       | `3`     | ≥ N force-kills → round emits `BLOCKED:`     |
| `DEEPER_HARD_CAP`             | `12`    | Max rounds per drill                         |
| `DEEPER_ASK_MOCK`             | unset   | If set, `ask.sh` emits this verbatim (tests) |
| `DEEPER_ANSWER_MOCK`          | unset   | If set, `answer.sh` emits this verbatim JSON envelope (tests) |
| `DEEPER_GLOBAL_IMPROVEMENTS`  | unset   | Override path for the global accumulator file (tests use this for isolation) |

### Run the full fanout drill

```bash
cd ~/code/deeper
bash nodes/deeper/fanout-loop.sh nodes/deeper/sample-seed.md my-fanout-run
bash nodes/deeper/render.sh           runs/deeper/my-fanout-run   # tree view (if model.py path)
bash nodes/deeper/render-dispatch.sh  runs/deeper/my-fanout-run   # dispatch view
```

Run the mock test suites (no LLM, $0):

```bash
bash tests/test-answer-mock.sh        # 22 assertions on answer.sh
bash tests/test-fanout-loop-mock.sh   # 31 assertions on the full Q→A loop
```

### Status

Draft. `fanout-loop.sh` orchestrates the full Q→A drill end-to-end using
`ask.sh` for Q-phase and `answer.sh` for A-phase. Termination conditions:
`STOP` / `BEDROCK:` in the answer, two consecutive `BLOCKED:` rounds,
or `DEEPER_HARD_CAP`.

Integration with the existing `/deeper` slash command orchestrator (see
`skills/deeper/SKILL.md`) is a follow-up — for now the auto-mode orchestrator
still spawns the legacy single-A-subagent per round.

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

## Examples — recorded runs

Two worked drills with full traces (tree, events, digest, outcome).

| Run | Seed | Outcome | What's interesting |
|---|---|---|---|
| [`examples/address-clustering`](./examples/address-clustering/) | "find a creative way to do address clustering well" | 50R · `auto_cap` · 0 violations | Practical → empirical → epistemic → meta-epistemic ladder; surfaces 7 actionable clustering ideas en route to limits |
| [`examples/ecdsa-drift`](./examples/ecdsa-drift/) | "solve ECDSA cryptocraphy scheme" | 50R · `auto_cap` · 1 violation | Cautionary case — math reduction (R1–R19) bottoms out cleanly at ZFC, then drifts into pure epistemology. Three `BEDROCK:<cat>` declarations failed to terminate the drill (real bug in `model.py`'s closure logic) |

Each folder contains `README.md` (phase-by-phase summary), `digest-r1-r50.md` (all Q/A pairs), `tree.json`, `events.jsonl`, `outcome.json`.

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

## License

Source-available under the **Sustainable Use License v1.0** (see
[`LICENSE.md`](LICENSE.md)). Internal business use and non-commercial /
personal use are permitted. Commercial redistribution — including offering
deeper as a hosted service or embedding it in a paid product — requires a
separate commercial license from Junhyuk Lee.

Third-party components incorporated into deeper retain their original
licenses; see [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).
