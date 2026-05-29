#!/usr/bin/env bash
# mock-model.sh — deterministic mock for demos. Reads BANS.md via env, outputs
# a commit-msg-shaped string that respects whichever lessons are in BANS.md.
# This is INSTRUMENTATION, not intelligence — it proves the harness pipework works.
# Swap with: MODEL_CMD="claude -p" for a real run.

set -euo pipefail

BANS_CONTENT=""
[ -n "${BANS_FILE:-}" ] && [ -f "$BANS_FILE" ] && BANS_CONTENT=$(cat "$BANS_FILE")

has_conv=false
has_short=false
has_lowerverb=false
grep -q 'conv-format\|conventional' <<< "$BANS_CONTENT" && has_conv=true
grep -q 'length\|under 70' <<< "$BANS_CONTENT" && has_short=true
grep -q 'verb-tense\|imperative' <<< "$BANS_CONTENT" && has_lowerverb=true

if   $has_conv && $has_short && $has_lowerverb; then
  echo "feat(api): add auth middleware to /api/* routes"
elif $has_conv && $has_short; then
  echo "feat(api): Added auth middleware to /api/* routes"
elif $has_conv; then
  echo "feat(api): Added authentication middleware to all the various /api/* routes for security."
elif $has_short; then
  echo "Added auth middleware to /api/* routes for security."
else
  echo "This commit adds authentication middleware to all the /api/* routes in the application for security reasons."
fi
