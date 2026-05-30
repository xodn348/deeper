# docs/assets

README media for deeper.

## `deeper-demo.gif` — the hero (live `/workflows` drill)

The README hero is an autoplaying GIF of the drill running as a Claude Code
dynamic workflow: cold subagents fan out in parallel each round, the judge keeps
the deepest answer, and the cursor descends toward bedrock — streaming live under
`/workflows`. A still screenshot can't show the fan-out rhythm; the GIF can, and
GitHub autoplays it inline with no click.

### How to (re)generate

1. Run a drill: `/deeper <some claim>` inside Claude Code.
2. Open `/workflows` while it's mid fan-out.
3. Screen-record just that window (macOS: `Cmd+Shift+5`). Bump the terminal
   font, keep the window narrow, capture ~10–25s of the fan-out → judge → descend
   loop. Save as `deeper-demo.mov`.
4. Convert to an optimized, autoplaying GIF:

   ```bash
   scripts/make-demo-gif.sh ~/Desktop/deeper-demo.mov
   # → docs/assets/deeper-demo.gif
   ```

Keep it under ~8MB so it loads fast on the README. If it's larger, re-run the
script with a smaller width (last arg).

## `deeper-tree.png` — optional annotated still

A single frozen frame of the tree with arrows/labels (cursor, ancestor chain,
the candidate the judge picked, a closed bedrock leaf) for the "anatomy"
explanation in the Mechanism section. The hero GIF gives the feel; this still
explains the structure.
