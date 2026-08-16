# Retro Log

Ledger of system improvements produced by `.github/skills/retro/SKILL.md`.
One row per `retro:` PR — this trail is what lets future hygiene passes see
why a rule exists (a rule with no traceable origin cannot be safely removed).

| Date | Failure class | Fix (asset + change) | Evidence |
|---|---|---|---|
| 2026-08-13 | Surfaces shipped and stayed broken because nothing had ever executed them — an agent tool grant that never matched its protocol, and a Windows command that never reached Git Bash. Neither regressed; both were wrong from the day they were written, and both were found by adopters rather than here | `ci.yml`: a `windows-launcher` job runs the documented Windows invocation on a Windows runner, distinguishing a launcher that raises from a repository that reports untuned. (#47's counterpart wall, `check-agent-tools.sh`, shipped with its own fix) | Occurrences: #47, #49; fix in #51 |
| 2026-08-08 | Supervisor archived before its workers, orphaning worker sessions (only a human can remove them; `archive_session` is creator-scoped) | `session-orchestration/SKILL.md`: leaf-first teardown order added to the app session-tree section | Occurrences: #117, #123 closeouts; fix in #127 |
| 2026-08-16 | Platform capability review drift | `.github/scripts/retro-hygiene.sh`: deterministic source-template-only capability baseline with official URL rendering, `unchanged`/`changed`/`unknown` handling, and preserved baseline values when upstream data fails. This extends the initial Rubber Duck/#68 seed with an engine-class official checkpoint ledger rather than a model summary. | Task #73 |
