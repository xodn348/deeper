# Deeper repo conventions for Claude Code sessions

## Auto-merge feature branches into main

When you complete work on a feature/worktree branch in this repo (typically a `worktree-*` branch created via `EnterWorktree` from a background session), do not stop and ask "should I merge?". Fast-forward merge into `main` automatically as the final step of the task, before reporting completion.

Sequence:

```bash
git -C ~/code/deeper merge --ff-only <branch-name>
```

If the merge cannot fast-forward (diverged main, conflicts), stop and ask the user — that case needs judgment. Otherwise proceed silently.

**Why:** This repo's workflow keeps short-lived branches that exist only to satisfy the background-session worktree-isolation guard. There is no review gate that merging would bypass — the user has already approved the work by the time the branch is committed. Asking "merge?" each time adds a round-trip for no benefit. (Same spirit as `feedback_museum_as_code_auto_merge.md` in user memory, scoped to this repo.)

**Scope:** Local fast-forward merges only. Pushing to `origin` is a separate decision — do not push without explicit user instruction.

## SOPs live in this repo, not in pegasus-os

Deeper-specific methodology documents go in `~/code/deeper/docs/` (e.g., `INVOCATION-SOP.md`), not in `~/code/pegasus-os/claude/sops/`. The pegasus-os SOP repo convention in the user's global CLAUDE.md applies to cross-project workflow SOPs only. Deeper-internal rules stay inside the deeper repo so they version with the code that depends on them.

Memory symlinks (`~/.claude/projects/-Users-jnnj92/memory/feedback_deeper_*.md`) point at files under `~/code/deeper/docs/` for this repo's SOPs.
