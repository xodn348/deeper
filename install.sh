#!/usr/bin/env bash
# deeper installer — wires the /deeper slash command and the deeper-native
# workflow into Claude Code. Idempotent: safe to re-run any time (it just
# re-asserts the symlinks). Run from anywhere — the repo root is resolved from
# this script's own location, so a clone at any path works.
#
#   bash /path/to/deeper/install.sh
#
# Honors $CLAUDE_CONFIG_DIR (defaults to ~/.claude).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
WORKFLOWS_DIR="$CLAUDE_DIR/workflows"

mkdir -p "$SKILLS_DIR" "$WORKFLOWS_DIR"

# /deeper slash command -> v2 skill (which auto-launches the deeper-native workflow)
ln -sfn "$REPO/skills/deeper" "$SKILLS_DIR/deeper"
# the workflow the skill launches
ln -sfn "$REPO/workflows/deeper-native.js" "$WORKFLOWS_DIR/deeper-native.js"

# verify both resolve
ok=1
[ -f "$SKILLS_DIR/deeper/SKILL.md" ]      || { echo "  ✗ skill did not resolve: $SKILLS_DIR/deeper" >&2; ok=0; }
[ -e "$WORKFLOWS_DIR/deeper-native.js" ]  || { echo "  ✗ workflow did not resolve: $WORKFLOWS_DIR/deeper-native.js" >&2; ok=0; }
[ "$ok" = 1 ] || exit 1

echo "deeper installed (idempotent):"
echo "  /deeper            -> $SKILLS_DIR/deeper -> $REPO/skills/deeper"
echo "  deeper-native (wf) -> $WORKFLOWS_DIR/deeper-native.js -> $REPO/workflows/deeper-native.js"
echo
echo "Use it in Claude Code:  /deeper why does X keep happening?"
