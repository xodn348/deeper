---
name: deeper
description: Depth-first interview that drills ONE claim to its bedrock (first principle / axiom / source of truth) via per-round fresh-subagent dispatch. Use when the user wants to ROOT-CAUSE something rather than survey it; when the question is "why is this REALLY the case?" not "what are the options?"; or when locking down a single decision's foundation before further work. Inverts the breadth-keeper guards found in superpowers:brainstorming, omx:deep-interview, ouroboros.
---

# deeper — depth-first interview (Claude Code edition)

You are the LAUNCHER, not the orchestrator. The orchestration happens **inside an isolated worktree subagent** dispatched in the background; the launcher arms a perception loop in the SAME turn so the drill streams progress live into chat. You do not reason about the user's claim. You set up state, dispatch the orchestrator (background) + Monitor (events stream), and surface what arrives. Nothing else.

## Repository assumption

This skill expects the `deeper` repo at `~/code/deeper/`. All paths below resolve from there.

## On invocation

**UI discipline (main-session launcher only)**: when the launcher needs the user to choose between options, ALWAYS use the `AskUserQuestion` tool — never a plain text prompt embedded in your message. The structured UI makes it visually unambiguous that the question is coming from the main session, not from whatever the worktree orchestrator is doing. Plain text is fine only for free-form input (e.g. seed claim entry) where no discrete options exist.

1. **Determine the mode and seed claim.**
   - **Default — worktree auto.** If the invocation is `/deeper <claim>` or `/deeper auto <claim>`, set `MODE=auto` and seed = the claim text. The entire drill runs in a worktree-isolated orchestrator subagent; the main session sees only the final dispatch tree.
   - **Explicit interactive.** If the invocation begins with `interactive` (e.g. `/deeper interactive <claim>`), set `MODE=interactive` and run the per-round loop in the main session, ending the turn after each question to await the user's reply. This is the legacy human-in-loop path.
   - **Resume.** If the invocation begins with `resume <run-id>`, see **## Resumption** below.
   - **Ambiguous invocation** (no claim, or just `/deeper` with no arg): call `AskUserQuestion` to pick the mode (single-select):
     - **Auto (recommended)** — worktree-isolated, hands-off, ~8 rounds
     - **Interactive** — human-in-loop, you answer each round in chat
     Then end your turn. On the user's reply, ask for the seed claim as plain text (free-form, no fixed options).

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
   - `MODE=auto`: go to **## Worktree-isolated orchestrator** below. In the SAME turn:
     (a) arm `Monitor` tailing `$RUN_DIR/events.jsonl` through `format-events.py` so
         each event becomes one chat line, then
     (b) dispatch the orchestrator with `isolation: "worktree"` AND
         `run_in_background: true`, then
     (c) tell the user one line ("Run started: $RUN_ID — streaming progress below.")
         and end the turn cleanly. You will wake on each Monitor notification (one
         per event) and on the orchestrator's completion notification. **Never enter
         the per-round loop yourself.**
   - `MODE=interactive`: enter the per-round loop starting at N=1 (the legacy "## Each round" protocol below).

## Worktree-isolated orchestrator (auto mode — default)

The launcher executes THREE tool calls in one turn, then ends the turn:

### A. Arm the perception loop (Monitor)

```
Monitor(
  command: "tail -F -n 0 \"$RUN_DIR/events.jsonl\" | python3 -u $HOME/code/deeper/nodes/deeper/format-events.py",
  description: "deeper $RUN_ID events stream",
  persistent: true,
  timeout_ms: 3600000
)
```

Each `format-events.py` stdout line becomes one launcher notification:
`[R{n} Q] ...` / `[R{n} A] ...` / `[R{n} ✓] depth=D done=B` / `[R{n} ⚠] STALL: ...` /
`─── deeper {status} ───`. Capture the Monitor task id (returned by the tool) — you
will pass it to `TaskStop` when the orchestrator completes.

### B. Dispatch the orchestrator in the background

```
Agent(
  subagent_type: "general-purpose",
  isolation: "worktree",
  run_in_background: true,
  description: "deeper auto drill",
  prompt: <orchestrator template below>
)
```

Substituting `{RUN_ID}`, `{RUN_DIR}`, `{SEED}`, and `{CAP}` (default 8, override via
`DEEPER_AUTO_CAP` env). Capture the agent id — the completion notification will
reference it.

### C. Tell the user one line and end the turn

Example: `Run started: $RUN_ID (auto, cap=$CAP). Streaming progress — orchestrator running in background.`

Then end the turn. Do NOT loop, do NOT poll. Wake on:
- **Each Monitor notification** — the body IS a formatted event line. Emit it
  verbatim to the user as a one-line text message, then end the turn.
- **Orchestrator completion notification** — see "## After orchestrator completes" below.

### Orchestrator template (substitute placeholders, send as `prompt`)

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

