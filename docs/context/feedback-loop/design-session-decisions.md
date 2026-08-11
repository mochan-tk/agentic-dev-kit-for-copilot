---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-08)
retrieved: 2026-08-08
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Design-session decisions: adopter feedback loop

Summary of the mechanism agreed in the design session. The source
conversation is ephemeral (session transport, not storage — AGENTS.md §1);
this file is the durable capture. As `method: ai-summary`, re-verify before
promoting any statement into an agreement — the intended verification is
human review of the PR that lands this file and ADR-0002.

## Problem

The scaffold ships as OSS and runs inside adopters' repositories. When an
adopter hits an error in a scaffold script, the maintainers never learn
about it unless the adopter files an issue by hand — which almost nobody
does. The improvement loop starves. The maintainer's ask: when a scaffold
script fails, offer the adopter a one-keystroke path to report it upstream,
with the report content derived from the failure — but without ever
capturing sensitive adopter data.

## Decisions

1. **Consent-gated offer, not telemetry.** Nothing is ever transmitted by
   default. On failure, the adopter is *asked* whether to report; the
   default answer is no; silence or a non-interactive environment means no.
   Every invocation asks again — there is no "always send" state in v1.
2. **Offer only on interactive terminals.** The prompt appears only when
   stdin/stderr are a TTY and no CI environment marker is present. CI runs,
   scripts piped from curl without a terminal, and automation never see a
   prompt and never transmit anything.
3. **Not-collect over sanitize.** The report payload is assembled from a
   fixed allowlist of structured fields (see `privacy-posture.md`).
   Free-form data — logs, stderr, paths, repository names — is never read
   into the payload, so there is nothing to redact and no sanitizer to get
   wrong.
4. **Full-body preview before send.** The adopter sees the exact issue
   title and body, plus a disclosure line (public repository, authored by
   their GitHub account), before confirming.
5. **Trap scope: interactive setup surfaces only.** The offer wires into
   the installer (`scaffold-init.sh`) and the interactive `setup-*`
   scripts. CI guard scripts (`check-*.sh`) are excluded: their failures
   normally mean the guard is doing its job on adopter-side content, not
   that the scaffold is broken, and they run non-interactively anyway.
6. **Transport is the gh CLI** the scaffold already requires; see
   `transport-alternatives.md`.
7. **Reports need a scaffold version.** Reproducibility requires knowing
   which scaffold commit the adopter runs. The installer already records
   prose provenance (upstream slug + full commit SHA in the changelog);
   the gap is a stable machine-readable schema — see
   `version-identity.md`.

## Non-decisions (left to the implementing Epic)

- Helper script name, exact prompt wording, and issue-title signature
  format.
- Deduplication and rate-limiting behavior (open questions in INDEX.md).
- Whether any REQ-### agreements should be extracted in addition to the
  ADR.
