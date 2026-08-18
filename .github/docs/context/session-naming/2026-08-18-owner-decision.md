---
source: https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/113
retrieved: 2026-08-18
method: ai-summary
collector: Copilot app worker session 6f6d8a1e-d72a-45b0-aaea-d88a5672e1fc
sensitivity: public
status: raw
---

# Owner naming decision

The repository owner supplied a translated and condensed summary of a
2026-08-18 consultation, including an external ChatGPT Pro analysis originally
provided in Japanese. The requested direction is to call the top-level Copilot
app session the **Project session**.

The Project session supervises the complete Epic set for one repository-level
initiative. It starts each Epic orchestrator session when that phase becomes
actionable, watches progress across phases, and replans the outline when
reality diverges. The name does not refer to, rename, or change a GitHub
Projects board.

The four-layer hierarchy remains:

```text
Project session
 └─ Epic orchestrator session
    └─ Task supervisor session
       └─ PR worker session
```

This is a terminology migration only. Responsibilities, parent/child behavior,
session lifetime and teardown, tools, the issue graph, branch naming, labels,
CI, Task rituals, and GitHub Projects behavior remain unchanged. Existing live
or archived sessions named `Program` remain valid; newly created top-level
sessions are named exactly `Project`. Historical records are not rewritten.

Because this note is an AI summary of translated and condensed material rather
than the original consultation, re-verify it against the linked Task issue
before promoting it to a reviewed agreement.
