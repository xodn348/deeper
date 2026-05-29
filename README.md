# deeper

![License](https://img.shields.io/badge/license-Sustainable%20Use%201.0-blue)

A self-improving [ralph loop](https://ghuntley.com/ralph/) for **depth-first interviewing** — it drills ONE claim to its bedrock (first principle / axiom / source of truth) instead of widening. Every other interview skill (`superpowers:brainstorming`, `omx:deep-interview`, `pegasus-init`, `gstack:office-hours`, `ouroboros`) is built to *keep breadth* and fight tunneling. deeper does the opposite: it commits to one claim and refuses to widen until that claim reaches bedrock — and it gets better run-over-run by promoting recurring mistakes into binding lessons.

> **Two ways to run it — same philosophy, same state shape (`tree.json`, DFS-to-bedrock).**
>
> - **v2 — [`deeper-native`](./workflows/README.md) (current, recommended).** The drill as a **native dynamic workflow**. One self-contained JS workflow runs the whole loop on Claude's orchestration runtime: cold per-round agents, a parallel skeptic gate, schema-typed termination, and a cross-run self-improvement store. **Start here.**
> - **v1 — the bash ralph + feedback framework (origins).** The original `/deeper` slash command plus a task-agnostic `harness/` (`loop.sh`, `feedback.sh`, deterministic mock). Still works, still installed by symlink; it's where the ideas were proven and the offline/CLI path. Kept as the reference implementation.
>
> v2 is v1's hand-built bash orchestration (single-turn launcher loop, `judge.sh` exit code as the done-signal, `Monitor`, a cwd contract) re-homed onto a runtime that provides all of that **natively** — so the scaffolding disappears and the failure modes it guarded against can't occur.

## Quick start (v2 — deeper-native)

```bash
# 1. clone
git clone https://github.com/xodn348/deeper.git ~/code/deeper

# 2. install the workflow (one-time symlink)
mkdir -p ~/.claude/workflows
ln -s ~/code/deeper/workflows/deeper-native.js ~/.claude/workflows/deeper-native.js
```

Then, inside Claude Code:

```
Workflow({ name: "deeper-native", args: { seed: "why does our checkout funnel keep regressing?" } })
```

The drill runs **Bootstrap → Drill/Verify → Evolve**, terminates when every leaf reaches a verified bedrock (or the cap), and persists lessons to `~/.deeper/runs/deeper-native/` so the next drill starts smarter. Verify the engine offline first ($0, no LLM):

```bash
node tests/test-drill-core.mjs   # 59 assertions
```

Full principle, architecture, args table, philosophy, and a *"how this differs from a vanilla dynamic workflow"* comparison live in **[`workflows/README.md`](./workflows/README.md)**.

## Philosophy (both versions)

1. **Cold context every round (ralph).** In a single long session, context grows and the model starts rationalizing its own prior reasoning — the exact drift Huntley's ralph fixes. deeper re-injects the same prompt with **fresh context** every round; only the node prompt + binding lessons + the *ancestor chain* (root → … → active claim, never siblings, never the whole tree) enter the generator's context.
2. **Depth-first to bedrock.** The cursor is always the DFS-deepest open leaf. A normal answer descends; a bedrock answer closes the leaf and pops to the next open one; a branch opens a parallel cause under the same parent. Done = no open leaves.
3. **Disciplined termination.** "Bedrock" means an axiom — a stated value, constraint, prior decision, external rule, identity, or empirical fact — not "I got bored." Shallow bedrock (depth < 2) is a flagged violation.
4. **Self-improvement flywheel.** A feedback step reads structured run logs and promotes recurring rule violations into a binding-lessons file. The next run reads those lessons and biases its questions away from the repeated mistake — improving the *quality distribution* of paths without anyone editing the prompt by hand.

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

1. Find `cursor` — the DFS-deepest open leaf.
2. Build the **ancestor chain** — root → … → cursor. NOT the whole tree, NOT siblings.
3. Generate ONE depth question from the node prompt + binding lessons + ancestor chain (pressure ladder / Ontologist 4Q).
4. Get an answer — descend (free text) `|` `BEDROCK:<cat>` `|` `BRANCH:<sibling>` `|` `STOP`.
5. Mutate the tree: **normal** → append child, descend · **BEDROCK** → close leaf, pop · **BRANCH** → append sibling, jump.
6. Judge + log. Done when `cursor=null` AND every leaf closed.

### How binding lessons shape paths

Lessons do **not** walk the tree directly — answers + cursor rules do. They shape the *questions*, which shape the answers, which shape the path. Indirect bias, compounding across runs. Example: a `shallow-bedrock` violation fires in run 3 and run 5 → feedback promotes it → run 6's generator probes deeper before letting any bedrock candidate through → run 6's trees close at depth 3+. Path *bias*, not path *forcing*.

## How deeper-native (v2) works

The dynamic Workflow tool **is** a deterministic orchestration runtime — exactly the thing v1 hand-builds in bash. `deeper-native` ([`workflows/deeper-native.js`](./workflows/deeper-native.js)) re-homes the philosophy above directly onto it and closes the self-improvement flywheel inside one workflow:

```
Bootstrap (load BANS) → Drill / Verify (cold Q/A + parallel skeptic gate) → Evolve (record · promote · persist)
```

What the runtime buys for free:

- **No orchestration race.** v1 needs a single-turn launcher loop ([ADR-002](./docs/ADR-002-main-session-orchestrator.md)) to dodge a `judge_result` wake race. A JS `while` loop has no turn boundaries, so that race cannot exist.
- **Reliable termination.** The answer is a **schema-typed discriminated union** (`descend | bedrock | branch | stop`). The answerer emits a *typed* bedrock — there is no prose-buried `BEDROCK:` for a string-prefix match to miss (the recognition failure that can leave a drill running to the cap; cf. [`examples/ecdsa-drift`](./examples/ecdsa-drift/)).
- **An adversarial gate.** Before a bedrock closes, `verify_fanout` skeptic agents run in `parallel()`; a majority-refute forces one more descent.
- **A pure, $0-tested core.** All DFS / judge / promotion logic is a pure engine ([`nodes/deeper/drill-core.mjs`](./nodes/deeper/drill-core.mjs)) with 59 offline assertions; agents do all filesystem I/O.
- **Automatic self-improvement.** Each drill promotes recurring violations to a persisted `BANS` store that the next drill's Bootstrap phase loads — v1's `feedback.sh` flywheel, run with no manual step.

It is the **autonomous** drill (v1's default `auto` mode) on the Workflow runtime — not a replacement for the interactive `/deeper` skill, which keeps `claude -p` / session auth. See **[`workflows/README.md`](./workflows/README.md)** for the full write-up.

## Examples — recorded runs

Two worked drills with full traces (tree, events, digest, outcome).

| Run | Seed | Outcome | What's interesting |
|---|---|---|---|
| [`examples/address-clustering`](./examples/address-clustering/) | "find a creative way to do address clustering well" | 50R · `auto_cap` · 0 violations | Practical → empirical → epistemic → meta-epistemic ladder; surfaces 7 actionable clustering ideas en route to limits |
| [`examples/ecdsa-drift`](./examples/ecdsa-drift/) | "solve ECDSA cryptocraphy scheme" | 50R · `auto_cap` · 1 violation | Cautionary case — clean math reduction (R1–R19) bottoms out at ZFC, then drifts into pure epistemology and **never closes a single leaf** (50 rounds, 0 bedrock). Exactly the non-termination v2's schema-typed bedrock answer is built to prevent |

Each folder contains `README.md` (phase-by-phase summary), `digest-r1-r50.md` (all Q/A pairs), `tree.json`, `events.jsonl`, `outcome.json`.

## v1 (origins) — the bash ralph + feedback framework

The original, proven implementation. A task-agnostic harness plus the `/deeper` slash command. Still fully functional and the path for offline / scripted / non-Claude-Code runs.

### Quick start (v1 skill)

```bash
mkdir -p ~/.claude/skills
ln -s ~/code/deeper/skills/deeper ~/.claude/skills/deeper
```

```
/deeper why does our checkout funnel keep regressing?
```

Defaults to ~10 rounds (override with `DEEPER_AUTO_CAP=50 /deeper …`), streams live progress, and persists state to `~/.deeper/runs/deeper/<run-id>/` — resume with `/deeper resume <run-id>`.

### The framework — ralph + structured feedback

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

The harness has no node-specific code. Plug in a node by satisfying `node-contract.md`. The model is whatever you put in `$MODEL_CMD` — `claude -p`, `gemini`, `codex exec`, a deterministic mock for tests, or (for the `deeper` node) a Claude Code orchestrator that dispatches a fresh subagent every round.

**Verified.** The `commit-msg` reference node starts at score 0.25 (3 hard-cap runs producing wrong-format, wrong-length, period-trailing output) and converges to score 1.0 in 1 round after 4 lessons accumulate in `BANS.md`. Trajectory recorded in `runs/commit-msg/`, summarized in `spec/tasks/004-self-improving-harness.md`.

### The `/deeper` slash command

A Claude Code slash command. Per round, a **fresh subagent** generates one targeted depth question from the node prompt (`nodes/deeper/PROMPT.md`), the binding lessons (`nodes/deeper/BANS.md`), and the **ancestor chain only**. You answer; the state mutates; the next round dispatches a new subagent with fresh context. The orchestrator (the main Claude session) does pure I/O + dispatch — it never reasons about your claim.

```
/deeper why does X keep happening?              # default — worktree-isolated auto drill
/deeper interactive why does X keep happening?  # human answers each round in chat
```

**Default (worktree auto):** the main session is a thin launcher. It sets up `$DEEPER_HOME/runs/deeper/<run-id>/`, then runs the round loop, firing a fresh `claude -p` subprocess per round for Q and another for A, feeding answers to `model.py`, running `judge.sh`, looping until done or `DEEPER_AUTO_CAP`. The done/continue decision uses only `judge.sh`'s exit code — never a re-read of the event log (the architectural guarantee against the wake race; see [ADR-002](./docs/ADR-002-main-session-orchestrator.md) and [ADR-003](./docs/ADR-003-claude-print-orchestrator.md)).

**Interactive:** the main session dispatches a fresh Q-subagent each round, asks you in chat, and ends its turn to await your reply. Use when the user is the source of truth.

Full orchestrator spec in `skills/deeper/SKILL.md`. After a drill, the skill suggests `bash harness/feedback.sh deeper` to roll the run's violations into BANS — closing the self-improvement loop.

### Self-improvement demo (autonomous, $0)

```bash
cd ~/code/deeper
MODEL_CMD="bash harness/lib/mock-model.sh" \
  bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 6 1
```

Watch `nodes/commit-msg/BANS.md` fill up and the run score climb from 0.25 to 1.0. The mock is a deterministic state machine — no LLM, no tokens. This is how the framework's self-improvement claim is verified.

### Depth-first interview — bash CLI (no Claude Code)

```bash
cd ~/code/deeper
MODEL_CMD="python3 nodes/deeper/model.py" \
  bash harness/loop.sh deeper nodes/deeper/sample-seed.md my-first-drill
bash nodes/deeper/render.sh runs/deeper/my-first-drill   # view the tree
```

Uses `model.py`'s mechanical "Why X?" prompt — no LLM. Same `tree.json` state files as the skill, so you can start in bash and resume in `/deeper`. Useful for offline, scripted, or smoke-test runs.

```bash
# any stdin→stdout model works on the commit-msg node, too:
MODEL_CMD="claude -p" bash harness/meta-loop.sh commit-msg nodes/commit-msg/sample-seed.md 3 1
```

<details>
<summary><strong>A-phase fanout (experimental)</strong> — five parallel investigator subagents per A-phase, with a termination gate and force-kill accounting</summary>

The legacy A-phase produces Aₖ from a single `claude -p` call. The fanout
A-phase replaces that single call with a **driver** that dispatches five
parallel investigator subagents (one per angle), gates synthesis on every
investigator reaching a terminal state, and force-kills stragglers past the
deadline. The driver lives at `nodes/deeper/answer.sh`; its system prompt is
`nodes/deeper/PROMPT.answer.md`.

The Q-phase is unchanged — one cold `claude -p` (haiku) emits one question.
Only the A-phase changes. The end-to-end Q→A drill is wrapped by
`nodes/deeper/fanout-loop.sh`.

#### Data flow per round

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

#### Termination gate

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

#### Files

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

#### Call accounting per round

```
ask.sh    : claude -p × 1   — haiku   (Q)
answer.sh : claude -p × 1   — opus    (A-driver)
            └─ Agent × 5    — opus    (investigators, parallel)
─────────────────────────────────────────────────────
total LLM calls / round  =  haiku × 1  +  opus × 6
HARD_CAP = 12            →  worst-case haiku × 12 + opus × 72
```

#### Tunables

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

#### Run the full fanout drill

```bash
cd ~/code/deeper
bash nodes/deeper/fanout-loop.sh nodes/deeper/sample-seed.md my-fanout-run
bash nodes/deeper/render.sh           runs/deeper/my-fanout-run   # tree view (if model.py path)
bash nodes/deeper/render-dispatch.sh  runs/deeper/my-fanout-run   # dispatch view

# mock test suites (no LLM, $0):
bash tests/test-answer-mock.sh        # 22 assertions on answer.sh
bash tests/test-fanout-loop-mock.sh   # 31 assertions on the full Q→A loop
```

**Status.** Draft. `fanout-loop.sh` orchestrates the full Q→A drill end-to-end.
Termination: `STOP` / `BEDROCK:` in the answer, two consecutive `BLOCKED:`
rounds, or `DEEPER_HARD_CAP`. Integration with the `/deeper` orchestrator is a
follow-up — for now auto-mode still spawns the legacy single-A-subagent per round.

</details>

## Repo layout

```
workflows/                  # v2 — the drill as a native dynamic workflow
├── deeper-native.js        # the workflow (Bootstrap→Drill→Verify→Evolve)
└── README.md               # deeper-native: principle, architecture, quick start, vs vanilla
tests/test-drill-core.mjs   # $0 engine + promotion + sync-guard suite (59 assertions)

harness/                    # v1 — task-agnostic ralph + feedback loop
node-contract.md            # what every node must provide

nodes/
├── deeper/                 # marquee node: depth-first interview
│   ├── PROMPT.md           # role + pressure ladder + Ontologist 4Q
│   ├── BANS.md             # accumulated lessons (read by the generator every round)
│   ├── model.py            # iteration-tree driver: mutates tree.json after each reply
│   ├── drill-core.mjs      # v2 pure engine (DFS state machine + promoteBans)
│   ├── judge.sh            # done = no open leaves; flags shallow-bedrock
│   ├── render.sh           # tree.json → human-readable view
│   ├── sample-seed.md
│   └── hard-cap.txt        # 20
└── commit-msg/             # reference verification node (autonomous, mock-driven)

skills/deeper/SKILL.md      # v1 Claude Code orchestrator for the deeper node
runs/<node>/<run-id>/       # per-run state: seed.md, tree.json, state.md, events.jsonl, outcome.json
docs/ATTRIBUTION.md         # per-source IP posture (superpowers / omx / ouroboros MIT; omo ideas-only)
```

## Why this exists

1. **Skills written into long markdown drift as conversations accumulate.** Huntley's ralph fixes this by re-injecting the same prompt every iteration with fresh context. Combining ralph with a feedback loop over structured logs gives a system that genuinely improves run-over-run without anyone editing the prompt by hand.
2. **Depth-first interviewing is missing.** Every existing interview skill explicitly fights tunneling. Root-cause work needs the opposite. → the `deeper` node.
3. **The orchestration belongs in a runtime, not in bash.** v1 proved the philosophy by hand-building a deterministic loop in shell. v2 (`deeper-native`) moves that loop onto the dynamic Workflow runtime, where the scaffolding is native and the races it guarded against can't occur.

## Status

v2 (`deeper-native`) is the recommended path; engine is covered by 59 offline assertions. v1 remains fully functional. See `workflow/status.md` for the framework changelog.

## License

Source-available under the **Sustainable Use License v1.0** (see
[`LICENSE.md`](LICENSE.md)). Internal business use and non-commercial /
personal use are permitted. Commercial redistribution — including offering
deeper as a hosted service or embedding it in a paid product — requires a
separate commercial license from Junhyuk Lee.

Third-party components incorporated into deeper retain their original
licenses; see [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).
