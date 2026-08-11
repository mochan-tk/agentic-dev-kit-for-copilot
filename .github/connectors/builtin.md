# builtin connector

The "none yet" path: for projects with no existing spec source. Elicits
requirements conversationally with a draft-first flow and lands
everything in the repository, so the project satisfies the Context
Contract using only this scaffold. Design source:
`docs/context/connector-design/elicitation-ux-blueprint.md` in the
scaffold repository (development record; not installed).

## Metadata

- name: builtin
- access: conversation with the humans (no external system)
- reach: repository plus whatever material the humans hand over
- trust-default: draft — nothing is trusted until it clears PR review
- status: core

## discover

Applies when no other connector's `discover` finds a source (no
`specs/**`, no registry entry) or when the humans choose it explicitly.
Inventory what already exists: `.github/docs/context/` entries,
`.github/docs/agreements/` content, README claims. Report what is
present and what the Contract still lacks.

## retrieve

Run the draft-first elicitation (invoked as the `/kickoff-context`
prompt, `.github/prompts/kickoff-context.prompt.md`; the mechanics are
normative here):

1. **Intake.** Accept whatever the humans have — file paths, pasted
   text, URLs. Land it under `.github/docs/context/<topic>/` per the
   context-collection skill: provenance headers, sensitivity marking,
   and redaction first — secrets, tokens, and personal data are
   referenced, never pasted (verification skill, "Reference, don't
   paste"). Scaffold-owned artifacts stay English-only (AGENTS.md §8):
   land non-English material as an English rendering and note the
   source language in provenance. Provided material shrinks the
   question budget.
2. **Draft first, don't interrogate.** Draft complete candidate
   requirements in EARS form ("WHEN … THE SYSTEM SHALL …"), each with a
   stable candidate ID (`REQ-C##`). Mark unknowns `[NEEDS CLARIFICATION]`
   inline; record every defaulted decision in an **Assumptions** section
   instead of inventing facts silently.
3. **Bounded questions.** At most 3–5 questions per round, ordered by
   impact (scope and security first), each multiple-choice with a
   recommended option, one at a time; skip anything the material already
   answers. Record answers in a dated Q&A file under the same topic
   directory — the interview log is itself collected material.
4. **Promote sparingly.** Only material that clears the distillation
   promotion bar becomes `.github/docs/agreements/` content: `REQ-###`
   requirements with stable IDs, ADRs for constraining choices
   (context-distillation skill). Everything else stays context.

## pin

In-repo content needs no standing pin. The registry entry (the
SOURCES.md file under `.github/docs/context/`) records that builtin is
active, citing the activation PR by number — an immutable ID that,
unlike a merge SHA, is known from inside the PR itself. Working pins
are taken per Epic at decomposition time: each Task issue cites the
agreements paths plus the commit SHA it was planned against (Contract
condition 4).

## verify

The gate is the **agreements PR**: collected context, Q&A log, drafted
agreements, and the Epic-decomposition sufficiency evidence in the PR
body (README.md, "The sufficiency test"). CODEOWNERS routes it to the
humans who own agreements; their review is the durable approval — no
chat "yes" counts. Afterwards, drift is ordinary change management:
agreements change only via new PRs, so `verify` is re-running the
sufficiency test when planning the next Epic, comparing each open
Epic's decomposition pin against the current agreements revision, and
escalating `needs:replan` on drift or when the test stalls.
