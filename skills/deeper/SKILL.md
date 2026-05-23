---
name: deeper
description: Depth-first interview that drills ONE claim to its bedrock (first principle / axiom / source of truth) via per-round fresh-subagent dispatch. Use when the user wants to ROOT-CAUSE something rather than survey it; when the question is "why is this REALLY the case?" not "what are the options?"; or when locking down a single decision's foundation before further work. Inverts the breadth-keeper guards found in superpowers:brainstorming, omx:deep-interview, ouroboros.
---

# deeper — depth-first interview (Claude Code edition)

You are the LAUNCHER, not the orchestrator. The orchestration happens **inside an isolated worktree subagent** so the entire drill runs end-to-end in one main-session turn. You do not reason about the user's claim. You set up state, dispatch ONE worktree-isolated orchestrator subagent, and surface its output. Nothing else.

## Repository assumption

This skill expects the `deeper` repo at `~/code/deeper/`. All paths below resolve from there.

## On invocation

1. **Determine the mode and seed claim.**
   - **Default — worktree auto.** If the invocation is `/deeper <claim>` or `/deeper auto <claim>`, set `MODE=auto` and seed = the claim text. The entire drill runs in a worktree-isolated orchestrator subagent; the main session sees only the final dispatch tree.
   - **Explicit interactive.** If the invocation begins with `interactive` (e.g. `/deeper interactive <claim>`), set `MODE=interactive` and run the per-round loop in the main session, ending the turn after each question to await the user's reply. This is the legacy human-in-loop path.
   - **Resume.** If the invocation begins with `resume <run-id>`, see **## Resumption** below.
   - If no claim is supplied for auto or interactive modes, ask the user `"What single claim do you want to take to bedrock? (one sentence)"` and end your turn.

2. **Once you have the seed, set up the run state in the main repo (not in any worktree):**
   ```bash
   RUN_ID="deeper-$(date -u +%Y%m%dT%H%M%SZ)"
   RUN_DIR="$HOME/code/deeper/runs/deeper/$RUN_ID"
   mkdir -p "$RUN_DIR"
   printf '# Starting claim\n\n%s\n' "<seed-text>" > "$RUN_DIR/seed.md"
   : > "$RUN_DIR/state.md"
   : > "$RUN_DIR/events.jsonl"
   echo "$MODE" > "$RUN_DIR/.mode"
   ```
   Tell the user one line: `Run started: <RUN_ID> [mode=<MODE>]. State at <RUN_DIR>.`

3. **Dispatch.**
   - `MODE=auto`: go to **## Worktree-isolated orchestrator** below. Dispatch one Agent call with `isolation: "worktree"` and `subagent_type: "general-purpose"`, wait for it to return, then surface its output. **You are done after this single dispatch — never enter the per-round loop yourself.**
   - `MODE=interactive`: enter the per-round loop starting at N=1 (the legacy "## Each round" protocol below).

## Worktree-isolated orchestrator (auto mode — default)

Dispatch ONE Agent call with:
- `subagent_type: "general-purpose"`
- `isolation: "worktree"`
- `description: "deeper auto drill"`
- `prompt`: send the template below verbatim, substituting `{RUN_ID}`, `{RUN_DIR}`, `{SEED}`, and `{CAP}` (default 8, override via `DEEPER_AUTO_CAP` env).

