---
name: deeper
description: Depth-first interview that drills ONE claim to its bedrock (first principle / axiom / source of truth). Use when the user wants to ROOT-CAUSE something rather than survey it — "why is this REALLY the case?" not "what are the options?" — or when locking down a single decision's foundation. Runs the deeper-native dynamic workflow (cold-context ralph loop + DFS tree + schema-typed termination + adversarial bedrock gate + cross-run self-improvement). Inverts the breadth-keeper guards in superpowers:brainstorming, omx:deep-interview, ouroboros.
---

# deeper — depth-first drill (runs on the deeper-native workflow)

When the user invokes `/deeper <claim>` (or asks you to drill / root-cause a claim), you do **one thing**: launch the `deeper-native` dynamic workflow with their claim as the seed, then surface what it returns. You do **not** reason about the claim yourself or hand-roll a round loop — the workflow owns the entire drill (cold Q/A agents, DFS state machine, adversarial bedrock gate, self-improvement store).

## On invocation

1. **Extract the seed.** Everything after `/deeper` is the claim to drill. If the invocation is bare (`/deeper` with no claim), ask the user for the claim as plain free-text — there are no fixed options.

2. **Parse optional knobs** if the user included them (otherwise omit and let the workflow default): `cap=N` (max rounds), `verify=N` (skeptics per bedrock candidate, the adversarial gate).

3. **Launch the workflow.** Call the Workflow tool:

   ```
   Workflow({ name: "deeper-native", args: { seed: "<claim>", cap?: N, verify_fanout?: N } })
   ```

   Pass `args` as a real object (the workflow normalizes it whether it arrives as an object or a JSON string). It runs in the background and returns a task id immediately; a notification arrives on completion. Tell the user one line: which seed is being drilled and that they can watch live with `/workflows`.

4. **When it completes, surface the result** — do not editorialize. The workflow returns `{ outcome, tree, trace, active_bans, promoted, run_dir }`:
   - Print the `tree` (the rendered bedrock tree) and the `outcome` (status + rounds).
   - If `promoted` is non-empty, mention which lessons were promoted this run (the self-improvement flywheel engaged).
   - State the `run_dir` so the user can inspect persisted state under `~/.deeper/runs/deeper-native/`.

## Notes

- **Install (one-time).** The workflow resolves by name from `~/.claude/workflows/`. If `name: "deeper-native"` does not resolve, symlink it: `ln -s ~/code/deeper/workflows/deeper-native.js ~/.claude/workflows/deeper-native.js`.
- **This is the autonomous drill.** Agents stand in for the respondent and the drill self-terminates at verified bedrock (or the cap). The human-answers-each-round *interactive* path is the v1 bash skill, archived at `legacy/skills/deeper/SKILL.md` (run with `DEEPER=~/code/deeper/legacy`).
- **Why a workflow, not a hand-built loop.** The dynamic Workflow runtime provides the deterministic orchestration the v1 skill simulated in bash — no turn-boundary race, schema-typed termination, native `parallel()` for the skeptic gate. See `workflows/README.md`.
