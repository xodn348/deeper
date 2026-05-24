#!/usr/bin/env bash
# ask.sh — one cold `claude -p` invocation using session auth.
#
# Replaces the prior Agent / Explore-subagent dispatch path (ADR-002).
# Session auth (the user's logged-in Claude Code session) — no ANTHROPIC_API_KEY
# required, no per-call billing. See docs/ADR-003 for rationale.
#
# Usage:
#   ask.sh <model> <sys-file> <user-file>
#
#   <model>     short alias (haiku|sonnet|opus) or full id (claude-haiku-4-5)
#   <sys-file>  path to file containing the full system prompt
#   <user-file> path to file containing the user-turn prompt
#
# Output: model's verbatim stdout response on success.
# Exit:   0 on success, non-zero on transport / auth failure.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'ask.sh: expected 3 args (model sys-file user-file), got %d\n' "$#" >&2
  exit 2
fi

MODEL="$1"
SYS_FILE="$2"
USER_FILE="$3"

[[ -r "$SYS_FILE"  ]] || { printf 'ask.sh: sys-file not readable: %s\n'  "$SYS_FILE"  >&2; exit 2; }
[[ -r "$USER_FILE" ]] || { printf 'ask.sh: user-file not readable: %s\n' "$USER_FILE" >&2; exit 2; }

# --system-prompt replaces the default CC system prompt entirely → no plugin /
# CLAUDE.md / MCP boot baggage. --tools "" disables every tool (this call is
# pure text in / text out). --no-session-persistence prevents the call from
# polluting the user's resume picker. --disable-slash-commands skips skill
# resolution. The result is a near-minimal cold LLM call over session auth.

# `</dev/null` is load-bearing: without it, `claude -p` waits 3s on stdin
# before proceeding even when the prompt is supplied as an argument.
exec claude -p \
  --no-session-persistence \
  --disable-slash-commands \
  --tools "" \
  --model "$MODEL" \
  --system-prompt "$(cat "$SYS_FILE")" \
  "$(cat "$USER_FILE")" </dev/null