2. Dispatch a Q-subagent (Agent tool, subagent_type "Explore", **model: "haiku"** —
   one-line emission is format-bound, judgment not required; escalate to "sonnet" only
   if BANS.md flags repeated G-violations for haiku on this claim type, or to "opus"
   for genuinely cryptic abstract claims). Prompt:

   You are deeper-round-{N}. Output exactly ONE depth question — no preamble,
   no "Question:", nothing else.

   ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md in full and follow it.
   BINDING LESSONS: read <DEEPER_ROOT>/nodes/deeper/BANS.md in full.

   HARD GUARDS (binary self-check before you emit — see PROMPT.md "HARD GUARDS" for
   full text): G1 one non-empty line · G2 no forbidden first tokens (Sure/Here/먼저/이/
   질문/etc) · G3 language matches ACTIVE CLAIM (Hangul claim → Hangul question) ·
   G4 exactly one "?", no conjunction joiners (그리고/~고/and/;) · G5 not a restatement
   of the claim · G6 stay on the active claim, no thread-switch frames. If your draft
   fails any guard, REWRITE before emitting.

   ANCESTOR CHAIN:
   {numbered chain — one line per ancestor, format: "N. <claim>"}

   ACTIVE CLAIM to drill: "{active_claim}"

   Output exactly ONE line: the depth question.

   Save the verbatim Q-subagent output to `$RUN_DIR/.q-raw-{N}.txt`. Emit a
   question_emitted event to `$RUN_DIR/events.jsonl` with question (last non-empty
   line), raw_chars, raw_lines.

3. Dispatch an A-subagent (Agent tool, subagent_type "Explore", **model: "sonnet"**
   — judgment-bound: must decide free-text vs BEDROCK vs BRANCH and pick the right
   axiom category. Escalate to "opus" when the claim is genuinely deep / multi-step
   reasoning is needed; downshift to "haiku" only for trivially shallow seeds). Prompt:

   You are deeper-answer-{N}. The interview is autonomous — you stand in for the
   human respondent.

   ROLE: read <DEEPER_ROOT>/nodes/deeper/PROMPT.md (you are answering, but the
   same depth discipline applies — be concrete, specific, honest about uncertainty).

   HARD GUARDS for your answer (binary self-check before emit):
   - A1: Your response is EXACTLY ONE of: (a) 1–3 sentence free-text answer
         (NO BEDROCK:/BRANCH: prefix), (b) a single line starting `BEDROCK:`,
         (c) a single line starting `BRANCH:`. Mixed forms = fail.
   - A2: Forbidden first tokens: `Sure`, `Here`, `OK`, `Answer`, `A:`, `먼저`,
         `우선`, `답`, `답변`, `이`. First token = first substantive word, or
         the literal `BEDROCK:` / `BRANCH:` prefix.
   - A3: Language match — Hangul in ACTIVE CLAIM → Hangul in your answer.
   - A4: If you emit `BEDROCK:<cat>`, <cat> MUST be EXACTLY one of:
         stated-value | constraint | prior-decision | external-rule | identity | empirical.
         Misspelling, synonym, or made-up category = fail.
   - A5: Honest uncertainty — if you don't know a fact, say "I don't know X"
         concretely. No hedge-filler ("perhaps", "maybe", "it could be") used to
         dodge committing.

   If your draft fails any guard, REWRITE before emitting.

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

   Save the verbatim A-subagent output to `$RUN_DIR/.a-raw-{N}.txt`.

   STALL SELF-HEAL — strip the saved file's content; if it is empty or whitespace-only:
     i.   Append event {"type":"stall","round":N,"reason":"empty_a_sonnet"} to
          `$RUN_DIR/events.jsonl` (this surfaces to the launcher as `[R{N} ⚠]`).
     ii.  Re-dispatch the SAME A-subagent prompt with model "opus" (judgment escalation).
          Overwrite `.a-raw-{N}.txt` with the retry output.
     iii. If the retry is ALSO empty:
            - Append event {"type":"stall","round":N,"reason":"empty_a_after_opus_retry"}.
            - Overwrite `.a-raw-{N}.txt` with the literal string `STOP` (this triggers
              model.py's BLOCKED path — model.py line 119: `if answer == "STOP"`).
            - Proceed to step 4. model.py will print `BLOCKED: user requested STOP`,
              the loop will exit cleanly at step 6, and STATUS will be `aborted`
              with exit_reason `stall_round_N`.

   Only AFTER the stall handler resolves (non-empty A, or STOP sentinel written),
   emit an answer_emitted event to `$RUN_DIR/events.jsonl` (answer, source="subagent"
   or "subagent-opus-retry"; if STOP was written, set source="stall-stop-sentinel").

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
- Append a terminal event {"type":"run_finished","status":STATUS,"rounds":N,"score":final_score} to `$RUN_DIR/events.jsonl`. This is the perception-loop sentinel — the launcher's formatter prints `─── deeper {status} ───` and the launcher knows to render the tree and close the run.

RETURN to the launching session: a single text block containing
  1) one-line summary: "status=<STATUS> rounds=<N> score=<S> violations=<aggregated>",
  2) the dispatch chain (render-dispatch.sh output),
  3) the tree (render.sh output),
  4) the path to outcome.json.