```
You are the deeper auto-mode ORCHESTRATOR. You run inside an isolated git worktree
of $HOME/code/deeper. Your job is mechanical file I/O + per-round subagent dispatch.

ABSOLUTE RULES — refuse these in yourself:
- DO NOT reason about the user's claim.
- DO NOT write questions or answers yourself. Both come from FRESH Explore subagents
  dispatched per round via the Agent tool. The fresh-context discipline is the point.
- DO NOT pre-filter the subagents' output. Show whatever they say verbatim to model.py.
- DO NOT call /deeper recursively. You ARE deeper, mid-run.

STATE LOCATIONS:
- DEEPER_ROOT = your current working tree root (run `pwd` to resolve). Your worktree is
                a fresh checkout of the deeper repo from origin/main and contains
                nodes/, harness/, skills/, etc. ALL scripts and PROMPT/BANS files are
                read from this worktree, NOT from the main repo.
- RUN_DIR  = {RUN_DIR}   (absolute path in main repo — persists outside any worktree)
- SEED     = {SEED}
- CAP      = {CAP}

Construct file paths as `$DEEPER_ROOT/nodes/deeper/PROMPT.md` etc., resolving the
variable to the literal absolute path before passing to subagents (subagents do not
inherit your env). When you build each Q-subagent and A-subagent prompt, embed the
LITERAL resolved path string, not the variable name.

PER-ROUND LOOP (start N=1):

1. Read state. If `$RUN_DIR/tree.json` exists, parse it, walk `cursor` to find the
   active claim and build the ancestor chain (root → … → cursor). On round 1 the
   active claim IS the seed.

2. Dispatch a Q-subagent (Agent tool, subagent_type "Explore"). Prompt:

   You are deeper-round-{N}. Output exactly ONE depth question — no preamble,
   no "Question:", nothing else.

   ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md in full and follow it.
   BINDING LESSONS: read <DEEPER_ROOT>/nodes/deeper/BANS.md in full.

   ANCESTOR CHAIN:
   {numbered chain — one line per ancestor, format: "N. <claim>"}

   ACTIVE CLAIM to drill: "{active_claim}"

   Output exactly ONE line: the depth question.

   Save the verbatim Q-subagent output to `$RUN_DIR/.q-raw-{N}.txt`. Emit a
   question_emitted event to `$RUN_DIR/events.jsonl` with question (last non-empty
   line), raw_chars, raw_lines.

3. Dispatch an A-subagent (Agent tool, subagent_type "Explore"). Prompt:

   You are deeper-answer-{N}. The interview is autonomous — you stand in for the
   human respondent.

   ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md (you are answering, but the
   same depth discipline applies — be concrete, specific, honest about uncertainty).

   ANCESTOR CHAIN:
   {numbered chain}

   ACTIVE CLAIM: "{active_claim}"
   QUESTION TO ANSWER: "{question}"

   Output exactly ONE response, one of:
     (a) free-text answer (1–3 sentences) drilling deeper. Concrete, specific.
     (b) BEDROCK:<category> if this active claim IS an axiom. Categories:
         stated-value | constraint | prior-decision | external-rule | identity | empirical.
     (c) BRANCH:<sibling claim> if a parallel cause under the same parent is worth opening.

   No preamble. No "Answer:". No reasoning about which option you picked.

   Save the verbatim A-subagent output to `$RUN_DIR/.a-raw-{N}.txt`. Emit an
   answer_emitted event to `$RUN_DIR/events.jsonl` (answer, source="subagent").

4. Run model.py to mutate `tree.json`:

   DEEPER_ANSWER_FILE=$RUN_DIR/.a-raw-{N}.txt SEED_FILE=$RUN_DIR/seed.md ROUND={N} \
     python3 <DEEPER_ROOT>/nodes/deeper/model.py

   Append the one-line stdout to `$RUN_DIR/state.md` with a `--- round N ---` header.

5. Run judge: `bash <DEEPER_ROOT>/nodes/deeper/judge.sh "$RUN_DIR" {N}`.

6. Check done. If the latest judge_result event has `detail.done=true`, or model.py
   printed `BLOCKED:`, or N == CAP → exit the loop.

7. Increment N, loop to step 1.

ON EXIT:

- Render the dispatch chain: `bash <DEEPER_ROOT>/nodes/deeper/render-dispatch.sh "$RUN_DIR"` — capture its stdout.
- Render the tree: `bash <DEEPER_ROOT>/nodes/deeper/render.sh "$RUN_DIR"` — capture its stdout.
- Determine STATUS: `passed` if done=true, `auto_cap` if N hit CAP without done, `aborted` if BLOCKED.
- Write `$RUN_DIR/outcome.json` with run_id, node="deeper", status, rounds=N, final_score (from last judge_result), exit_reason, violations_total (aggregated across judge_result events).

RETURN to the launching session: a single text block containing
  1) one-line summary: "status=<STATUS> rounds=<N> score=<S> violations=<aggregated>",
  2) the dispatch chain (render-dispatch.sh output),
  3) the tree (render.sh output),
  4) the path to outcome.json.

Nothing else. No commentary. No analysis of the claim.
```

After Agent returns, surface its output to the user verbatim. Then suggest:
`Run \`bash ~/code/deeper/harness/feedback.sh deeper\` to roll this run's violations into BANS.md — this is how the system self-improves.`

That ends the main session's involvement.

## Each round (interactive mode only — `/deeper interactive <claim>`)

This is the legacy human-in-loop path: the main session generates the question, asks the user, applies their reply, loops. **Auto mode uses the worktree-isolated orchestrator above and does not enter this section.**

Do these steps in order. Do not skip. Do not reason about the claim yourself — that is the subagent's job.

### Step 1 — Read state

