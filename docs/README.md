# Scaffold development records

This directory holds **the scaffold repository's own** development
records — the raw context collections and architecture decision records
produced while building the template itself:

- `context/` — raw intake about scaffold features (connector design,
  feedback loop), with provenance headers.
- `agreements/adr/` — ADRs governing the scaffold's own behavior
  (`ADR-0001` pluggable context connectors, `ADR-0002` consent-gated
  adopter feedback, `ADR-0003` two-tier task execution). New scaffold
  ADRs continue this numbering here.

## Why it lives at the repository root

The installer (`.github/scripts/scaffold-init.sh`) ships the `.github/`
tree plus `AGENTS.md` and `SCAFFOLD-CHANGELOG.md`, and seeds `README.md`
and `.gitignore` only when the target has none — nothing else. Keeping
these records outside `.github/` keeps them out of every
installed copy, so an adopter's `.github/docs/` starts pristine: their
planner reads `.github/docs/agreements/` as *their* reviewed truth, and
their ADR numbering starts at `ADR-0001` unpolluted by ours.

"Use this template" copies do include this directory (GitHub copies the
whole tree — same trade-off as `.devcontainer/`); adopters can delete it
freely.

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
wired the other way: the shipped tier READMEs under `.github/docs/` point
back to this directory.

## Conventions

Files here follow `.github/instructions/docs.instructions.md` (English
only, provenance headers in `context/`, ADR template and sequential
numbering in `agreements/adr/`) **by discipline**: the CI walls
deliberately scan only shipped scaffold paths, because in adopter
repositories root `docs/` is application-owned and must never be
subject to scaffold checks.
