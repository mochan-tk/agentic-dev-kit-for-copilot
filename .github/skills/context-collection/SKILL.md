---
name: context-collection
description: Land raw project information — meeting notes, existing specs, domain research, external tool exports, interview answers — into .github/docs/context/ with provenance, so later phases and stateless agents can use it. Use this at project kickoff, whenever new source material appears (a document, a decision made in chat, findings from web/MCP research), and before any distillation work that lacks raw inputs.
---

# Context Collection

Collection has one job: get information out of volatile places (chats, heads,
external tools) and into the repository, faithfully. Completeness beats tidiness
here — the distillation phase (see `context-distillation`) will filter. What
collection must never do is silently interpret: a paraphrase that changes
meaning is worse than a messy verbatim note, because downstream agents will
trust it.

## Landing zone

- Everything lands under `.github/docs/context/<topic>/`, one topic per directory
  (e.g., `.github/docs/context/device-pairing/`, `.github/docs/context/line-integration/`).
- Each topic directory keeps an `INDEX.md`: one line per file — what it is and
  why it matters. Agents read indexes first; keep them current.
- Large binaries and originals stay in their system of record; store a link
  and an extracted-text or summary file here instead.

## Provenance header (mandatory)

Every collected file starts with:

```markdown
---
source: <URL, meeting name, person, or tool>
retrieved: <YYYY-MM-DD>
method: <verbatim | export | interview | ai-summary | web-research>
collector: <human name or agent/session identifier>
sensitivity: <public | internal | confidential>
status: raw
---
```

The `method` field is what lets a future reader calibrate trust:
`verbatim`/`export` can be quoted as fact; `ai-summary` and `web-research`
must be re-verified before becoming an agreement.

## Collection rules

1. **Raw over summarized.** Prefer the original wording; if you must condense,
   keep the original alongside or linked. Mark interpretation as such.
2. **Chat is a source too.** When a real decision or requirement surfaces in a
   conversation, capture it here (method: `verbatim`, source: the
   conversation) — otherwise it evaporates when the session ends.
3. **External systems via MCP.** Pull from external tools (docs, tickets,
   designs) through the MCP servers configured for this repo
   (`.vscode/mcp.json` for interactive surfaces; repository settings for the
   cloud agent). Record which server/tool produced the data in `source`.
4. **No secrets, ever.** Redact tokens, credentials, and personal data before
   a file lands. If sensitivity is `confidential`, confirm with a human that
   the repository is an acceptable home before committing.
5. **Contradictions are content.** When two sources disagree, collect both and
   note the conflict in `INDEX.md` — resolving it is a distillation/agreement
   decision, not a collection edit.

## Definition of done for a collection pass

- New material sits under the right topic with a complete provenance header.
- `INDEX.md` updated.
- Conflicts and open questions listed at the top of `INDEX.md`.
- Nothing in the pass exists only in a chat window.