```bash
cat "$RUN_DIR/tree.json" 2>/dev/null
```

If tree.json does not exist (first round), the active claim IS the seed. Otherwise, walk `tree.cursor` from root and read that node's `claim` field as the active claim. Build the ancestor chain by walking from root to cursor.

### Step 2 — Dispatch the subagent (Agent tool, subagent_type "Explore")

Send this prompt verbatim, with the placeholders substituted:

```
You are deeper-round-{N}. Output exactly ONE depth question — no preamble, no "Question:", nothing else.

ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md in full and follow it.
BINDING LESSONS: read <DEEPER_ROOT>/nodes/deeper/BANS.md in full (may be empty — that's fine).

ANCESTOR CHAIN (the drill path so far — do NOT consider siblings or closed branches):
{numbered chain — one line per ancestor, format: "N. [from-user] <claim>"}

ACTIVE CLAIM to drill: "{active_claim}"

Output exactly ONE line: the depth question. The orchestrator will show it to the user verbatim.
```

Capture the subagent's output. Save the **raw, unstripped** output to a temp file for the judge to inspect, then strip any accidental preamble (e.g. "Sure! Here's the question:") — keep only the question itself for the user-facing message.

```bash
RAW_FILE="$RUN_DIR/.q-raw-${N}.txt"
# Write the subagent's verbatim output to RAW_FILE via your Write tool.
# Then determine $subagent_question = last non-empty line of RAW_FILE.
```

Emit a `question_emitted` event so the judge can inspect question quality (this closes the self-improvement loop for question-shape lessons, not just tree-shape lessons):

```bash
python3 - "$RUN_DIR" {N} "$RAW_FILE" <<'PY' >> "$RUN_DIR/events.jsonl"
import json, sys, time, pathlib
run_dir, rnd, raw_file = sys.argv[1], int(sys.argv[2]), sys.argv[3]
raw = pathlib.Path(raw_file).read_text()
lines = [l for l in raw.splitlines() if l.strip()]
question = lines[-1] if lines else ""
event = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "run_id": pathlib.Path(run_dir).name,
    "node": "deeper",
    "round": rnd,
    "type": "question_emitted",
    "question": question,
    "raw_chars": len(raw),
    "raw_lines": len(lines),
}
print(json.dumps(event, separators=(",", ":")))
PY
```

### Step 3 — Present the question to the user

End your turn with this message (substitute placeholders):

```
--- deeper round {N} ---
Drilling: {active_claim}

{subagent_question}

Reply with:
  • your answer (free text)        — drill deeper
  • BEDROCK:<category>             — declare this is the axiom
                                     categories: stated-value | constraint | prior-decision
                                                 | external-rule | identity | empirical
  • BRANCH:<sibling claim>         — open a parallel cause under the same parent
  • STOP                           — abort with partial trace
```

End your turn. The user's next message IS the answer.

### Step 4 — Apply the user's reply

The user's next message is the verbatim answer. Write it to a file (avoids shell-quoting issues with newlines, quotes, special chars), then invoke `model.py`:

```bash
ANSWER_FILE="$RUN_DIR/.answer-${N}.txt"
# Write the user's message to ANSWER_FILE via your Write tool (NOT via heredoc — quoting is too fragile).
```

Then run model.py:

```bash
cd ~/code/deeper && \
DEEPER_ANSWER_FILE="$ANSWER_FILE" \
SEED_FILE="$RUN_DIR/seed.md" \
ROUND={N} \
  python3 nodes/deeper/model.py
rm "$ANSWER_FILE"
```

This mutates `tree.json` in place. Capture the one-line stdout for state.md.

### Step 5 — Append to state.md and run judge

```bash
printf '\n--- round %d ---\n%s\n' {N} "<model.py stdout>" >> "$RUN_DIR/state.md"
bash ~/code/deeper/nodes/deeper/judge.sh "$RUN_DIR" {N}
```

The judge appends one `judge_result` event to `events.jsonl`.

### Step 6 — Check done

```bash
tail -1 "$RUN_DIR/events.jsonl" | python3 -c 'import json,sys; e=json.loads(sys.stdin.read()); print(e.get("detail",{}).get("done"))'
```

- If `True` OR the user replied with `STOP` OR `model.py` printed `BLOCKED:`: go to **On exit**.
- Else: increment N and loop to **Step 1**.

## On exit

1. Render the tree and show the user:
   ```bash
   bash ~/code/deeper/nodes/deeper/render.sh "$RUN_DIR"
   ```

