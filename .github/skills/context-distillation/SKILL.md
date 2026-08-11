---
name: context-distillation
description: Turn raw material in .github/docs/context/ into reviewed agreements (requirements with REQ-### IDs, ADRs, glossary, non-goals) and place each piece of knowledge in the right context tier — always-on instructions, path-scoped instructions, or on-demand skills/docs. Most knowledge never becomes an agreement; the promotion bar inside decides what does. Use this after collection passes, before planning an Epic, when agents keep missing the same context, or when instruction files grow bloated.
---

# Context Distillation

Distillation answers two questions for every piece of collected knowledge:
**is it true and agreed?** and **when should an agent see it?** The first
produces `.github/docs/agreements/`; the second decides its tier. Skipping the second
question is the classic failure mode — stuffing everything into always-on
instructions degrades every request a little until agents get worse, not
better.

## Outputs

| Artifact | File | Rules |
|---|---|---|
| Requirements | `.github/docs/agreements/requirements.md` | one `REQ-###` per verifiable statement; IDs never reused |
| Non-goals | `.github/docs/agreements/non-goals.md` | explicit "we will not" list — the cheapest scope-creep guard |
| Decisions | `.github/docs/agreements/adr/ADR-####-<slug>.md` | one decision per ADR, template `ADR-0000-template.md` |
| Vocabulary | `.github/docs/agreements/glossary.md` | project-specific terms; agents misname what humans leave undefined |

## When an agreement is warranted

Most knowledge never becomes an agreement. Promote a piece of knowledge into
`.github/docs/agreements/` only when it clears the bar below; everything under the
bar lives and dies in the Task issue body that needs it. Agreements are
written just-in-time, like Task decomposition — not speculatively.

| Artifact | Warranted only when |
|---|---|
| `REQ-###` | The statement is verifiable **and** constrains more than one task |
| ADR | Reversing the decision later would be expensive (architecture, process, security posture) |
| Glossary entry | The term has actually been misread across sessions or tools |
| Non-goal | Scope creep has appeared, or is predictably tempting |

A missing agreement is not a blocker: agents proceed on the Task issue body
and stop only for **contradictions** (Ambiguity rule, `AGENTS.md` §6).

## Procedure

1. **Scope.** Pick one topic directory in `.github/docs/context/`; read its `INDEX.md`
   and flagged conflicts first.
2. **Extract candidates.** Draft requirement statements, decisions, terms,
   and non-goals. Each must trace back to a source file (link it) — a
   candidate with no source is an invention and needs human confirmation.
3. **Resolve conflicts explicitly.** Where sources disagree, present the
   options; a human picks. Record the pick as an ADR if it is architectural,
   or directly as the surviving `REQ` otherwise.
4. **Write the diff, open a PR.** Agreements change only via PR with human
   approval (`docs.instructions.md`). The PR description lists each new/changed
   `REQ-###`/ADR with its source link. **Merge = agreement**; the review
   thread is the negotiation record.
5. **Tier the knowledge** (see below) and, when a tier assignment adds or
   changes instruction/skill files, include those edits in the same PR so the
   agreement and its delivery mechanism land together.

## Tiering: when should an agent see it?

| Tier | Test | Destination | Budget |
|---|---|---|---|
| Always-on | Needed on *most* tasks, stable, compressible to a few lines | `AGENTS.md`, `.github/copilot-instructions.md` | keep each file lean — target well under ~150 lines; adding usually means removing |
| Scoped | Needed only when touching certain paths | `.github/instructions/<area>.instructions.md` with `applyTo` | one concern per file |
| On-demand | Large, procedural, or rarely needed | a skill under `.github/skills/` or a doc under `.github/docs/agreements/` referenced from issues | no practical size limit; discoverability via skill descriptions and issue links |

Tie-breakers: if agents *repeatedly* miss it, promote one tier up; if an
always-on line hasn't mattered in weeks of PRs, demote it. Task-specific
context never goes into instructions at all — it belongs in the Task issue's
"Context & references" section.

## Quality bar

- Every `REQ` is testable — a verification command or observable behavior can
  prove it. "The system should be fast" is not a requirement until it has a
  number.
- Agreements are short declarative sentences; rationale lives in the linked
  ADR or source, not inline.
- After merging, mark distilled source files' `status:` as `distilled` in
  their provenance headers so future passes skip them.
