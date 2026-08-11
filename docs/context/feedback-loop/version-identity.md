---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-08)
retrieved: 2026-08-08
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Version identity: the missing prerequisite

## Why reports need it

A report that says "setup-labels.sh failed at step X" is only actionable
if the maintainer knows *which* setup-labels.sh the adopter ran. The
scaffold evolves on `main`; adopters install at arbitrary points; without
a version marker every report starts with an archaeology exercise.

## What exists today

`scaffold-init.sh` already records adoption provenance: it resolves the
requested ref to a **full commit SHA before download** and writes a prose
line into `SCAFFOLD-CHANGELOG.md`:

    **Adopted:** from <owner>/<repo>@<full-sha> (requested ref: <ref>) on <date>.

Re-installs append further lines (newest first); local-tree installs
degrade to a short SHA or a bare path. An earlier draft of this file
wrongly claimed the installer records nothing — corrected after external
review against the installer source.

## The actual gap: no stable machine-readable schema

- The provenance is a prose sentence in a Markdown file: consumers must
  regex free text, and nothing guards the format against wording drift.
- Multiple `Adopted:` lines have no defined "current version" semantics.
- Local-tree installs may record no usable commit at all.
- "Use this template" copies carry **no upstream identity anywhere**:
  GitHub creates them with a single squashed initial commit unrelated to
  the template's history (per GitHub's template-repository docs), so git
  history cannot identify the template version either. The template's own
  changelog line (`v1.0.0 (this is the template itself…)`) is a
  placeholder that onboarding must update by hand.

## Candidate mechanisms (Epic decides)

1. **Promote the existing provenance to a machine-readable marker** —
   keep the human-readable line, and additionally write a structured
   field the helper can parse. Exact schema, location (structured
   changelog line vs. a dedicated marker file), and re-install/upgrade
   semantics are the Epic's call.
2. **Release-tagged distribution** — cut tags on the template repo and
   have the installer record the tag. Heavier process; premature while
   the scaffold iterates on `main`.
3. **Checksum-derived fingerprint** — hash the installed tree. Robust
   against manual edits but maps to a commit only with a lookup table;
   likely overkill.

Working assumption for the ADR: mechanism 1 — the marker carries the
upstream slug + full SHA + date (all already present in the prose line),
giving the feedback helper its filing target and version field from one
source. The marker is useful beyond feedback: upgrade tooling and drift
detection would read the same field.
