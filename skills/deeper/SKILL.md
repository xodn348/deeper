---
name: deeper
description: Depth-first interview that drills ONE claim to its bedrock (first principle / axiom / source of truth) via per-round fresh-subagent dispatch. Use when the user wants to ROOT-CAUSE something rather than survey it; when the question is "why is this REALLY the case?" not "what are the options?"; or when locking down a single decision's foundation before further work. Inverts the breadth-keeper guards found in superpowers:brainstorming, omx:deep-interview, ouroboros.
---

# deeper — depth-first interview (Claude Code edition)

You are the LAUNCHER and the orchestrator — the main Claude session runs the round loop directly in a single turn, looping until done or cap, dispatching a fresh Explore subagent per round for Q and another for A. You do NOT reason about the user's claim — that judgment belongs to the per-round Explore subagents. You set up state, arm Monitor for live progress, run the round loop, surface what arrives. Nothing more.

This replaces the earlier worktree-isolated orchestrator design (PR #4), which depended on recursive Agent dispatch from inside a background subagent — a path Claude Code blocks at tool resolution (`"Agent is not available inside subagents"`). See `docs/ADR-002-main-session-orchestrator.md` for the decision rationale.

## Repository assumption

This skill expects the `deeper` repo at `~/code/deeper/`. All paths below resolve from there.

## On invocation

**UI discipline (main-session launcher only)**: when the launcher needs the user to choose between options, ALWAYS use the `AskUserQuestion` tool — never a plain text prompt embedded in your message. The structured UI makes it visually unambiguous that the question is a control prompt, not a Q-subagent output. Plain text is fine only for free-form input (e.g. seed claim entry) where no discrete options exist.

1. **Determine the mode and seed claim.**
   - **Default — auto.** If the invocation is `/deeper <claim>` or `/deeper auto <claim>`, set `MODE=auto` and seed = the claim text. The main session runs the round loop directly, looping rounds within a single turn until done or cap, dispatching fresh Explore subagents per round for Q and A.
   - **Explicit interactive.** If the invocation begins with `interactive` (e.g. `/deeper interactive <claim>`), set `MODE=interactive` and run the per-round loop in the main session, ending the turn after each question to await the user's reply. This is the human-answers path.
   - **Resume.** If the invocation begins with `resume <run-id>`, see **## Resumption** below.
   - **Ambiguous invocation** (no claim, or just `/deeper` with no arg): call `AskUserQuestion` to pick the mode (single-select):
     - **Auto (recommended)** — subagent answers each round, hands-off, ~8 rounds
     - **Interactive** — human answers each round in chat
     Then end your turn. On the user's reply, ask for the seed claim as plain text (free-form, no fixed options).

1b. **Stuck-run pre-flight check (race-recovery safety net).** Before creating a new RUN_ID, scan for any prior run that started but never reached a terminal state — this catches the case where a previous launcher session crashed, was interrupted, or hit the (now-fixed) judge_result wake race and left the user with no obvious recovery path.

    ```bash
    STUCK=$(python3 -c "
    import json, pathlib
    base = pathlib.Path.home() / 'code' / 'deeper' / 'runs' / 'deeper'
    out = []
    for d in sorted(base.glob('deeper-*'), reverse=True)[:10]:
        if (d / 'outcome.json').exists(): continue
        ev = d / 'events.jsonl'
        if not ev.exists(): continue
        last = ''
        for line in ev.read_text().splitlines():
            if line.strip(): last = line
        if not last: continue
        try: e = json.loads(last)
        except: continue
        if e.get('type') == 'judge_result' and not e.get('detail',{}).get('done'):
            seed = (d/'seed.md').read_text()[:80].replace('\n',' ') if (d/'seed.md').exists() else ''
            out.append(f'{d.name}|{e.get(\"round\",\"?\")}|{seed}')
    print('\n'.join(out))
    ")
    ```

    If `STUCK` is non-empty, call `AskUserQuestion` with options (one per stuck run, up to 4): label `Resume <RUN_ID> (R{round}, "{seed snippet}")`, plus a final `Start fresh anyway` option. If the user picks resume, jump to **## Resumption**. If they pick fresh, continue to step 2 below.

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
   - `MODE=auto`: go to **## Main-session orchestrator** below. In the launcher turn:
     (a) arm `Monitor` tailing `$RUN_DIR/events.jsonl` through `format-events.py` so each event becomes one chat line,
     (b) run the "### Round handler" for round 1 (Q-subagent dispatch + A-subagent dispatch + model.py + judge.sh),
     (c) immediately continue into round 2, 3, ... in the same turn until `done==true`, cap is reached, `BLOCKED:`, or a user interrupt. See the section below for the full protocol.
   - `MODE=interactive`: enter the per-round loop starting at N=1 (the human-in-loop "## Each round" protocol below).

## Main-session orchestrator (auto mode — default)

The main Claude session runs the round loop itself, all rounds in a single turn until done or cap. Q and A both come from fresh Explore subagents — the launcher never produces content.

Why single-turn looping (not one round per turn): the prior "one round per turn + wake on judge_result" design had a race condition — when `judge.sh` ran fast enough that the `judge_result` notification arrived synchronously inside the launcher turn (consumed as a mid-turn system reminder), no NEW wake notification existed after turn end, so the loop deadlocked silently (observed: deeper-20260524T052713Z hung at R3 after judge.sh emitted the event mid-Bash-output). Single-turn looping eliminates the race and also removes the 50–74s inter-turn gap (turn boot + tree.json read + cold subagent dispatch) that doubled per-round latency. Monitor stays armed for live event surfacing; focus mode hides intermediate assistant text but tool-call system reminders still surface each `[Rx Q]`, `[Rx A]`, `[Rx ✓]` event as the user sees them.

User interrupt mechanism: a user message arriving mid-loop terminates the drill cleanly (see "Wake handler → user-interrupt path"). Without an interrupt, the loop runs to completion in one continuous turn.

### Launcher entry (one turn, all rounds)

Execute in this order:

1. Pre-flight (Step 0 above) + run-dir setup (Step 2 above).

2. **Arm Monitor automatically** — do NOT ask the user, do NOT skip:

   ```
   Monitor(
     command: "tail -F -n 0 \"$RUN_DIR/events.jsonl\" | python3 -u $HOME/code/deeper/nodes/deeper/format-events.py",
     description: "deeper $RUN_ID events stream",
     persistent: true,
     timeout_ms: 3600000
   )
   ```

   Capture the task id — you will TaskStop it at run end. Persist it to `$RUN_DIR/.monitor-task-id`.

3. Tell the user one line: `Run started: $RUN_ID (auto, cap=$CAP). Streaming progress below.`

4. **Loop**: for N = 1, 2, 3, ...:
   a. Run the **Round handler** below for round N. Capture two signals from the round:
      - `MODEL_BLOCKED=1` if model.py's stdout started with `BLOCKED:` (stall self-heal sentinel).
      - `JUDGE_EXIT` = the exit code of `judge.sh` (see `nodes/deeper/judge.sh` header — `0`=continue, `100`=done, `1`=error).
   b. Branch on those signals — **never re-read events.jsonl or re-parse stdout to decide done/continue**, because the prior design's race condition came from exactly that kind of secondary state dependence. The judge's exit code IS the authoritative signal.
   c. If `MODEL_BLOCKED=1` → break loop, go to "## After completion (exit handler)" with status `aborted` (reason: `stall_round_N` or `user_stop`).
   d. If `JUDGE_EXIT == 100` → break loop, go to "## After completion" with status `passed`.
   e. If `JUDGE_EXIT == 1` → break loop, go to "## After completion" with status `aborted` (reason: `judge_error_round_N`).
   f. If `JUDGE_EXIT == 0` and N >= CAP (default 8, `DEEPER_AUTO_CAP` overrides) → break loop, go to "## After completion" with status `auto_cap`.
   g. Otherwise (`JUDGE_EXIT == 0` and N < CAP): increment N, continue immediately to the next round in the same turn. Do NOT end the turn between rounds.

5. After the exit handler runs, end the turn with the consolidated rendered tree as the final message.

### Round handler (one round, inside the launcher loop)

Given the round number N:

1. **Build the ancestor chain**: read `$RUN_DIR/tree.json` (if exists), walk `cursor`, collect claim text from root to the active claim. On round 1 tree.json does not yet exist — active claim IS the seed.

2. **Dispatch the Q-subagent** with `Agent` foreground (NOT background), `subagent_type: "Explore"`, `model: "haiku"`. Prompt (substitute placeholders):

   ```
   You are deeper-round-{N}. Output exactly ONE depth question — no preamble, no "Question:", nothing else.

   ROLE: read /Users/jnnj92/code/deeper/nodes/deeper/PROMPT.md in full and follow it.
   BINDING LESSONS: read /Users/jnnj92/code/deeper/nodes/deeper/BANS.md in full.

   HARD GUARDS (binary self-check before you emit — see PROMPT.md "HARD GUARDS" for full text):
   G1 one non-empty line · G2 no forbidden first tokens · G3 language matches ACTIVE CLAIM ·
   G4 exactly one "?", no conjunction joiners · G5 not a restatement of the claim ·
   G6 stay on the active claim · G7 no breadth-extension framing.
   If your draft fails any guard, REWRITE before emitting.

   ANCESTOR CHAIN:
   {numbered chain — one line per ancestor, format: "N. <claim>"}

   ACTIVE CLAIM to drill: "{active_claim}"

   Output exactly ONE line: the depth question.
   ```

   Save the verbatim output to `$RUN_DIR/.q-raw-{N}.txt` via the Write tool. Emit a `question_emitted` event to `$RUN_DIR/events.jsonl` with `question` (last non-empty line of raw), `raw_chars`, `raw_lines`.

   Model escalation: `sonnet` only if BANS.md flags repeated G-violations for haiku on this claim type; `opus` for genuinely cryptic abstract claims.

3. **Dispatch the A-subagent** with `Agent` foreground, `subagent_type: "Explore"`, `model: "sonnet"`. Prompt:

   ```
   You are deeper-answer-{N}. The interview is autonomous — you stand in for the human respondent.

   ROLE: read /Users/jnnj92/code/deeper/nodes/deeper/PROMPT.md.

   HARD GUARDS for your answer (binary self-check before emit):
   - A1: Your response is EXACTLY ONE of: (a) 1–3 sentence free-text answer (NO BEDROCK:/BRANCH: prefix), (b) a single line starting `BEDROCK:`, (c) a single line starting `BRANCH:`. Mixed forms = fail.
   - A2: Forbidden first tokens: Sure, Here, OK, Answer, A:, 먼저, 우선, 답, 답변, 이.
   - A3: Language match — Hangul in ACTIVE CLAIM → Hangul in your answer.
   - A4: If you emit `BEDROCK:<cat>`, <cat> MUST be EXACTLY one of: stated-value | constraint | prior-decision | external-rule | identity | empirical.
   - A5: Honest uncertainty — if you don't know a fact, say "I don't know X" concretely. No hedge-filler.

   If your draft fails any guard, REWRITE before emitting.

   ANCESTOR CHAIN:
   {numbered chain}

   ACTIVE CLAIM: "{active_claim}"
   QUESTION TO ANSWER: "{question}"

   Output exactly ONE response, one of:
     (a) free-text answer (1–3 sentences) drilling deeper. Concrete, specific.
     (b) BEDROCK:<category> if this active claim IS an axiom.
     (c) BRANCH:<sibling claim> if a parallel cause under the same parent is worth opening.

   No preamble. No "Answer:". No reasoning about which option you picked.
   ```

   Save verbatim to `$RUN_DIR/.a-raw-{N}.txt`.

   **Stall self-heal** — if the saved file is empty or whitespace-only:
     i.   Append event `{"type":"stall","round":N,"reason":"empty_a_sonnet"}` to events.jsonl.
     ii.  Re-dispatch the A-subagent with `model: "opus"`. Overwrite `.a-raw-{N}.txt`.
     iii. If still empty:
          - Append event `{"type":"stall","round":N,"reason":"empty_a_after_opus_retry"}`.
          - Overwrite `.a-raw-{N}.txt` with literal `STOP` (triggers model.py's BLOCKED path).
          - Proceed to step 4.

   After the stall handler resolves, emit an `answer_emitted` event (`answer`, `source="subagent" | "subagent-opus-retry" | "stall-stop-sentinel"`).

4. **Run model.py** — capture stdout and check for the `BLOCKED:` sentinel:

   ```bash
   MODEL_OUT=$(DEEPER_ANSWER_FILE=$RUN_DIR/.a-raw-{N}.txt SEED_FILE=$RUN_DIR/seed.md ROUND={N} \
     python3 ~/code/deeper/nodes/deeper/model.py)
   MODEL_BLOCKED=0
   case "$MODEL_OUT" in BLOCKED:*) MODEL_BLOCKED=1 ;; esac
   printf '\n--- round %d ---\n%s\n' {N} "$MODEL_OUT" >> "$RUN_DIR/state.md"
   ```

   Pass `MODEL_BLOCKED` back to the launcher loop (step 4) along with `JUDGE_EXIT` from step 5.

5. **Run judge** — capture its exit code, which is the launcher loop's authoritative done/continue signal:

   ```bash
   bash ~/code/deeper/nodes/deeper/judge.sh "$RUN_DIR" {N} || JUDGE_EXIT=$?
   JUDGE_EXIT=${JUDGE_EXIT:-0}
   ```

   Exit code reference (see `nodes/deeper/judge.sh` header):
   - `0` → not done, continue looping
   - `100` → `detail.done == true`, drill complete
   - `1` → internal error in judge.sh (treat as `aborted` reason `judge_error_round_N`)

6. **Return control to the launcher loop** (step 4 of "Launcher entry") with `MODEL_BLOCKED` (from step 4 of this handler) and `JUDGE_EXIT` (from step 5). The launcher loop decides done/continue using ONLY those two integers — never re-reads events.jsonl. This is the architectural guarantee against future race conditions.

### User-interrupt path

If the user sends a message while the launcher loop is still running (i.e. a new turn arrives before the loop has hit done / cap / BLOCKED), treat it as an interrupt:
- Break the loop immediately.
- Go to "## After completion (exit handler)" with status `aborted` (reason: `user_interrupt`).
- Acknowledge the interrupt in one line at turn end.

### Resume-handler path

A `/deeper resume <run-id>` invocation enters at "## Resumption" below. It rebuilds N from existing events and re-enters the launcher loop at round N — same single-turn looping discipline applies.

### `DEEPER_AUTO_CAP` env variable

Default 8. Override on invocation: `DEEPER_AUTO_CAP=16 /deeper <claim>`. The cap bounds the round loop and produces `auto_cap` status when reached without `done=true`.

## After completion (exit handler)

Triggered by the wake handler when:

- judge_result with `detail.done == true` → status `passed`
- judge_result with N >= CAP and not done → status `auto_cap`
- model.py printed `BLOCKED:` (e.g. stall-stop-sentinel) → status `aborted` (reason: `stall_round_N` or `user_stop`)
- User message mid-drill → status `aborted` (reason: `user_interrupt`)

Steps:

1. `TaskStop` the Monitor task id (read from `$RUN_DIR/.monitor-task-id` if not in context).
2. Run `bash ~/code/deeper/nodes/deeper/render-dispatch.sh "$RUN_DIR"` and `bash ~/code/deeper/nodes/deeper/render.sh "$RUN_DIR"` — print both verbatim to chat. The user already saw rounds live via Monitor; this is the consolidated closing view.
3. Write `$RUN_DIR/outcome.json` with `run_id`, `node="deeper"`, `status`, `rounds` (max round in events), `final_score` (from last judge_result), `exit_reason`, `violations_total` (aggregated across all judge_result events).
4. Append a terminal `run_finished` event: `{"type":"run_finished","status":STATUS,"rounds":N,"score":final_score}` to events.jsonl.
5. **Exit handler — restore the launcher's original cwd** (per the Pre-flight transactional contract):
   ```bash
   ORIG_CWD="$(cat "$RUN_DIR/.orig-cwd" 2>/dev/null)"
   python3 -c "import json,time; print(json.dumps({'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'event':'launcher_exit','run_id':'$RUN_ID','status':'$STATUS','orig_cwd':'$ORIG_CWD'}))" >> "$HOME/code/deeper/runs/deeper/.launcher.jsonl"
   [ -n "$ORIG_CWD" ] && [ -d "$ORIG_CWD" ] && cd "$ORIG_CWD"
   ```
6. Call `AskUserQuestion` to offer next-step actions. Options depend on status:

   - `status=passed` (all leaves closed):
     - **Run feedback.sh** — promote this run's violations to BANS.md
     - **View tree** — re-render `nodes/deeper/render.sh <RUN_DIR>`
     - **Done** — nothing more

   - `status=auto_cap` (hit the round cap without closing):
     - **Resume with +8 rounds (Recommended)** — `/deeper resume <RUN_ID>` with `DEEPER_AUTO_CAP` doubled
     - **Run feedback.sh** — promote partial violations anyway
     - **Accept partial trace** — leave outcome.json as-is, exit
     - **Done** — nothing more

   - `status=aborted` (BLOCKED or user_interrupt):
     - **Inspect events.jsonl** — open the run dir, show the last few events
     - **Resume** — try again with the next round
     - **Done** — nothing more

Then execute whatever the user picked. If they pick **Done** or **Other** with no actionable text, end your turn silently. **Never** narrate or "interpret" the drill's outcome — surface the renders, surface the UI choices, do what's picked, stop.

## Each round (interactive mode only — `/deeper interactive <claim>`)

This is the human-in-loop path: the main session generates the question, asks the user, applies their reply, loops. **Auto mode uses the main-session orchestrator above (Q/A dispatched to Explore subagents) and does not enter this section.**

Do these steps in order. Do not skip. Do not reason about the claim yourself — that is the subagent's job.

### Step 1 — Read state

```bash
cat "$RUN_DIR/tree.json" 2>/dev/null
```

If tree.json does not exist (first round), the active claim IS the seed. Otherwise, walk `tree.cursor` from root and read that node's `claim` field as the active claim. Build the ancestor chain by walking from root to cursor.

### Step 2 — Dispatch the subagent (Agent tool, subagent_type "Explore", **model: "haiku"** — Opus allowed for cryptic abstract claims)

Send this prompt verbatim, with the placeholders substituted:

```
You are deeper-round-{N}. Output exactly ONE depth question — no preamble, no "Question:", nothing else.

ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md in full and follow it.
BINDING LESSONS: read <DEEPER_ROOT>/nodes/deeper/BANS.md in full (may be empty — that's fine).

HARD GUARDS (binary self-check before you emit — see PROMPT.md "HARD GUARDS" for full text):
G1 one non-empty line · G2 no forbidden first tokens (Sure/Here/먼저/이/질문/etc) ·
G3 language matches ACTIVE CLAIM (Hangul claim → Hangul question) ·
G4 exactly one "?", no conjunction joiners (그리고/~고/and/;) ·
G5 not a restatement of the claim · G6 stay on the active claim, no thread-switch frames.
If your draft fails any guard, REWRITE before emitting.

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
- Read `.mode` to determine `MODE=auto|interactive`. If missing, default to `auto`.
- Read `tree.json`, walk `cursor` → that is the active claim for the next round.
- Determine N: `python3 -c "import json,sys; ls=open('$RUN_DIR/events.jsonl').readlines(); rounds={json.loads(l)['round'] for l in ls if l.strip()}; print(max(rounds)+1 if rounds else 1)"`.
- If `MODE=auto`: arm Monitor (per "## Main-session orchestrator", "### Launcher entry", step 2) and re-enter the launcher loop starting at round N. The tree.json `cursor` and events.jsonl max-round determine where to resume.
- If `MODE=interactive`: skip to Step 1 of round N in the legacy "## Each round" section.

If invoked as `/deeper resume` with NO run-id, call `AskUserQuestion` to pick from recent runs:
- Title: `이어서 drill할 run을 골라`
- Options: list the 4 most recent run-ids under `runs/deeper/` (sort by mtime desc), each labeled with the run-id + the seed snippet (first 40 chars of `seed.md`).
- On selection, treat the chosen run-id as the resume target and continue per above.

## Hard cap

**Interactive mode**: if N reaches 20 without an exit, present the user three options (use AskUserQuestion):
- **Continue** — relax the cap, keep drilling
- **Accept current as provisional bedrock** — close active leaf with category `stated-value` (note: user-provisional, not user-asserted)
- **Abort with partial trace** — write outcome.json with status=hard_cap

**Auto mode**: if N reaches `DEEPER_AUTO_CAP` (default 8) without an exit, the launcher loop breaks and routes to "## After completion (exit handler)" with status `auto_cap`. The exit handler renders the tree + dispatch chain and offers next actions via `AskUserQuestion`.

## RED FLAGS — refuse these in YOURSELF (LAUNCHER)

The launcher orchestrates the round loop itself, but it NEVER produces content — Q and A always come from fresh Explore subagents.

| Thought | Reality |
|---|---|
| "The user is asking about the claim — let me just answer directly" | NO. The claim text is for the Q-subagent and A-subagent, not for you. Dispatch them. The launcher does mechanical I/O, never content. |
| "Q-subagent output looks shallow; let me rewrite it" | NO. Pass through verbatim to .q-raw-{N}.txt. If quality is bad, that's a BANS / judge lesson for the next run, not a launcher correction. |
| "A-subagent's answer should be different — let me modify it" | NO. The A-subagent's output goes to model.py verbatim. Same fresh-context discipline as Q. |
| "Let me read tree.json and reason about the claims" | NO. Read tree.json only to extract `cursor` and assemble the ancestor chain. Do not interpret the claims themselves. |
| "Let me end the turn between rounds — multi-turn looks cleaner" | NO. The launcher loops rounds in a single turn until done/cap. Single-turn looping is REQUIRED to avoid the judge_result-notification race (a fast judge.sh consumes the wake notification mid-turn, leaving no pending notification → deadlock). Monitor's stream still surfaces each Rx event as a system reminder; focus mode hides intermediate assistant text but tool-call events remain visible. |
| "Let me arm Monitor as background but skip looping in this turn" | NO. The Monitor is a visualization channel only — it cannot wake the launcher reliably (race condition documented above). The loop body itself drives round progression. |
| "I'll re-read events.jsonl to confirm whether the drill is done" | NO. The judge.sh exit code IS the authoritative signal: `0`=continue, `100`=done, `1`=error. Re-reading events.jsonl re-introduces the same class of secondary-state-dependence that caused the original race. Trust the integer; do not double-check. |
| "Let me parse model.py stdout AFTER appending to state.md to detect BLOCKED" | NO. Capture `MODEL_OUT` in a variable BEFORE the redirect, check the `BLOCKED:` prefix on the variable, then append. Pulling state back out of a file you just wrote is exactly the secondary-read pattern that race conditions thrive on. |
| "User message mid-drill — let me interpret it as a normal answer" | NO. The A-subagent answers, not the user. A mid-drill user message means STOP/interrupt. End the drill cleanly via "## After completion" with status `aborted` reason `user_interrupt`. |
| "Interactive mode is safer, let me default to that" | NO. Default = auto. Interactive only when the user explicitly types `interactive`. |
| "Let me skip Monitor — it's just decoration" | NO. Monitor is the user-visible progress channel. Without it, focus mode shows nothing until completion. Arm it at launcher entry unconditionally. |
| "I'll just ask the user inline in text — saves a tool call" | NO. Any user choice between options goes through `AskUserQuestion`. The structured UI is the visible boundary between drill state and main-session conversation. Plain text only for free-form seed entry. |

## Why per-round subagent dispatch

In a single Claude session, context grows across rounds and the model starts rationalizing its own prior reasoning — the exact drift Huntley's ralph fixes. Per-round dispatch keeps each question generation cold: only PROMPT.md + BANS.md + the ancestor chain enter the subagent's context. The orchestrator is pure I/O + dispatch. This is the only known way to keep depth-first discipline across many rounds without drift.

For full design rationale and source attributions, see `docs/deeper-v0-design.md` and `docs/ATTRIBUTION.md`.
