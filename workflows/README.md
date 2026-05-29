# deeper-native — depth-first drilling as a native dynamic workflow

> deeper's philosophy — **ralph cold loop · depth-first to bedrock · disciplined termination** — implemented directly on the dynamic Workflow runtime. No `claude -p`, no filesystem inside the loop, no race-avoidance scaffolding.

`deeper` (the skill) hand-builds a deterministic orchestration runtime in bash: a single-turn launcher loop ([ADR-002](../docs/ADR-002-main-session-orchestrator.md)) to dodge a `judge_result` notification race, a `judge.sh` exit code treated as the only authoritative done-signal, `Monitor` arming for live progress, a cwd transactional contract. **All of that is scaffolding to simulate what a deterministic orchestration runtime gives for free.** The dynamic Workflow tool *is* that runtime. `deeper-native` keeps the three philosophies and drops the scaffolding — and fixes deeper's one confirmed production bug for free (see [Principle §3](#3-schema-typed-termination--the-bug-fix)).

It is not a replacement for the interactive `/deeper` skill. It is the **autonomous drill** (deeper's default `auto` mode) re-homed onto the runtime it always wanted. See [Scope](#scope).

---

## Philosophy (inherited from deeper)

Every other interview framework (`brainstorming`, `deep-interview`, `office-hours`, `ouroboros`) is built to **keep breadth** and fight tunneling. `deeper` inverts that: it commits to ONE claim and refuses to widen until that claim reaches bedrock. `deeper-native` carries the same three commitments.

1. **Ralph cold re-injection.** A [ralph loop](https://ghuntley.com/ralph/) re-injects the same prompt every iteration with *fresh context*. In a long session, context accumulates and the model starts rationalizing its own prior reasoning — adversarial pressure ("where does this break?") silently degrades into self-consistency preservation. Each round must be **cold**: only the prompt + accumulated lessons + the ancestor chain enter the model. Nothing else.
2. **Depth-first to bedrock.** Drill one claim straight down. The cursor is always the DFS-deepest open leaf. A normal answer descends; a bedrock declaration closes the leaf and pops to the next open one; a branch opens a parallel cause. Never "what else?", never "compare to X", never widen.
3. **Disciplined termination.** A drill is *done* when every leaf is closed at a bedrock (axiom / physical constraint / deliberate prior decision / external rule / identity / measured fact). Not when the model feels finished, not at an arbitrary turn — when the tree says so.

---

## Principle (how it runs on the Workflow runtime)

### 1. Cold context per round
Each round rebuilds the agent prompt from scratch: `PROMPT + bans + ancestorChain(cursor)`. The script holds the entire history in memory — and **deliberately does not pass it forward.** That restraint *is* ralph. `agent()` is natively cold (a fresh subagent, no session/keychain residue), so the discipline is to keep the *prompt* minimal, not the process.

### 2. DFS state machine in pure JS
`workflows/drill-core.mjs` ports `model.py`'s `find_next_open_leaf` + the three-way mutation (descend / bedrock / branch) and `judge.sh`'s "done = no open leaves" into pure functions. The tree lives in a JS variable — it *is* the single source of truth. No `tree.json` round-trip inside the loop, no exit-code signalling.

### 3. Schema-typed termination — the bug fix
deeper's live A-answer → `model.py` contract is a brittle string-prefix match (`answer.startswith("BEDROCK:")`). An autonomous answerer that buries `BEDROCK:` in prose is never recognized, so the drill never closes and drifts to the cap — this actually happened: `examples/ecdsa-drift` is a 50-deep linear chain, zero leaves closed, cursor never null.

`deeper-native` makes the answer a **discriminated union** validated at the tool layer:

```js
{ kind: 'descend' | 'bedrock' | 'branch' | 'stop', claim?, category?, depth_delta?, rationale }
```

The model *must* return one well-typed `kind`; the runtime retries on mismatch. Prose-buried bedrock is impossible, so termination is reliable. (Schema fixes *recognition*, not *judgment* — for the latter, see §4.)

### 4. Adversarial bedrock gate
Before a leaf is closed, `verify_fanout` skeptics run in **`parallel()`**, each trying to ask one more honest "why?" with a contestable answer. Majority-refute (`bedrockSurvives`) rejects the bedrock and forces one more descent into the strongest skeptic's deeper claim. This is the *one* place breadth enters — in service of depth discipline. It guards against shallow or mislabeled bedrock (a failure mode observed in the un-gated prototype).

### 5. Self-improvement across runs (the ralph flywheel — automatic)
Every drill is bracketed by two store phases. **Bootstrap** (start) reads the persisted store and loads accumulated lessons into the cold prompt. **Evolve** (end) records this run's violations to the run log, recomputes which violations recur across runs, and promotes the recurring ones to the binding-lessons file — so the *next* drill starts smarter without anyone editing a prompt by hand. After every session/question, the algorithm updates itself.

Promotion is `promoteBans()` — a pure function mirroring `legacy/harness/feedback.sh`: count the **distinct runs** (within a sliding `window`, default 5) in which each violation key appears; promote any key hitting `threshold` (default 2), idempotently, with a rationale. It is computed in the script body (deterministic, unit-tested); **agents only do the filesystem I/O** (same split as deeper's `model.py` = pure logic, shell = I/O). The store lives at `~/.deeper/runs/deeper-native/`:

- `runlog.jsonl` — one line per run: `{run_id, violations}`
- `bans.json` — the currently-promoted lessons `[{key, rationale}]`, reloaded by the next Bootstrap
- `BANS.md` — human-readable view
- `<run-id>/{outcome.json, tree.txt}` — each run's result

This closes the loop deeper's framework is built around (`legacy/harness/meta-loop.sh` + `feedback.sh` + `BANS.md`) inside a single self-contained workflow: **drill → record → promote → (next drill) load**. A violation has to recur in `threshold` distinct runs before it becomes a binding lesson, so the flywheel visibly engages after repeated drills, not on the first one.

---

## Architecture

```
                        args {seed, cap?, verify_fanout?, bans?}
                                         │
         ┌───────────────────────────────▼─────────────────────────────────┐
         │  workflows/deeper-native.js   (the dynamic workflow / driver)     │
         │                                                                   │
         │  ① BOOTSTRAP  agent reads store → loads BANS into the cold prompt │
         │        │                                                          │
         │        ▼  PROMPT (ralph, re-injected) · ANSWER_SCHEMA · VERDICT_SCHEMA
         │  ② DRILL / VERIFY                                                 │
         │     answerFn ─ agent(Q, cold) → agent(A, cold, schema)            │
         │     verifyFn ─ parallel( agent×N skeptics, schema )               │
         │        │                                                          │
         │        ▼   ┌──────────── CORE (mirrored, pure) ───────────────┐   │
         │            │ runDrill: while(open leaf){ answerFn → [verifyFn] │   │
         │            │           → applyAnswer → spinning guard }        │   │
         │            │ findOpenLeaf·walk·applyAnswer·judge·bedrockSurvives│   │
         │            │ promoteBans  ← pure feedback/promotion logic      │   │
         │            └────────────────────────────────────────────────────┘ │
         │        │                                                          │
         │        ▼  ③ EVOLVE  promoteBans(prior+this) → agent writes store  │
         └───────────────────────────────┬─────────────────────────────────┘
                                          │  returns { outcome, tree, trace, active_bans, promoted }
                                          ▼
   ~/.deeper/runs/deeper-native/   runlog.jsonl · bans.json · BANS.md · <id>/{outcome,tree}
        ▲ Bootstrap reads ─────────────────────────── Evolve writes ┘   (the ralph flywheel)

   workflows/drill-core.mjs     ── canonical pure engine (CORE block) ──┐
   tests/test-drill-core.mjs    ── $0 fixtures + sync-guard ────────────┘  (59 assertions)
```

- **`workflows/drill-core.mjs`** — canonical pure engine: the DFS state machine, `runDrill`, and `promoteBans` (the feedback/promotion logic). No agents, no FS, no clock. Exported for tests.
- **`workflows/deeper-native.js`** — the workflow. Inlines a verbatim copy of the engine's `CORE` block (workflow scripts are sandboxed and cannot `import` local files), then adds: a **Bootstrap** agent (reads the store), the **per-round fan-out** `answerFn` (a cold Q, then `answer_fanout` candidate A's in `parallel()` from distinct angles, then a judge that keeps the deepest), the `parallel()` `verifyFn` bedrock gate, and an **Evolve** agent (records the run, promotes recurring violations, persists). The script body itself never touches the filesystem.
- **`tests/test-drill-core.mjs`** — 25 fixtures over the pure engine (feeding scripted answers in place of `agent()`, plus `promoteBans` promotion cases), and a **sync-guard** asserting the workflow's inlined `CORE` block is byte-identical (whitespace-normalized) to the module. 59 assertions, $0, no LLM.

---

## Quick start

Install as a saved workflow (one-time symlink, mirrors how the skill is installed):

```bash
mkdir -p ~/.claude/workflows
ln -s ~/code/deeper/workflows/deeper-native.js ~/.claude/workflows/deeper-native.js
```

Run it from a Claude Code session (the Workflow tool), passing a seed claim via `args`:

```
Workflow({ name: "deeper-native", args: { seed: "Why does our checkout funnel keep regressing?", cap: 12 } })
```

`args`:

| key            | default | meaning                                                        |
|----------------|---------|----------------------------------------------------------------|
| `seed`         | (a self-referential demo claim) | the claim to drill to bedrock            |
| `cap`          | 12 (or budget-scaled) | max rounds; if a token budget is set, scales with it |
| `answer_fanout`| 3       | candidate answers fanned out **per round**; a judge keeps the deepest |
| `verify_fanout`| 3       | skeptics per bedrock candidate (the adversarial gate)          |
| `bans`         | `[]`    | extra binding lessons to inject (merged on top of the auto-loaded ones) |

Watch live with `/workflows`. The drill **self-improves automatically**: it loads accumulated lessons at the start and promotes recurring violations at the end — no flags needed. State + lessons persist to `~/.deeper/runs/deeper-native/` (`<run-id>/{outcome.json,tree.txt}`, `runlog.jsonl`, `bans.json`, `BANS.md`). The flywheel engages after a violation recurs in `threshold` (default 2) runs.

Run the $0 tests (no LLM, no tokens):

```bash
node tests/test-drill-core.mjs        # 12 fixtures + CORE sync-guard
```

---

## How this differs from a vanilla dynamic workflow

A vanilla dynamic workflow is **breadth-shaped**: `parallel()`/`pipeline()` fan work out, agents are independent, you decompose then gather. `deeper-native` uses the *same runtime* to do the opposite, and adds discipline a plain script doesn't have:

| Dimension | Vanilla dynamic workflow | `deeper-native` |
|---|---|---|
| **Shape** | Breadth — fan-out / pipeline, parallel by default | **Depth** — a serial DFS `while` loop; one claim drilled vertically |
| **Agent role** | Agents return data the script gathers | Agents **steer a state machine** — each schema-typed answer mutates a shared tree and moves the cursor |
| **Termination** | Ends when the script ends | A **predicate**: loop until every leaf is closed at bedrock (or spinning / cap) |
| **Context** | Each agent is cold, but independent | Cold **and** ralph-disciplined: prompt is re-injected with *accumulating binding lessons*, never the running history |
| **Parallelism** | The whole point | Used *only* at the bedrock gate (skeptics) — breadth in service of depth, never to widen the thread |
| **Self-improvement** | None across runs | An automatic ralph flywheel: each run records violations, `promoteBans` promotes recurring ones (sliding window) to a persisted BANS store the next run's Bootstrap loads |
| **Quality bar** | Whatever the agents return | An **adversarial gate** must fail to refute a claim before it counts as bedrock |

In short: a vanilla workflow is an *orchestrator of independent work*; `deeper-native` is an *epistemic state machine* that happens to run on the same orchestrator. The runtime gives determinism (no [ADR-002](../docs/ADR-002-main-session-orchestrator.md) race — a JS `while` loop has no turn boundaries) and schema-typed signals (fixing deeper's prose-parsing bug) for free; the philosophy supplies everything the runtime doesn't care about.

---

## Scope — what this is and isn't

- **Is:** the autonomous drill (deeper's default `auto` mode) as a background workflow. Agents stand in for the respondent; reliable termination; observable via `/workflows`; persisted for inspection.
- **Isn't:** the interactive `/deeper interactive` mode. A background workflow takes no mid-run user input, so the human-answers-each-round path stays in the skill (`legacy/skills/deeper/SKILL.md`).
- **Trade vs the skill:** `agent()` bills tokens; the skill's `claude -p` runs over session auth with no per-call billing. For an autonomous background drill you are already paying workflow tokens, and `claude -p`'s latency advantage (the reason for [ADR-003](../docs/ADR-003-claude-print-orchestrator.md)) is invisible when nobody is watching round-by-round — so the trade is worth it *here*, and only here.
