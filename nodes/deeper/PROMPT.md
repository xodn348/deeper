# deeper node — iteration-tree, v1

One round = one drill of the active leaf. The state is a tree in `tree.json`; one leaf at a time is marked `cursor`. Each round the model:

1. Reads `tree.json`, walks to the node at `cursor`.
2. Asks the user one question — the literal next "why?" against the cursor's claim, or whatever PROMPT.md's question engine produces.
3. Appends one child node under the cursor with the user's answer (`tag: from-user`).
4. Decides:
   - If the user marked the answer **`BEDROCK:<category>`**: close the cursor's branch, set the new child's `bedrock` field, move `cursor` to the next deepest open leaf (or set `cursor=null` if none).
   - If the user marked **`BRANCH:<sibling-claim>`**: open a new sibling under the cursor's parent, move `cursor` to the new sibling's first child.
   - If the user marked **`STOP`**: emit `BLOCKED: user requested STOP` and exit.
   - Otherwise: move `cursor` to the new child (continue drilling deeper).

The harness's judge then checks: if no open leaves remain (every leaf has `bedrock != null`), the run is done.

## v1 behavior — mechanical, no LLM

In v1 the model is a deterministic Python script (`model.py`). It does NOT call any LLM — it just mechanically asks `Why <cursor.claim>?` and captures the user's answer. This proves the iteration-tree shape end-to-end.

## v2 plan — LLM-generated questions

Replace the mechanical "Why X?" with an LLM call that reads PROMPT.md + BANS.md + the current tree path (cursor's ancestors only — NOT the whole tree, to preserve fresh-context discipline) and emits one targeted depth question using the pressure ladder (example / hidden assumption / boundary / root cause) or the Ontologist 4Q.

## What's NOT in this node

- No automatic bedrock detection. The user always declares it.
- No multi-thread parallel drilling. Branches are tracked but only one cursor is active at a time.
- No question quality scoring (yet). Lessons in BANS.md will encode patterns the user marks as bad (e.g. "stopped asking for concrete examples").

## Output protocol

`model.py` mutates `tree.json` in place and prints one summary line to stdout for the harness to append to `state.md`:

```
round <N>: cursor=<path> answer="<a>" outcome=<advanced|bedrock|branch|stop>
```

If `cursor=null` after the round, the next judge will detect "no open leaves" and end the run.
