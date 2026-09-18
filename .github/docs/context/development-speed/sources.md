---
source: https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/119
retrieved: 2026-09-15
method: ai-summary
collector: Task-120-worker
sensitivity: public
status: raw
---

# Source provenance

Originals remain in the owner's attachment store referenced by
[Epic #119](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/119).
They were not reacquired, translated, or rehashed by this worker.

| Original | SHA-256 recorded in the Epic | Original method |
|---|---|---|
| `copilot-development-speed-audit-2026-09-15.md` | `a55b14a51194a9eb7438cbec38cdb6feeccc73436768e868b3dfb19fb629f7fc` | ai-summary |
| `copilot-frontier-offline-probes.zip` | `e00d229b146ec9fe815ab143101d7d005580c3366a32d9bbe184664a4bd4e46f` | export |
| `copilot-pr-review-122-123-2026-09-15.md` | `08885df7900e4c2722d943d54dfa75788dd52265a5cc6f418ddd4f0686b049a1` | ai-summary |
| `copilot-pr123-cli-schema-reproduction.zip` | `1642d378462fa1f5a0b0ed78e939f1f17ce6968645f070162ecf726aa3f5849a` | export |

The two rework inputs are recorded by the
[Epic correction](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/119#issuecomment-5673230062),
retrieved 2026-09-15, status raw, with originals in the owner's attachment
store. The parent read/hashed the report and listed the archive but did not
execute its probes. The report describes Linux offline probes, not live
GitHub, macOS, or app execution. The worker did not acquire/run the archive.

The worker directly read the public
[v2.98.0 Issue.ExportData exporter](https://github.com/cli/cli/blob/v2.98.0/api/export_pr.go#L84-L98)
on 2026-09-15. This ai-summary is raw: nodes export `id`, `number`, `title`,
`url`, `state`; the connection exports `nodes`, `totalCount`. `repository`
exists in the internal type but is absent from this export. New offline
fixtures derive from this public source, not the supplied executable archive.

This intake summarizes public ledger facts, not the Japanese originals.
External feedback is not authorization; the
[owner decision](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/119#issuecomment-5668795167)
and normal Task Plan approval supply the first-wave authority.
