# ADR-0002: Consent-gated adopter feedback over gh CLI

- **Status:** accepted
- **Date:** 2026-08-08
- **Supersedes:** none

## Context

The scaffold ships as OSS and executes inside adopters' repositories;
maintainers learn about failures only when adopters file issues by hand,
so the improvement loop starves. The maintainer wants failure reports
offered at the moment of error, derived from the failure itself — under a
hard constraint: no sensitive adopter data may ever be acquired. A
telemetry-style always-on collector would violate that constraint and the
repository's own review rule against new external endpoints. gh CLI is
already a hard prerequisite for every adopter. The installer already
records adoption provenance (upstream slug + full commit SHA, prose line
in the changelog), but no stable machine-readable schema exists for a
helper to consume; external reporters hold no label permissions on the
upstream repository, so classification cannot rely on labels applied at
create time.

Sources: `docs/context/feedback-loop/` (design-session decisions,
privacy posture, transport alternatives, version identity).

## Decision

When a scaffold-owned interactive script fails (installer and `setup-*`
scripts; CI guards excluded), it may *offer* — on interactive terminals
only, never in CI or piped contexts — to file an upstream issue via the
adopter's own `gh issue create`. The payload is assembled exclusively
from a fixed allowlist of structured fields (script name, failing step,
exit code, OS/arch, bash/gh/jq versions, scaffold version), with
hardened sourcing: script names come from a fixed enum of scaffold-owned
basenames (never raw `$0`), step labels are scaffold-authored constants
or bare line numbers (never `$BASH_COMMAND`), every field is validated
against an expected character class and length cap, and fields failing
validation are omitted (`unknown`) rather than passed through. Free-form
data such as logs, stderr, paths, repository identity, or environment
values is never collected, so nothing needs redaction. The exact issue
body is previewed in full, with an explicit disclosure that it becomes a
public issue authored by the adopter's account, and the default answer
is no. The version field comes from the installer's existing adoption
provenance, promoted to a machine-readable marker (schema and location
decided by the implementing Epic); the same marker carries the upstream
slug the helper files against. Helper-filed reports carry a fixed marker
(title prefix and/or body comment) instead of labels — external
reporters cannot apply labels — and the upstream repository classifies
them (`from:adopter`) via its own receiving-side automation; the
receiving end is a `feedback.yml` issue form, and reports are triage
inputs, not execution-plane work orders.

## Consequences

- Easier: maintainers see real-world failures with reproducible version
  context; adopters report with one keystroke; privacy review is a table
  lookup (allowlist) instead of a sanitizer audit; no telemetry
  infrastructure exists to operate or secure.
- Harder: every new field proposed for the payload is an ADR-level
  privacy decision, not a convenience patch; interactive scripts carry
  offer-wiring code that must never fire non-interactively; the
  machine-readable version marker becomes scaffold-owned surface that
  installs, upgrades, and self-checks must keep consistent.
- Must now be true: transmission is impossible without an explicit yes on
  a previewed body; the allowlist and field-hardening rules in
  `docs/context/feedback-loop/privacy-posture.md` are the outer
  bound of what any implementation may send; CI guard failures never
  trigger the offer; helper-filed reports never require label permissions.
- Follow-up (implementing Epic): machine-readable version-marker schema
  and re-install semantics, helper script and prompt wording,
  `feedback.yml` form and receiving-side labeling automation,
  dedup/rate-limit posture, README documentation.

## References

- `docs/context/feedback-loop/INDEX.md` (open questions live here)
- ADR-0001 (pluggable context connectors) — precedent for the
  context-then-ADR-then-Epic shape
- `.github/instructions/docs.instructions.md` — agreements change control
