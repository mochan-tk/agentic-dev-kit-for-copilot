---
source: https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/113
retrieved: 2026-08-18
method: ai-summary
collector: Copilot app worker session 6f6d8a1e-d72a-45b0-aaea-d88a5672e1fc
sensitivity: public
status: raw
---

# Session naming context

## Open questions

None were recorded in the supplied decision. The source material is translated
and condensed, so it must be re-verified before promotion to an agreement.

## Sources

- `2026-08-18-owner-decision.md` — summarizes the repository owner's
  2026-08-18 naming decision, its scope, preserved behavior, and migration
  boundary.

## Final requested direction

Use **Project session** for the top-level Copilot app session and name newly
created instances exactly `Project`. Preserve the hierarchy Project session →
Epic orchestrator session → Task supervisor session → PR worker session.
Treat the name as unrelated to a GitHub Projects board, retain existing
sessions named `Program`, and do not change behavior or historical records.
