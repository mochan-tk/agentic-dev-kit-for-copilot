# Scaffold development records

This directory holds part of **the scaffold repository's own** development
history. Kit records also live at their existing source paths under
`.github/docs/`; neither history tree is installed into adopters:

- `context/` — raw intake about scaffold features (connector design,
  feedback loop), with provenance headers.
- `agreements/adr/` — ADRs governing the scaffold's own behavior
  (`ADR-0001` pluggable context connectors, `ADR-0002` consent-gated
  adopter feedback, `ADR-0003` two-tier task execution).
- Kit `.github/docs/context/` holds later context collections;
  [ADR-0004](../.github/docs/agreements/adr/ADR-0004-hotl-governance-sensors.md)
  and the populated kit retro-log remain under kit `.github/docs/agreements/`.
  ADR numbering is unchanged; location does not restart it.

## Distribution boundary

The installer (`.github/scripts/scaffold-init.sh`) distributes documentation
only through `.github/scripts/scaffold-docs.manifest`: two tier READMEs,
the ADR-0000 template, empty requirements/glossary/non-goals/retro ledgers,
and the adopter-feedback mechanism page. Dedicated bootstrap payloads are
separate from mutable kit agreements. Root `docs/` history and kit
`.github/docs/` history both stay kit-side, regardless of location; no
record is moved or renumbered. An adopter's agreements are *their* reviewed
truth and their ADR numbering starts at `ADR-0001`. Root `docs/` remains
application-owned, not a universal required destination.

"Use this template" copies do include this directory (GitHub copies the
whole tree — same trade-off as `.devcontainer/`); inspect inherited records
and retain project modifications before any manual cleanup.

## Governance

These records carry the same authority as they did under
`.github/docs/agreements/`: they are the scaffold's reviewed truth, and
**every change still lands only via a pull request reviewed by the
maintainer** — the human gate `.github/instructions/docs.instructions.md`
prescribes. What changes is the *enforcement surface*, deliberately:
CODEOWNERS, the CI walls, and `docs.instructions.md` itself all ship to
adopter repositories, where root `docs/` is application-owned — a shipped
rule or check pointed at this path would misfire on adopter projects.
So the gate here is procedural (PR review), not mechanical. Discovery is
wired through the shipped tier READMEs under `.github/docs/`: they distinguish
adopter truth from kit-side records in both source trees and link the kit ADR
directory. They do not prescribe root `docs/` for adopters.

## Conventions

Files here follow `.github/instructions/docs.instructions.md` (English
only, provenance headers in `context/`, ADR template and sequential
numbering in `agreements/adr/`) **by discipline**: the CI walls
deliberately scan only shipped scaffold paths, because in adopter
repositories root `docs/` is application-owned and must never be
subject to scaffold checks.
