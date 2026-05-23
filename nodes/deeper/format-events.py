#!/usr/bin/env python3
"""Tail formatter for deeper events.jsonl.

Reads NDJSON from stdin (line-buffered), emits ONE human-readable line per event.
Designed to be piped from `tail -F -n 0 events.jsonl` and consumed by Claude
Code's Monitor tool — each stdout line becomes one notification surfacing to
the launcher's next turn.

Format (one line per event):
  [R{n} Q] <question first ~140 chars>
  [R{n} A] <answer first ~140 chars>
  [R{n} ✓] depth=D done=B score=S [viol=...]
  [R{n} ⚠] STALL: <reason>
  ─── deeper {status} ───        (run_finished sentinel)
"""
import json
import sys


def shorten(s: str, n: int = 140) -> str:
    s = (s or "").replace("\n", " ").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def emit(line: str) -> None:
    print(line, flush=True)


for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        e = json.loads(raw)
    except json.JSONDecodeError:
        continue
    t = e.get("type", "")
    r = e.get("round", "?")
    if t == "question_emitted":
        emit(f"[R{r} Q] {shorten(e.get('question', ''))}")
    elif t == "answer_emitted":
        emit(f"[R{r} A] {shorten(e.get('answer', ''))}")
    elif t == "judge_result":
        d = e.get("detail", {}) or {}
        v = e.get("violations", []) or []
        vs = f" viol={','.join(v)}" if v else ""
        emit(
            f"[R{r} ✓] depth={d.get('max_depth', '?')} "
            f"done={d.get('done', '?')} score={e.get('score', '?')}{vs}"
        )
    elif t == "stall":
        emit(f"[R{r} ⚠] STALL: {e.get('reason', 'unknown')}")
    elif t == "run_finished":
        emit(f"─── deeper {e.get('status', '?')} (rounds={e.get('rounds', '?')} score={e.get('score', '?')}) ───")
