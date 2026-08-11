# Retro Log

Ledger of system improvements produced by `.github/skills/retro/SKILL.md`.
One row per `retro:` PR — this trail is what lets future hygiene passes see
why a rule exists (a rule with no traceable origin cannot be safely removed).

| Date | Failure class | Fix (asset + change) | Evidence |
|---|---|---|---|
| 2026-08-08 | Supervisor archived before its workers, orphaning worker sessions (only a human can remove them; `archive_session` is creator-scoped) | `session-orchestration/SKILL.md`: leaf-first teardown order added to the app session-tree section | Occurrences: #117, #123 closeouts; fix in #127 |
