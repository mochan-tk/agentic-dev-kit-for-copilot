# <name> connector

<!-- Copy this file to <name>.md and fill every section. Keep the exact
     headings: the conformance wall greps for them. Write the procedure
     so an agent can execute it with no context beyond this file, the
     Contract in README.md, and the repository. English only. -->

One-paragraph summary: what source this connector adapts, and for whom.

## Metadata

- name: <name, matches the filename>
- access: <how the source is reached: conversation | in-repo files | external API …>
- reach: <what the source can see: repository | tenant data | …>
- trust-default: <trust level of retrieved content before re-verification>
- status: experimental

<!-- status must be one of: core | community | experimental.
     New contributions start experimental; see README.md for the
     promotion ladder. -->

## discover

How to detect that this source applies to the repository, and how to
enumerate what it contains. State the concrete signals (paths, config
files, API probes) and what to report when nothing is found.

## retrieve

How to land source material into `.github/docs/context/` with provenance
headers — or, for sources that already live in-repo, how to reference
them in place. Name the provenance fields to fill and any sensitivity
handling.

## pin

How to fix the exact source revision the plan will be built against
(commit SHA for in-repo sources; immutable IDs otherwise), and where the
pin is recorded (the project's SOURCES.md registry entry).

## verify

How to check that the pinned source still matches reality, and what to
do on drift: escalate with `needs:replan` on the affected Epic — never
silently re-pin.
