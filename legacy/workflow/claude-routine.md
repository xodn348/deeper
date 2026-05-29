# Claude routine

Name: deeper
Project: /Users/jnnj92/code/deeper
Status: pending_start

Pegasus uses one Claude routine per project.
The routine name must be the project name.
When the project is done or stopped, Pegasus deletes this routine record only after exact absence is verified.
Pegasus only reports `registered` after the local Claude CLI verifies the live routine.

Not verified yet. Pegasus attempted safe discovery/creation and will only report `registered` after exact verification.
Create attempt: No verified noninteractive Claude routine create command is exposed by `claude agents --help`; kept pending_start.

Routine prompt:

```text
You are the Claude routine for Pegasus project `deeper`.

Project root: /Users/jnnj92/code/deeper

Read the GitHub repo files as the source of truth before doing work:
- spec/current.md
- spec/updates.md
- workflow/status.md
- workflow/questions.md
- spec/tasks/*.md
- workflow/agent-requests/*.md

Do not rely on chat memory over repo files. Report files changed, evidence, and open questions.
```
