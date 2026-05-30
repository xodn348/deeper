#!/usr/bin/env bash
# make-demo-gif.sh — turn a screen recording of the live `/workflows` drill
# into a README-ready, autoplaying, optimized GIF.
#
# Usage:
#   scripts/make-demo-gif.sh <input.mov|input.mp4> [output.gif] [fps] [width]
#
# Defaults: output=docs/assets/deeper-demo.gif, fps=12, width=1000
#
# How to capture (macOS): Cmd+Shift+5 → record just the window running
# `/workflows` mid fan-out. Bump the terminal font, keep the window narrow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IN="${1:-}"
OUT="${2:-$ROOT/docs/assets/deeper-demo.gif}"
FPS="${3:-12}"
WIDTH="${4:-1000}"

if [[ -z "$IN" ]]; then
  echo "usage: $0 <input.mov|input.mp4> [output.gif] [fps] [width]" >&2
  exit 2
fi
if [[ ! -f "$IN" ]]; then
  echo "error: input not found: $IN" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found — install with: brew install ffmpeg" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
PALETTE="$(mktemp -t deeper-palette).png"
trap 'rm -f "$PALETTE"' EXIT

# 2-pass palette: pass 1 builds an optimal 256-color palette from the clip,
# pass 2 renders the GIF against it — the clean way to keep a colorful TUI sharp.
FILTERS="fps=${FPS},scale=${WIDTH}:-1:flags=lanczos"

echo "→ pass 1/2: building palette ($FILTERS)"
ffmpeg -v warning -y -i "$IN" -vf "${FILTERS},palettegen=stats_mode=diff" -update 1 -frames:v 1 "$PALETTE"

echo "→ pass 2/2: rendering GIF"
ffmpeg -v warning -y -i "$IN" -i "$PALETTE" \
  -lavfi "${FILTERS}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  "$OUT"

# Optional extra squeeze if gifsicle is installed.
if command -v gifsicle >/dev/null 2>&1; then
  echo "→ optimizing with gifsicle"
  gifsicle -O3 --colors 256 --batch "$OUT"
else
  echo "  (gifsicle not found — skip extra optimization; brew install gifsicle for smaller files)"
fi

SIZE="$(du -h "$OUT" | cut -f1)"
echo "✓ wrote $OUT ($SIZE)"
echo "  if it's >8MB, re-run with a lower width, e.g.: $0 \"$IN\" \"$OUT\" 12 800"
