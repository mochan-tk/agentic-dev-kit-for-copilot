---
applyTo: ".github/docs/**"
---

# Documentation Rules (`.github/docs/`)

## Language and voice

- English only, for every file in this tree. Persistent artifacts must read
  identically to every model and every future session; mixed-language docs
  cause nuance drift.
- Write in the imperative for procedures and in plain declarative sentences
  for facts. State *why* a rule exists when it is not obvious.

## The two tiers are different

- `.github/docs/context/` is an **intake area**: raw, possibly redundant, never
  authoritative. Every file starts with the provenance header defined in
  `.github/skills/context-collection/SKILL.md`. Do not "clean up" raw material
  into conclusions here — that is distillation and it happens elsewhere.
  Exception: SOURCES.md, the machine-written connector activation registry
  (`.github/connectors/README.md`, "Activation"), carries no provenance header.
- `.github/docs/agreements/` is **reviewed truth**: requirements (`REQ-###`), ADRs
  (`ADR-####`), glossary, non-goals. Only knowledge that clears the promotion
  bar belongs here (`.github/skills/context-distillation/SKILL.md`, "When an
  agreement is warranted"); most task-sized knowledge lives and dies in the
  Task issue body that needs it. Files here change **only via pull request**
  with at least one human approval.

## Changing an agreement

- **Substantive changes** — a new, changed, or superseded `REQ`/ADR, glossary
  or non-goal entry — get their own agreements PR. Never make them as a side
  effect of implementation work; if implementation reveals an agreement is
  wrong, open a separate agreements PR and link the two.
- **Wording fixes** — typos, broken links, formatting, phrasing that changes
  no meaning — may ride an implementation PR as a **declared rider**: state
  the rider in the PR description, comment it on the Task issue, and obtain
  approval from a `.github/docs/agreements/` code owner before merge.
- **Litmus test.** If the edit could change whether an acceptance criterion
  passes or how a reader acts, it is not a wording fix — it is a substantive
  change and needs its own agreements PR.

## Traceability

- New or changed requirements get the next free `REQ-###` ID; never reuse IDs.
  Superseded requirements are marked `(superseded by REQ-###)`, not deleted.
- ADRs are numbered sequentially from `ADR-0001` and follow
  `.github/docs/agreements/adr/ADR-0000-template.md`. An ADR that reverses a previous
  decision must reference the ADR it supersedes.
- When a decision is made anywhere else (issue thread, PR review, chat), it is
  not an agreement until it lands in `.github/docs/agreements/` through a PR. Copy the
  conclusion, link the discussion.
