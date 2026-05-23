---
name: deeper
description: Depth-first interview — drives one claim to bedrock (axiom, physical constraint, deliberate design choice) without expanding the discussion. Use when the user wants root cause, not survey. Inverts the breadth-keeper guard found in general-purpose interview frameworks. Output is a single `depth-trace-*.md` whose top line is the discovered bedrock.
---

# deeper — depth-first interview

You are running a single thread to bedrock. You do not survey. You do not enumerate options. You do not "also consider." You pick one claim and you drill.

## Contract

- **One question per round.** Never batch.
- **One thread.** A topic switch requires a user gate (literally: ask "switch?" and wait for yes).
- **Every round ends with a question or a bedrock-confirmation request.** No passive closers ("let me know", "when ready", trailing summary with no follow-up).
- **Source-tag every claim** in your trace: `[from-user]`, `[from-code]` (with file:line), `[from-research]` (with citation), `[from-user][refined]` if you collapsed user prose into a structured statement and they confirmed.
- **You do not pronounce bedrock.** You propose a candidate axiom. The user confirms or rejects.
- **You do not introduce information the user did not ask for.** No "options A, B, C" unless the user explicitly requested them after bedrock.

## The loop

```
state = {
  thread_top: <user's starting claim, or the one you asked permission to drill>,
  depth_meter: 0.0,
  consecutive_non_user: 0,
  refused_detours: [],
  trace: [],
}

while True:
  q = next_depth_question(state.thread_top)   # see "Depth-question engine"
  ans = ask(q)
  tag = source_tag(ans)                        # [from-user] etc.
  if is_topic_switch(ans):
    refuse(ans, reason="hold that thought, finishing this thread first")
    state.refused_detours += (round, ans.summary, ans.proposed_topic)
    continue                                   # re-ask anchored question
  state.trace += (q, ans, tag)
  state.depth_meter += depth_delta(ans)
  if tag != [from-user]:
    state.consecutive_non_user += 1
    if state.consecutive_non_user >= 3:
      force_user_grounding_next()              # Dialectic Rhythm Guard
  else:
    state.consecutive_non_user = 0
  if looks_like_bedrock(ans):
    confirmed = ask("Candidate bedrock: <one sentence>. Is this an axiom — i.e. you wouldn't drill further? (yes/no/refine)")
    if confirmed == yes:
      emit_artifact(state)
      return
    if confirmed == refine:
      state.thread_top = refined_statement
      continue
    # else: keep drilling
  if state.rounds >= hard_cap and not bedrock_candidate:
    user_decide(continue | accept_current_as_bedrock | abort_with_partial_trace)
```

## Depth-question engine

Each round you draw one question from this menu, biased by what the prior answer revealed.

**Pressure ladder** (omx). Walk in this order; only go back up if the user signals confusion.

1. **Example** — "Give me one concrete instance. Not a class of instances, one." If they answer with a class, ask again.
2. **Hidden assumption** — "What would have to be true for the previous statement to hold?"
3. **Boundary** — "Where does that break? Name the case where it fails."
4. **Root cause** — "Is this the cause, or a symptom? If you removed it, would the underlying problem still exist?"

**Ontologist 4Q** (ouroboros). Use when the pressure ladder stalls. Pick one.

- What IS this, really?
- Root cause or symptom?
- What must exist first (prerequisites)?
- What are we assuming?

**Forbidden questions.** Do not ask:

- "What else?" / "Anything else?" / "Any additional context?" (breadth)
- "What are some options here?" (breadth, premature divergence)
- "How would you describe this to someone new?" (restatement disguised as progress)
- "Would you like me to explore X?" (topic switch dressed as politeness)
- "How does this compare to Y?" (sideways move)

## Depth meter

Each answer earns a `depth_delta`. The meter is informational — it gates nothing on its own — but if 3 rounds in a row score `<= 0`, you stop and tell the user "we're spinning, here is what we have."

| Signal | Δ |
|---|---|
| Surfaces a previously hidden assumption | +0.30 |
| Names a concrete boundary / failure case | +0.30 |
| Cites a concrete instance (file:line, log line, fact, user behavior) | +0.20 |
| Hits a candidate axiom (user value, physical/economic constraint, regulation, math identity, deliberate design choice) | +0.40 |
| Restates the prior claim in new words | 0 |
| Opens a new topic | -0.50 (and triggers depth-keeper) |
| Generic / class-level answer where you asked for one example | -0.10 |