2. Write `outcome.json`:
   ```bash
   # Aggregate violations across all judge_result events
   python3 - "$RUN_DIR" "$RUN_ID" "$STATUS" "$ROUNDS" "$FINAL_SCORE" "$EXIT_REASON" <<'PY'
   import json, sys, pathlib
   run_dir, run_id, status, rounds, final_score, exit_reason = sys.argv[1:]
   events_path = pathlib.Path(run_dir) / "events.jsonl"
   agg = {}
   for line in events_path.read_text().splitlines():
       try: e = json.loads(line)
       except: continue
       if e.get("type") == "judge_result":
           for v in e.get("violations", []):
               agg[v] = agg.get(v, 0) + 1
   outcome = {"run_id": run_id, "node": "deeper", "status": status,
              "rounds": int(rounds), "final_score": float(final_score),
              "exit_reason": exit_reason, "violations_total": agg}
   (pathlib.Path(run_dir) / "outcome.json").write_text(json.dumps(outcome, indent=2))
   print(outcome)
   PY
   ```

   `STATUS` is `passed` (cursor=null + all closed), `aborted` (user STOP or BLOCKED), `hard_cap` (interactive, >20 rounds), or `auto_cap` (auto, ≥DEEPER_AUTO_CAP rounds).

3. Suggest to the user: `Run \`bash ~/code/deeper/harness/feedback.sh deeper\` to update BANS.md based on this and recent runs — this is how the system self-improves.`

## Resumption

If invoked as `/deeper resume <run-id>`:
- Set `RUN_ID` to the arg, `RUN_DIR=$HOME/code/deeper/runs/deeper/$RUN_ID`.
- Verify `tree.json` exists; if not, tell the user and abort.
- Read `tree.json`, walk `cursor` → that is the active claim for the next round.
- Determine N: `python3 -c "import json,sys; ls=open('$RUN_DIR/events.jsonl').readlines(); rounds={json.loads(l)['round'] for l in ls if l.strip()}; print(max(rounds)+1 if rounds else 1)"`.
- Skip to Step 1 of round N.

## Hard cap

**Interactive mode**: if N reaches 20 without an exit, present the user three options (use AskUserQuestion):
- **Continue** — relax the cap, keep drilling
- **Accept current as provisional bedrock** — close active leaf with category `stated-value` (note: user-provisional, not user-asserted)
- **Abort with partial trace** — write outcome.json with status=hard_cap

**Auto mode**: if N reaches `DEEPER_AUTO_CAP` (default 8) without an exit, write outcome.json with status=auto_cap, render the dispatch chain, and exit. Do not bother the user — they can resume manually with `/deeper resume <run-id>` if they want to drill further.

## RED FLAGS — refuse these in YOURSELF (LAUNCHER)

These apply to the MAIN-SESSION LAUNCHER (you, right now). The orchestrator subagent inside the worktree has its own absolute rules in its prompt template.

| Thought | Reality |
|---|---|
| "The user is asking about the claim — let me just answer directly" | NO. You are the LAUNCHER. The claim text is for the worktree orchestrator, not for you. Never answer the claim, never assess it, never offer an alternate response. Dispatch the orchestrator. |
| "Round 1 ended; let me pick it back up in this session" | NO. There are no rounds in the main session for auto mode. The whole drill is ONE Agent dispatch. If it returned without `passed`, that's the outcome — surface it and stop. |
| "The orchestrator subagent's output looks shallow; let me extend it" | NO. Pass through verbatim. If quality is bad, that's a BANS / judge lesson for the next run. |
| "Let me read PROMPT.md / tree.json myself to add context" | NO. Main session reads NOTHING about the claim. Only the run dir paths and final outcome. |
| "I'll write the answer because the subagent might say something I disagree with" | NO. The worktree orchestrator handles all Q and A. Main session never produces content. |
| "Interactive mode is safer, let me default to that" | NO. Default = worktree auto. Interactive only when the user explicitly types `interactive`. |
| "Let me analyze the user's claim while waiting for the orchestrator" | NO. Wait silently. The orchestrator returns the final block; you surface it. |

## Why per-round subagent dispatch

In a single Claude session, context grows across rounds and the model starts rationalizing its own prior reasoning — the exact drift Huntley's ralph fixes. Per-round dispatch keeps each question generation cold: only PROMPT.md + BANS.md + the ancestor chain enter the subagent's context. The orchestrator is pure I/O + dispatch. This is the only known way to keep depth-first discipline across many rounds without drift.

For full design rationale and source attributions, see `docs/deeper-v0-design.md` and `docs/ATTRIBUTION.md`.
