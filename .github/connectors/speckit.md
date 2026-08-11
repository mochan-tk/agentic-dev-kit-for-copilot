# speckit connector

Adopts an existing [spec-kit](https://github.com/github/spec-kit)
workspace as the project's requirements source: `specs/**` stays the
single source of truth, maintained with spec-kit's own commands, and
this scaffold's Phase 3–5 consume it through the Contract. Design
source: `docs/context/connector-design/design-session-decisions.md` and
`prior-art-kiro-speckit-bmad.md`, kept in the same directory of the
scaffold repository (development records; not installed).

## Metadata

- name: speckit
- access: in-repo files (`specs/**`, `.specify/**`)
- reach: repository only
- trust-default: repo-reviewed — trusted to the extent the project's
  own PR review covers `specs/**`; sufficiency verified at activation
- status: core

## discover

Applies when the repository contains a spec-kit workspace: `specs/`
feature directories (typically `spec.md`, `plan.md`, `tasks.md` per
feature) and usually `.specify/` scaffolding. Enumerate the feature
directories and report which Contract conditions their content already
meets — spec-kit's requirement keys satisfy condition 1 (stable IDs) and
its committed markdown satisfies conditions 3–4 (in-repo, referenceable).
Confirm the spec files are actually tracked: `git check-ignore
specs/*/plan.md` must find nothing (an overly broad ignore rule — in
any `.gitignore` on the path — silently drops spec content out of the
Contract; fix the ignore rule before activating).

## retrieve

Nothing is copied: `specs/**` already lives in the repository, so
retrieval is referencing in place. Do not duplicate spec content into
`.github/docs/context/` — that would create a second source of truth.
Record in the SOURCES.md registry entry (the machine-written file under
`.github/docs/context/`) that requirements resolve to `specs/**` at the
pinned revision. Decisions embedded in specs (spec-kit's `/clarify`
records Q&A inside the spec files) satisfy Contract condition 2 through
git history, not file immutability: spec files are editable, but every
revision is a reviewed PR diff, so "decided at revision X" stays
reconstructable. Decisions that must survive spec refactors — or that
constrain work outside spec scope — belong in scaffold ADRs.

## pin

Activation is **PR-A**: a single PR that (a) adds the speckit entry to
the SOURCES.md registry, recording the `specs/**` commit SHA current at
adoption, and (b) adds `specs/**` to CODEOWNERS so future spec changes
get owner review (CODEOWNERS applies from the base branch, so the rule
takes effect after PR-A merges — PR-A itself is reviewed under the
existing rules). Its body carries the sufficiency-test evidence
(README.md, "The sufficiency test"). Merging PR-A is the durable
decision "adopt `specs/**` as the requirements source"; the recorded
SHA is the **activation pin** — a historical fact that never needs
updating. Working pins are separate: each Task issue cites the spec
revision it was decomposed against (Contract condition 4).

## verify

Ongoing spec evolution is **PR-B**: because specs are in-repo files,
every change is naturally a reviewed PR — no extra machinery, and no
registry churn (the activation pin is historical; it does not chase
HEAD). Drift is checked against the working pins: when planning, and
before executing a Task, compare the spec revision the Task issues cite
against the current spec tree (`git log -1 --format=%H -- specs/`); on
mismatch, escalate `needs:replan` on the affected Epic so decomposition
is redone against the new revision — never silently proceed on stale
specs.
