# ADR-0001: Pluggable context connectors for Phase 1–2

- **Status:** accepted
- **Date:** 2026-08-07
- **Supersedes:** none

## Context

The scaffold's lifecycle table presents Phase 1 (context collection) and
Phase 2 (distillation) as fixed, conversation-driven procedures. Adopters
arrive in different states: some already maintain a spec source (spec-kit's
`specs/**`, Kiro's `.kiro/specs/**`, documents in external systems such as
M365), others have nothing written down. Phase 3–5 (plan → execute →
verify) do not depend on *how* context was produced — only on properties of
the result: verifiable requirements with stable IDs, immutable decisions,
reachability from every execution surface, and stable referenceability from
Task issues (the Context Contract, with sufficiency judged by the
Epic-decomposition test). Prior-art research (Kiro, spec-kit, BMAD)
confirmed strong existing front-ends for spec authoring, none of which
provide this scaffold's governed execution lifecycle — integration, not
competition, is the useful posture. Publishing the scaffold as OSS adds a
constraint: third parties must be able to contribute new source
integrations without touching the core.

Sources: `docs/context/connector-design/` (design-session
decisions, Context Contract, prior art, elicitation blueprint, wizard and
support matrix).

## Decision

Phase 1–2 become a pluggable layer: any *connector* — a markdown-defined
procedure implementing `discover` / `retrieve` / `pin` / `verify` with
declared metadata — is a valid provider of Phase 1–2 so long as its output
satisfies the Context Contract, which becomes the sole interface consumed
by Phase 3–5. The scaffold ships `builtin` (draft-first elicitation gated
by PR review) and `speckit` (adopt an existing spec-kit workspace via an
activation PR) as core connectors, activated per-project through a
`SOURCES.md` registry (planned file under `.github/docs/context/`).

## Consequences

- Easier: adopting the scaffold on projects with existing spec sources
  (no forced re-collection); OSS contribution of new connectors against a
  template and conformance wall; keeping Phase 3–5 stable while the intake
  side evolves.
- Harder: the Context Contract must be kept precise and normative — it is
  now load-bearing; connector definitions need CI conformance checking
  (`check-connectors.sh`) to stop drift; documentation must explain a
  two-sided model (connector authors vs. adopters).
- Must now be true: nothing in Phase 3–5 may reference a specific
  connector's internals; every enabled source is pinned and drift is
  detected at decomposition time (`verify`, escalating `needs:replan`);
  approval of context/agreements happens in PR reviews, never chat.
- Follow-up candidates (Epic #82 phases): connector framework files under
  `.github/connectors/` + conformance wall; setup wizard with preflight and
  the Free-plan private-repo hard stop; builtin `/kickoff-context` prompt;
  README lifecycle/support-matrix updates. Later Epics: `workiq`
  (experimental, planner-pins), community Kiro connector.

## References

- Epic: mochan-tk/ttt1-copilot#82; Task: mochan-tk/ttt1-copilot#83
- Context: `docs/context/connector-design/INDEX.md` and files
  listed there
- Prior art: github/spec-kit; kiro.dev specs workflow; BMAD-METHOD;
  Martin Fowler, "Exploring Generative AI: SDD tools"
