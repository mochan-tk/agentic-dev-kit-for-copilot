---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-06/07)
retrieved: 2026-08-07
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# The Context Contract

What any Phase 1–2 implementation must deliver so that Phase 3–5 can run
unchanged. Agreed in the design session; the framework phase promotes this
into the connector framework README (planned file under
`.github/connectors/`) as the normative text. As `method: ai-summary`,
re-verify via PR review before treating as agreement.

## The four conditions

A project satisfies the Context Contract when:

1. **Verifiable requirements with stable IDs.** Requirement-shaped
   statements exist, each individually checkable and carrying an identifier
   that survives edits (`REQ-###` in the builtin case; spec-kit's own
   requirement keys in the speckit case). "Verifiable" means a reviewer can
   decide pass/fail without interviewing the author.
2. **Immutable decisions.** Design choices that constrain future work are
   recorded append-only (ADRs or the source tool's equivalent), so a later
   session can distinguish "decided" from "assumed".
3. **Reachable from every execution surface.** All content is accessible
   from any surface a task may run on (`exec:cloud`, `exec:app`,
   `exec:cli`, `exec:ide`) — in practice: in the repository, or pinned into
   it. A source only one surface can reach fails the Contract.
4. **Stably referenceable from Task issues.** A Task issue can cite the
   material with a reference that will not silently change meaning — a
   path plus pin (SHA) for in-repo sources, an immutable ID otherwise.

## The sufficiency test

Contract satisfaction is judged by the **Epic-decomposition test**:

> The next Epic can be decomposed into Task issues, and every Task's
> acceptance criteria can be written in verifiable form, without going back
> to the humans for missing fundamentals.

This is deliberately behavioral rather than structural: it does not matter
how many files exist or how polished they are; it matters whether planning
can proceed. The test is cheap to run (attempt the decomposition; note
where it stalls) and its evidence belongs in the activation/agreements PR.

## Consequences noted in-session

- The Contract is the *only* interface between connectors and the rest of
  the scaffold; nothing in Phase 3–5 may depend on connector specifics.
- Conformance checking (`check-connectors.sh`) validates connector
  *definitions* (structure: four operations, metadata, Contract citation);
  the sufficiency test validates a *project's* actual context. Both are
  needed; they check different things.
- Today these conditions are implicit, scattered across the
  context-collection and context-distillation skills. Writing them down as
  a named Contract is itself part of the value of this Epic.