Nothing else. No commentary. No analysis of the claim.
```

## After orchestrator completes

The completion notification mentions the agent id you captured in step B. When it arrives:

1. `TaskStop` the Monitor task id captured in step A (stops the tail).
2. Run `bash <DEEPER_ROOT>/nodes/deeper/render-dispatch.sh "$RUN_DIR"` and
   `bash <DEEPER_ROOT>/nodes/deeper/render.sh "$RUN_DIR"` — print both to chat so
   the user sees the final dispatch chain + tree (they already saw rounds live;
   this is the consolidated closing view).
3. Surface the orchestrator's returned block verbatim (its summary line + outcome.json path).
4. Call `AskUserQuestion` to offer next-step actions — the structured UI is the
   visible signal that control has returned to the main session and the drill is done.

Question: `이 drill 이후로 뭘 할까?`

Options depend on the returned STATUS:

- `status=passed` (drill closed all leaves):
  - **Run feedback.sh** — promote this run's violations to BANS.md
  - **View tree** — re-render `nodes/deeper/render.sh <RUN_DIR>` in chat
  - **Done** — nothing more

- `status=auto_cap` (hit the round cap without closing):
  - **Resume with +8 rounds (Recommended)** — `/deeper resume <RUN_ID>` with `DEEPER_AUTO_CAP` doubled
  - **Run feedback.sh** — promote partial violations anyway
  - **Accept partial trace** — leave outcome.json as-is, exit
  - **Done** — nothing more

- `status=aborted` (BLOCKED — model.py rejected something):
  - **Inspect events.jsonl** — open the run dir, show the last few events
  - **Resume** — try again with the next round
  - **Done** — nothing more

Then execute whatever the user picked. If they pick **Done** or **Other** with no actionable text, end your turn silently. **Never** narrate or "interpret" the drill's outcome — surface the orchestrator's block, surface the UI choices, do what's picked, stop.

That ends the main session's involvement.

## Each round (interactive mode only — `/deeper interactive <claim>`)

This is the legacy human-in-loop path: the main session generates the question, asks the user, applies their reply, loops. **Auto mode uses the worktree-isolated orchestrator above and does not enter this section.**

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
- If `MODE=auto`: dispatch the worktree orchestrator with the existing RUN_DIR (the orchestrator's per-round loop already handles resuming via tree.json + events.jsonl).
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

**Auto mode**: if N reaches `DEEPER_AUTO_CAP` (default 8) without an exit, the orchestrator writes outcome.json with status=auto_cap, renders the dispatch chain, and exits the worktree. Control returns to the main session launcher, which then offers next actions via `AskUserQuestion` (see the post-dispatch options block above). The orchestrator never asks the user directly — it only returns its block.

## RED FLAGS — refuse these in YOURSELF (LAUNCHER)

These apply to the MAIN-SESSION LAUNCHER (you, right now). The orchestrator subagent inside the worktree has its own absolute rules in its prompt template.

| Thought | Reality |
|---|---|
| "The user is asking about the claim — let me just answer directly" | NO. You are the LAUNCHER. The claim text is for the worktree orchestrator, not for you. Never answer the claim, never assess it, never offer an alternate response. Dispatch the orchestrator. |
| "Round 1 ended; let me pick it back up in this session" | NO. The launcher only WAKES for Monitor notifications and orchestrator completion — it never executes a round. Each wake = emit one line, end turn. The drill itself runs entirely inside the background orchestrator. |
| "The orchestrator subagent's output looks shallow; let me extend it" | NO. Pass through verbatim. If quality is bad, that's a BANS / judge lesson for the next run. |
| "Let me read PROMPT.md / tree.json myself to add context" | NO. Main session reads NOTHING about the claim. Only the run dir paths and final outcome. |
| "I'll write the answer because the subagent might say something I disagree with" | NO. The worktree orchestrator handles all Q and A. Main session never produces content. |
| "Interactive mode is safer, let me default to that" | NO. Default = worktree auto. Interactive only when the user explicitly types `interactive`. |
| "Let me analyze the user's claim while waiting for the orchestrator" | NO. You are not "waiting" — you ended your turn. Wake-events come automatically. On each wake, emit the formatted event line verbatim. Do not interpret, do not extrapolate, do not commentary the claim. |
| "I'll just ask the user inline in text — saves a tool call" | NO. Any user choice between options goes through `AskUserQuestion`. The structured UI is the visible separator between main session and worktree. Plain text only for free-form input. |
| "The orchestrator could ask the user directly mid-drill" | NO. The orchestrator runs in an isolated worktree and never has a turn boundary with the user. It returns one block at the end. All user prompts are launcher-side via `AskUserQuestion`. |

## Why per-round subagent dispatch

In a single Claude session, context grows across rounds and the model starts rationalizing its own prior reasoning — the exact drift Huntley's ralph fixes. Per-round dispatch keeps each question generation cold: only PROMPT.md + BANS.md + the ancestor chain enter the subagent's context. The orchestrator is pure I/O + dispatch. This is the only known way to keep depth-first discipline across many rounds without drift.

For full design rationale and source attributions, see `docs/deeper-v0-design.md` and `docs/ATTRIBUTION.md`.
