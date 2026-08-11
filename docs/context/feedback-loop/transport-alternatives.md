---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-08)
retrieved: 2026-08-08
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Transport: gh CLI chosen; alternatives considered

## Chosen: `gh issue create --repo <upstream>`

- gh is already a hard prerequisite of the scaffold (README
  Prerequisites); every adopter has it authenticated.
- No new external endpoints: the only network destination is GitHub
  itself, which the scaffold's security posture already trusts
  ("no new external endpoints" review rule stays intact).
- No telemetry infrastructure to run, secure, or pay for; nothing to
  self-host.
- The report is authored by the adopter's own account, which is honest
  (they can edit/close it) and spam-resistant (GitHub's own abuse
  controls apply).
- Failure mode is graceful: if gh is unauthenticated, the helper can fall
  back to printing the prefilled body for manual filing.

## Considered and rejected

1. **Issue-form URL prefill** (`https://github.com/<up>/issues/new?template=…&…`)
   — official GitHub feature, zero code on the receiving end. Rejected as
   primary transport: query-string length limits truncate bodies, the
   adopter lands in a browser mid-terminal-session, and the preview shown
   in the terminal is not guaranteed to be what the form submits. Kept as
   a possible manual fallback when gh is unavailable.
2. **Third-party telemetry service** (Sentry-style SDK or a collector
   endpoint) — rejected outright: introduces a new external endpoint and
   a data-processor relationship, contradicts the consent-per-event
   posture, and violates the spirit of the repository's own review rule
   against new external endpoints.
3. **GitHub API via raw curl + token** — strictly worse than gh (token
   handling lands in scaffold code); rejected.

## Receiving end (upstream repository)

- A `feedback.yml` issue form so hand-filed reports have structure;
  helper-filed bodies render the same headings.
- **Labeling cannot happen at create time.** External reporters normally
  hold no triage permission on the upstream repo, so
  `gh issue create --label` fails for them, and an issue form's `labels:`
  key applies only to web-form submissions (external review caught this).
  Classification therefore uses a **fixed marker** the helper always
  emits — a title prefix (e.g. `[adopter-feedback]`) and/or an HTML
  comment marker in the body — and the upstream repo may run a small
  receiving-side Action that applies `from:adopter` to issues carrying
  the marker. The label is thus maintainer-side automation; the helper
  itself needs no permissions beyond issue creation.
- Reports are Task-issue *inputs*: triage may convert one into a
  `type:task` issue, but adopter reports themselves do not enter the
  execution plane.
