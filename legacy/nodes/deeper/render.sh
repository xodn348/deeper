#!/usr/bin/env bash
# render.sh — render tree.json as a human-readable markdown tree.
# Usage: render.sh <run-dir>   (or pipe: cat tree.json | render.sh -)

set -euo pipefail

if [ "${1:-}" = "-" ]; then
  INPUT="/dev/stdin"
else
  RUN_DIR="${1:?run-dir or '-' required}"
  INPUT="$RUN_DIR/tree.json"
fi

python3 - "$INPUT" <<'PYEOF'
import json, sys
tree = json.load(open(sys.argv[1]))

print("# Depth tree")
print()
print("## Bedrock")
print()
# Pull bedrock summary from closed leaves
closed = []
def collect(node, depth):
    if not node["children"] and node.get("bedrock"):
        closed.append((depth, node["bedrock"], node["claim"]))
    for c in node["children"]:
        collect(c, depth + 1)
collect(tree["root"], 0)
if closed:
    for d, cat, claim in closed:
        print(f"- [{cat}] (depth {d}) {claim}")
else:
    print("(none yet)")

print()
print("## Tree")
print()
cursor = tuple(tree.get("cursor") or [-1])

def render(node, depth, path):
    indent = "  " * depth
    tag = node.get("tag", "?")
    bedrock = node.get("bedrock")
    cursor_mark = "  <-- CURSOR" if tuple(path) == cursor else ""
    bedrock_mark = f"  [BEDROCK:{bedrock}]" if bedrock else ""
    print(f"{indent}- [{tag}]{bedrock_mark} {node['claim']}{cursor_mark}")
    for i, c in enumerate(node["children"]):
        render(c, depth + 1, path + [i])

render(tree["root"], 0, [])
PYEOF
