# Context: connector-design

Raw material grounding ADR-0001 (pluggable context connectors) and Epic #82.

## Open questions

- Should connector definitions eventually move out of the scaffold into a
  registry (v3 split)? Deferred; documented as an escape hatch only.
- Exact conformance checks for `check-connectors.sh` (framework phase will
  decide; the Contract file lists the candidate assertions).
- Whether the Kiro `.kiro/specs/**` layout is close enough to spec-kit's to
  share adapter code (community connector candidate, unscoped).

## Conflicts

- None recorded. Prior-art findings agree with the chosen draft-first
  elicitation design; the earlier interview-first sketch was discarded in the
  design session (see `elicitation-ux-blueprint.md`).

## Files

- `design-session-decisions.md` — architecture agreed in the design session:
  Context Contract, connector model, activation via SOURCES.md, v1/v2/v3 scope.
- `context-contract.md` — the four contract conditions and the sufficiency
  test (Epic-decomposition test) every connector must satisfy.
- `prior-art-kiro-speckit-bmad.md` — web research on Kiro, spec-kit, BMAD,
  and the SDD tools comparison; what this scaffold borrows from each.
- `elicitation-ux-blueprint.md` — draft-first `/kickoff-context` UX for the
  builtin connector, including the PR-review approval gate.
- `setup-wizard-and-support-matrix.md` — install-time wizard flow, preflight
  checks, Free-plan private-repo hard stop, and the support matrix.