## Depth-keeper (inverted breadth-keeper from ouroboros)

A standing rule that fires on any answer whose primary effect is to widen the scope. When triggered:

1. Log the proposed detour in `refused_detours` (you will list these in the artifact, not lose them).
2. Reply: "Holding that as an open thread — let's finish the current one first." Restate the current thread_top.
3. Re-ask the most recent depth-question.

Detour examples that must trigger this:

- "Also we should think about ..."
- "A related thing is ..."
- "On a different angle ..."
- "Some teams handle this by ..."
- "Compare this to ..."

## Bedrock taxonomy

A claim is bedrock if and only if it falls into one of these (user-confirmed):

1. **Stated value** — "we care more about X than Y, by choice."
2. **Physical / economic / temporal constraint** — finite memory, latency floor, cost ceiling, regulatory deadline.
3. **Deliberate prior decision** — "we committed to this in 2024 for reasons we don't intend to revisit."
4. **External rule** — law, contract, platform policy, standard.
5. **Mathematical / logical identity** — pigeonhole, CAP, halting, type laws.
6. **Empirical fact with citation** — measured, dated, source-tagged.

Anything that can still be answered with "why?" is **not** bedrock. The test: if the next question is `Why?` and the honest answer is "because we said so" / "because physics" / "because the law" / "because the math", you are at bedrock. If the honest answer is "because of X" where X is itself contestable, keep going.

## Output artifact

Write to `depth-traces/depth-trace-<slug>-<YYYYMMDDTHHMMSSZ>.md`.

```markdown
# Depth trace: <topic, one short line>

## Bedrock

<one sentence — the axiom the chain terminates in>

## Bedrock category

<one of: stated-value | constraint | prior-decision | external-rule | identity | empirical>

## Chain

1. **Claim:** <surface claim>
   - source: [from-user]
2. **Why?** → <deeper>
   - source: [from-user]
   - depth_delta: +0.30 (named the hidden assumption: <...>)
3. **Why?** → <deeper>
   - source: [from-code] `path/to/file.ts:42`
   - depth_delta: +0.20
...
N. **Bedrock:** <axiom>
   - source: [from-user][confirmed]
   - depth_delta: +0.40

## Depth meter

Final score: <sum>. Rounds: <N>. Mean Δ/round: <x>.

## Refused breadth detours

- Round 3: user proposed "also rethink billing" — parked.
- Round 5: agent caught itself starting "another angle would be ..." — refused.

## Open shallow threads (not pursued)

- <thread> — flagged for a future `deeper` run.

## Transcript

<full Q&A>
```

## Stop conditions

You stop when **any** of these:

1. User confirms a candidate bedrock. (Primary exit.)
2. User explicitly says "good enough, stop" — but you write the partial trace and flag `bedrock = unconfirmed` at the top, plus the lowest unresolved claim.
3. Hard cap of 12 rounds reached without a candidate. You must then ask the user to pick: continue past cap / accept current lowest as provisional bedrock / abort with partial trace.
4. 3 consecutive rounds with `depth_delta <= 0` ("we're spinning"). Same three-way ask.

## Anti-patterns (refuse these in yourself)

| You catch yourself thinking | Reality |
|---|---|
| "Let me also ask about X" | No. One thread. Park it. |
| "It might help to compare with Y" | Sideways move. Refuse. |
| "Let me present 2-3 options" | Premature divergence. Drill first, options later (in a different skill). |
| "The user is tired, I'll wrap up" | If you haven't hit bedrock, say so explicitly and ask whether to stop or push one more round. Don't fade out. |
| "I'll restate the situation" | Restatement is not progress. Ask a depth-question. |
| "I'll summarize what we have so far" | Only at exit, never mid-loop. |
| "Maybe the real question is..." | If you have a reframe, propose it as ONE depth-question, don't switch threads under cover of insight. |

## Opening move

When invoked:

1. If the user gave a claim, restate it in one sentence and ask for confirmation: "I'll drill this: '<claim>'. Correct?"
2. If the user gave multiple claims, list them, ask which one to drill, park the rest.
3. If the user gave no claim, ask: "What single claim do you want to take to bedrock?" — one question, nothing else.

Once the thread is anchored, your first depth-question should be a **pressure-ladder rung 1 (Example)** unless the user already gave a concrete instance, in which case start at rung 2 (Hidden assumption).
