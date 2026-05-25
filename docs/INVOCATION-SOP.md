---
name: /deeper invocation methodology — transactional cwd + worktree-per-call + two-layer logging
description: Every /deeper invocation must run a pre-flight that borrows the launcher cwd into $DEEPER (default ~/code/deeper) (so worktree isolation works), restores it on exit (so the user's original working context survives), and logs every enter/exit/failed event to $DEEPER_HOME/runs/deeper/.launcher.jsonl (default ~/.deeper/runs/deeper/.launcher.jsonl). Worktree isolation per invocation is provided by Claude's native Agent(isolation:"worktree") mechanism — do not roll your own. Applies to /deeper in any cwd.
type: feedback
---

When the user runs `/deeper` (or `/deeper auto`, `/deeper interactive`, `/deeper resume`), follow this invocation methodology before mode-determination, run-state setup, Monitor arming, or any Agent dispatch.

**Why:** `/deeper` can be invoked from any cwd ($HOME, another project being debugged, a sibling repo). `Agent(isolation:"worktree")` — the mechanism that gives the orchestrator subagent its isolated git worktree and the UI hookup in Claude Code — only works when the launcher's cwd is inside a git repo. A naive launcher fails immediately with `Cannot create agent worktree: not in a git repository`. A naive fix ("just `cd ~/code/deeper`") strands the user's session inside the deeper repo even after the drill ends, breaking whatever workflow they were in before.

**How to apply:** every `/deeper` invocation follows this 4-principle methodology.

## Principle 1 — Transactional cwd (borrow, restore)

The launcher cwd is borrowed into `~/code/deeper` for the duration of the drill, then restored to wherever the user invoked from. The cwd is treated as a transactional resource — acquired at pre-flight, released at exit, with the original value persisted to the run dir so even a session-resume can restore it.

**Step 0 — Enter (BEFORE anything else):**

```bash
ORIG_CWD="$(pwd)"

DEEPER="${DEEPER:-$HOME/code/deeper}"
DEEPER_HOME="${DEEPER_HOME:-$HOME/.deeper}"
test -d "$DEEPER/.git" || {
  python3 -c "import json,time; print(json.dumps({'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'event':'launcher_failed','orig_cwd':'$ORIG_CWD','reason':'deeper_repo_missing'}))" >> "$DEEPER_HOME/runs/deeper/.launcher.jsonl" 2>/dev/null || true
  echo "failed: deeper repo missing at $DEEPER — install or clone before retrying."
  exit 1
}

cd "$DEEPER"

mkdir -p "$DEEPER_HOME/runs/deeper"
python3 -c "import json,os,time; print(json.dumps({'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'event':'launcher_enter','orig_cwd':'$ORIG_CWD','pid':os.getpid()}))" >> "$DEEPER_HOME/runs/deeper/.launcher.jsonl"
```

After `RUN_ID` and `$RUN_DIR` are created in the existing skill flow, persist the original cwd into the run state:

```bash
echo "$ORIG_CWD" > "$RUN_DIR/.orig-cwd"
```

**Step N — Exit (EVERY exit path — success / auto_cap / aborted / failed):**

```bash
ORIG_CWD="$(cat "$RUN_DIR/.orig-cwd" 2>/dev/null)"
python3 -c "import json,time; print(json.dumps({'ts':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'event':'launcher_exit','run_id':'$RUN_ID','status':'$STATUS','orig_cwd':'$ORIG_CWD'}))" >> "$DEEPER_HOME/runs/deeper/.launcher.jsonl"
[ -n "$ORIG_CWD" ] && [ -d "$ORIG_CWD" ] && cd "$ORIG_CWD"
```

## Principle 2 — Worktree per invocation (native, not custom)

Do **not** roll a custom `git worktree add` flow. The cd from Principle 1 enables `Agent(isolation:"worktree")` — Claude's native mechanism — which:

- creates `$DEEPER/.claude/worktrees/agent-<id>/` per dispatch
- auto-names so concurrent `/deeper` invocations get disjoint worktrees
- branches from `origin/main` (per `worktree.baseRef=fresh`) so the main checkout's state never leaks
- hooks into Claude Code's worktree UI for visibility
- auto-cleans on agent exit if no changes were made

The custom layer adds only the cwd transaction — everything below it stays native.

## Principle 3 — Two-layer logging

- **Per-run drill log** (already exists): `$RUN_DIR/events.jsonl` — every Q/A, judge result, stall, run_finished.
- **Cross-run launcher log** (new, this SOP): `$DEEPER_HOME/runs/deeper/.launcher.jsonl` (default ~/.deeper/runs/deeper/.launcher.jsonl) — one line per `launcher_enter` / `launcher_exit` / `launcher_failed`. Records ts, orig_cwd, RUN_ID, status, pid.

Together they let you reconstruct any past invocation: "what was the 3rd `/deeper` call yesterday?" → grep `.launcher.jsonl` by date → get `RUN_ID` → read `$RUN_DIR/events.jsonl`.

## Principle 4 — Match Claude Code's internal mechanisms

The custom layer is *thin*. Specifically:

- worktree creation: native `Agent(isolation:"worktree")` (not manual `git worktree add`)
- background dispatch: native `run_in_background:true`
- event perception: native `Monitor` tool tailing `events.jsonl`
- completion signal: native agent completion notification

The SOP adds two things only: (a) the transactional cwd wrapper around the dispatch, and (b) the cross-run launcher log. Nothing else duplicates Claude internals.

## Invariants (testable)

1. After every `/deeper` invocation finishes (regardless of status), `pwd` in the launcher session equals the value of `pwd` immediately before the invocation.
2. `$DEEPER_HOME/runs/deeper/.launcher.jsonl` gains exactly one `launcher_enter` line at start and exactly one `launcher_exit` (or `launcher_failed`) line at end of every invocation.
3. Concurrent `/deeper` invocations never share a worktree directory (`$DEEPER/.claude/worktrees/agent-<id>/` is per-dispatch, ids are unique).
4. `$RUN_DIR/.orig-cwd` exists for every run, so a session resume can recover the original cwd.

## Don'ts

- Don't skip pre-flight "because the user already invoked from inside the repo." Idempotent — verify and cd anyway.
- Don't replace `Agent(isolation:"worktree")` with a manual `git worktree add` flow to "work around" the cwd requirement. You lose the UI hookup and concurrent-safe auto-naming for nothing.
- Don't compress the pre-flight into a single inline command "for brevity." Each line is load-bearing — the repo check is the only failure path, the cd is the cwd borrow, the log line is the audit trail.
- Don't forget the exit handler in error paths. Restoration must happen in `aborted` and `failed` paths too, not just `passed`.

## Related

- `[[focus_mode_inline]]` — `/deeper` runs in focus mode by default; final message visible only.
- `[[worktree_parallel]]` — different topic (multi-pane orchestration); shares the worktree primitive but not the invocation discipline.
