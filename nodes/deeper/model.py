#!/usr/bin/env python3
"""
deeper node v1 model — mechanical iteration-tree driver. No LLM.

One invocation = one ralph iteration.
- Reads/initializes tree.json in $RUN_DIR.
- Walks to the node at tree["cursor"] (a list-of-int path from root).
- Prompts the user via /dev/tty (falls back to env DEEPER_AUTO_ANSWER for testing).
- Mutates tree.json in place.
- Prints one summary line on stdout for the harness.

Output protocol (one line on stdout):
  round <N>: cursor=<path> answer="<a>" outcome=<advanced|bedrock|branch|stop>
If cursor=null after the round, the next judge detects "no open leaves" and ends the run.

Tree mutation rules:
  normal answer            → append child under cursor, cursor descends (deeper)
  BEDROCK:<category>       → close current, cursor pops to next open leaf (DFS-deepest)
  BRANCH:<sibling-claim>   → append sibling under parent, cursor jumps (parallel cause)
  STOP                     → emit "BLOCKED: user requested STOP", exit
"""

import json
import os
import sys
from pathlib import Path

BEDROCK_CATEGORIES = {
    "stated-value", "constraint", "prior-decision",
    "external-rule", "identity", "empirical",
}


def must_env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        sys.exit(f"model.py: missing env {name}")
    return v


def read_answer(prompt: str) -> str:
    # Preferred: file-backed answer (skill mode — avoids shell-quoting headaches)
    if af := os.environ.get("DEEPER_ANSWER_FILE"):
        return Path(af).read_text().rstrip("\n")
    # Secondary: env-var answer (autonomous tests, simple scripts)
    auto = os.environ.get("DEEPER_AUTO_ANSWER")
    if auto is not None:
        print(prompt, file=sys.stderr)
        print(f"(auto) {auto}", file=sys.stderr)
        return auto
    # Fallback: interactive tty (bash CLI mode)
    try:
        with open("/dev/tty", "r+") as tty:
            tty.write(prompt)
            tty.flush()
            return tty.readline().rstrip("\n")
    except OSError:
        sys.exit("model.py: no /dev/tty, DEEPER_ANSWER_FILE, or DEEPER_AUTO_ANSWER set")


def atomic_write_json(path: Path, data: dict) -> None:
    # tree.json is the run's single source of truth. A crash mid-write leaves
    # the run unresumable; write to a sibling tempfile and rename atomically.
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, path)


def walk(tree: dict, path: list[int]) -> dict:
    node = tree["root"]
    for i in path:
        node = node["children"][i]
    return node


def find_next_open_leaf(node: dict, path: list[int]) -> list[int] | None:
    """Deepest-first search for a node with bedrock=None and no children (or all children closed)."""
    if node.get("bedrock") is None and not node["children"]:
        return path
    for i, child in enumerate(node["children"]):
        result = find_next_open_leaf(child, path + [i])
        if result is not None:
            return result
    return None


def init_tree(seed_path: str) -> dict:
    seed = Path(seed_path).read_text().strip()
    # Use the seed body (skip first markdown header line if present) as the root claim.
    lines = [l for l in seed.splitlines() if l.strip() and not l.startswith("#")]
    root_claim = lines[0] if lines else seed
    return {
        "root": {
            "claim": root_claim,
            "tag": "from-user",
            "bedrock": None,
            "children": [],
        },
        "cursor": [],  # empty path = root
    }


def main() -> int:
    run_dir = Path(os.path.dirname(must_env("SEED_FILE")))
    tree_path = run_dir / "tree.json"
    round_num = int(os.environ.get("ROUND", "0"))

    if tree_path.exists():
        tree = json.loads(tree_path.read_text())
    else:
        tree = init_tree(must_env("SEED_FILE"))

    if tree["cursor"] is None:
        print(f"round {round_num}: no open leaves; nothing to do")
        return 0

    cursor_node = walk(tree, tree["cursor"])
    parent_claim = cursor_node["claim"]

    prompt = (
        f"\n--- deeper round {round_num} ---\n"
        f"Drilling: {parent_claim}\n"
        f"Why? (or:  BEDROCK:<cat>  |  BRANCH:<sibling>  |  STOP)\n"
        f"Categories: {', '.join(sorted(BEDROCK_CATEGORIES))}\n"
        f"> "
    )
    answer = read_answer(prompt).strip()

    outcome = "advanced"

    if answer == "STOP":
        atomic_write_json(tree_path, tree)
        print(f"round {round_num}: cursor={tree['cursor']} STOP")
        print("BLOCKED: user requested STOP")
        return 0

    if answer.startswith("BEDROCK:"):
        category = answer[len("BEDROCK:"):].strip()
        if category not in BEDROCK_CATEGORIES:
            print(f"round {round_num}: invalid bedrock category '{category}'", file=sys.stderr)
            print(f"round {round_num}: cursor={tree['cursor']} answer=\"{answer}\" outcome=rejected")
            return 0
        cursor_node["children"].append({
            "claim": f"(bedrock declared at: {parent_claim})",
            "tag": "from-user",
            "bedrock": category,
            "children": [],
        })
        next_cursor = find_next_open_leaf(tree["root"], [])
        tree["cursor"] = next_cursor
        outcome = "bedrock"

    elif answer.startswith("BRANCH:"):
        sibling_claim = answer[len("BRANCH:"):].strip()
        if not tree["cursor"]:
            print(f"round {round_num}: cannot BRANCH at root; treating as normal answer", file=sys.stderr)
            outcome = "rejected"
        else:
            parent_path = tree["cursor"][:-1]
            parent = walk(tree, parent_path)
            parent["children"].append({
                "claim": sibling_claim,
                "tag": "from-user",
                "bedrock": None,
                "children": [],
            })
            tree["cursor"] = parent_path + [len(parent["children"]) - 1]
            outcome = "branch"

    else:
        cursor_node["children"].append({
            "claim": answer,
            "tag": "from-user",
            "bedrock": None,
            "children": [],
        })
        tree["cursor"] = tree["cursor"] + [len(cursor_node["children"]) - 1]
        outcome = "advanced"

    atomic_write_json(tree_path, tree)

    safe_answer = answer.replace('"', "'")[:80]
    print(f"round {round_num}: cursor={tree['cursor']} answer=\"{safe_answer}\" outcome={outcome}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
