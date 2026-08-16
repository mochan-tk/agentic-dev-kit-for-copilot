---
source: Task #72 collection pass over the HOTL review and originating spike artifacts
retrieved: 2026-08-16
method: ai-summary
collector: Task #72 worker session
sensitivity: public
status: raw
---

# HOTL review context

## Conflicts and open questions

- The review asks for runtime controls such as authenticated events, immutable
  roles, heartbeats, budgets, pause/resume, and a supervision console. This kit
  is plain repository files, and all sessions use one GitHub identity, so it
  cannot implement or verify those controls. Issue
  [#6](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6#issuecomment-5305170668)
  records the accepted limitation and the hardening trigger.
- Only 11 of 36 sampled Task issues had a File ownership section parseable as
  code-span bullets by the first prototype. The declared grammar must therefore
  be enforced for newly dispatchable Tasks, while legacy or malformed Tasks
  fail closed as `UNCHECKABLE`.
- `SCAFFOLD-CHANGELOG.md` appeared in 9 of those 11 parseable Tasks. That is a
  real shared-writer bottleneck, not a detector false positive; whether a future
  changelog-fragment design should remove it remains a separate decision.
- Merge queue is not an inactive control for this personal repository; it is
  not applicable. An eligible organization repository would also need its CI
  workflow to handle the `merge_group` event.
- The spike created and deleted disabled rulesets against a nonexistent branch.
  These were reversible mutations used because no validation-only ruleset API
  exists. Active team enforcement was not enabled.
- Team ruleset support for named required reviewers was not tested and is not
  part of the proposed profile. Human review must decide whether code-owner
  review is sufficient for the first team profile.

## Collected files

- [`review.md`](review.md) preserves the owner-supplied external HOTL review
  verbatim after its provenance header.
- [`feasibility.md`](feasibility.md) records the originating technical spikes,
  observed results, official platform constraints, corrected design
  conclusions, and verified versus unverified boundaries.

The corrected standalone ADR draft and executable prototypes remain the source
artifacts for this collection pass. `feasibility.md` identifies each artifact
and records what was observed without promoting the prototypes into supported
repository tooling.
