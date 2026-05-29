# deeper IMPROVEMENTS — aggregated across runs

This file is the global accumulator of investigator-subagent failures observed
during deeper A-phase fanout. Every time the A-driver (`answer.sh` →
`PROMPT.answer.md`) force-kills an investigator that did not finish before its
deadline, an entry is appended here with the classified reason.

Per-run copies live at `runs/deeper/<run-id>/improvements.md`. The global file
below is reviewed periodically to feed BANS.md updates and to inform future
investigator-prompt revisions.

Entry format:

```
## <run-id> · round <k> · <ts>
- angle `<angle>` · reason `<reason>` · last_tool `<tool>` · snippet: <≤200 chars>
```

Reason vocabulary (closed set):

- `context_limit`
- `tool_loop`
- `stuck_on_permission`
- `network_timeout`
- `ambiguous_task`
- `unknown`
