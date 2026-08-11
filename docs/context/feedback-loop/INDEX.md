# Context: feedback-loop

Raw material grounding ADR-0002 (consent-gated adopter feedback) and its
implementing Epic.

## Open questions

- Deduplication: should the helper search existing upstream issues for the
  same signature (script + step + version) and offer a "me too" comment
  instead of a new issue? (v1 candidate, may be deferred)
- Version marker schema and location: structured changelog line vs. a
  dedicated marker file, and re-install/upgrade semantics — the Epic
  decides (see `version-identity.md`; the prose `Adopted:` line already
  exists).
- Receiving-side labeling Action: ship it with the scaffold or leave the
  title-prefix marker as the only classification in v1?
- Should "Use this template" copies get the offer wired too? They carry
  no upstream identity (single squashed initial commit, unrelated
  history — GitHub template-repo behavior), so they'd need the marker
  backfilled by onboarding first. (installer path is the primary target)
- Rate limiting: is per-run consent enough, or does the helper need a
  "never ask again" opt-out knob (env var or stamped config)?

## Conflicts

- None recorded yet.

## Files

- `design-session-decisions.md` — what was decided and why: consent-gated
  offer, not-collect allowlist, interactive-only, trap scope.
- `privacy-posture.md` — the allowlist (collected vs. never-collected),
  disclosure requirements, preview-before-send.
- `transport-alternatives.md` — gh CLI chosen; URL-prefill and third-party
  telemetry considered and rejected; receiving-end shape.
- `version-identity.md` — why reports need a scaffold version, the current
  gap, candidate stamping mechanisms.
