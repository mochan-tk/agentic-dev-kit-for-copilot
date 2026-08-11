---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-06/07)
retrieved: 2026-08-07
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Design-session decisions: pluggable context connectors

Summary of the architecture agreed in the design session. The source
conversation is ephemeral (session transport, not storage — AGENTS.md §1);
this file is the durable capture. As `method: ai-summary`, re-verify before
promoting any statement into an agreement — the intended verification is
human review of the PR that lands this file and ADR-0001.

## Problem

The scaffold's lifecycle hardcodes one way to acquire project context:
Phase 1 (collection) and Phase 2 (distillation) assume material is gathered
conversationally and distilled by hand. Real adopters arrive differently:
some already run spec-kit and have `specs/**` as their requirements source;
some use other spec tools; some have nothing yet. Meanwhile Phase 3–5
(plan → execute → verify) only care that certain inputs exist — they do not
care how those inputs were produced.

## Decision sketch (captured; decision itself lives in ADR-0001)

Make Phase 1–2 a **pluggable layer**. Any implementation that satisfies a
single **Context Contract** (see `context-contract.md`) is a valid provider
of Phase 1–2; Phase 3–5 remain unchanged and consume only Contract outputs.

## Connector model

A connector is a swappable implementation of Phase 1–2, defined as a
markdown procedure (plus optional MCP configuration where a tool needs it).
Every connector must define four operations:

| Operation | Meaning |
|---|---|
| `discover` | Detect whether this source applies to the repository (e.g. `specs/**` exists) and what it contains. |
| `retrieve` | Land source material into `.github/docs/context/` (or reference it in place when it already lives in-repo) with provenance. |
| `pin` | Fix the exact source revision the plan will be built against (e.g. a commit SHA for in-repo specs), recorded durably. |
| `verify` | Check the pinned source still matches reality (drift detection); on mismatch, escalate with `needs:replan`. |

Connector metadata: `name`, `access` (how the source is reached), `reach`
(what the source can see), `trust-default` (how much its content can be
trusted before re-verification), `status` (`core` | `community` |
`experimental`).

## Placement and activation

- Connector definitions live in `.github/connectors/`:
  `README.md` (Contract + contribution rules), `CONNECTOR-TEMPLATE.md`,
  `builtin.md`, `speckit.md`.
- Activation is per-project via a `SOURCES.md` registry (planned file under
  `.github/docs/context/`) listing enabled connectors and their pins.
  Written by the setup wizard or by an activation PR.
- A conformance script (`check-connectors.sh`, CI wall) validates every
  connector definition against the Contract (framework phase decides the
  exact assertions).

## Versioned scope

- **v1 (Epic #82)**: framework + two core connectors — `builtin`
  (draft-first elicitation via `/kickoff-context`; see
  `elicitation-ux-blueprint.md`) and `speckit` (adopt an existing spec-kit
  workspace) — plus the setup wizard and README surface updates.
- **v2 (separate Epic)**: `workiq` (M365) connector, `experimental`, using a
  planner-pins pattern (the planner pins retrieved artifacts because the
  source system is outside the repository).
- **Community candidates**: Kiro (`.kiro/specs/**` is structurally similar
  to spec-kit's layout). Documented only; contributed via the connector
  template. The template is published as OSS with the expectation that
  contributors add connectors.
- **v3 escape hatch (documented, not built)**: split connector definitions
  out of the scaffold into a registry if the set grows past what
  `.github/connectors/` comfortably holds.

## speckit connector: two-stage PR design

- **PR-A (activation)**: adds the pin to `SOURCES.md` and adds `specs/**`
  to CODEOWNERS. Merging it is the durable decision "adopt `specs/**` at
  this revision as the requirements source", with `verify` +
  sufficiency-test evidence in the PR body.
- **PR-B (ongoing)**: after activation, every spec change is naturally a PR
  because `specs/**` are in-repo files — no extra machinery. spec-kit's own
  `/clarify` records Q&A inside the spec, so provenance is free.
- **Drift detection**: Task issues cite the pin SHA at decomposition time;
  the planner's `verify` compares pin vs HEAD and escalates `needs:replan`
  on mismatch.

## Differentiator recorded

Kiro and spec-kit gate phase transitions with a chat approval ("yes" in a
conversation), which evaporates. This scaffold replaces that gate with a PR
review: approval is a ledger event (reviewer, timestamp, diff), traceable
later via `git blame` and the PR record.
