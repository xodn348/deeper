# ADR-001: Recursive Agent dispatch is blocked inside subagents

**Status**: Accepted (2026-05-24)
**Affects**: `skills/deeper/SKILL.md` auto-mode design (PR #4)

## Context

The current `/deeper` auto-mode design (introduced in PR #4) assumes a two-hop
Agent dispatch chain:

```
main session  ─Agent(bg, worktree)→  orchestrator  ─Agent(Explore)→  Q/A subagent
```

The launcher is a thin shim; the orchestrator runs the whole drill in a
worktree-isolated subagent, dispatching fresh Q-subagents and A-subagents per
round.

## Decision

**The second hop is structurally impossible.** Claude Code blocks Agent
dispatch from inside a subagent. Direct invocation returns:

```
No such tool available: Agent. Agent is not available inside subagents.
Complete the task with the tools provided and return findings to the
orchestrator.
```

Verified 2026-05-24 by direct probe (`probe2`, agentId `a5ac5d17351658c26`).
The official tools-reference page (`code.claude.com/docs/en/tools-reference`)
documents subagent tool inheritance and background auto-deny semantics but
does not name this specific recursion block. The block is enforced at tool
resolution, not via permission policy.

## Consequences

1. The PR #4 orchestrator cannot dispatch Q/A subagents. It either aborts at
   round 0 (the correct outcome — refuse to substitute self-reasoning) or
   produces a fake drill where the orchestrator answers its own prompts and
   labels them `source: subagent`. Both modes break the fresh-context
   discipline that is the entire point of the design.

2. Historical runs (`runs/deeper/deeper-20260523T204752Z` and similar) that
   appear to have completed 5-7 rounds in auto mode are suspect. The
   orchestrator's recursive Agent calls would have failed; the trace likely
   represents self-answered rounds. The original transcripts are not
   recoverable for confirmation.

3. The fresh-context discipline must be re-implemented without recursive
   Agent dispatch. Two viable shapes:

   - **Main-session orchestrator** (revert to pre-PR #4): the launcher runs
     the round loop itself, dispatching `Agent(Explore)` for Q and A.
     Re-introduces the round-1 dropout risk PR #4 set out to fix
     (out-of-protocol main-session messages break the loop).

   - **Bash + Claude CLI sub-process**: orchestrator is a bash script that
     shells out to `claude --print --model haiku ...` for each Q/A. True
     background, no Agent recursion, preserves PR #4 separation of launcher
     and orchestrator.

   The latter is the closer fit to PR #4's intent.

## Not implemented in this ADR

A replacement design. This ADR documents the constraint so the next change
to `SKILL.md` starts from ground truth.
