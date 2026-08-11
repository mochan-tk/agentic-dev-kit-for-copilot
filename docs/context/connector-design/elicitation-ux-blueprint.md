---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-06/07)
retrieved: 2026-08-07
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Elicitation UX blueprint: builtin `/kickoff-context` (draft-first)

Agreed UX for the builtin connector's elicitation flow — the "None yet"
path for projects with no existing spec source. Supersedes an earlier
interview-first sketch that was discarded in-session after prior-art
research (see `prior-art-kiro-speckit-bmad.md`) showed draft-first is the
established pattern. As `method: ai-summary`, re-verify via PR review.

## Flow

1. **Intake.** The user invokes `/kickoff-context` and may hand over
   anything they already have: file paths, pasted text, URLs. Material
   lands verbatim in `.github/docs/context/<topic>/` with full provenance
   headers (context-collection skill). Providing files is the happy path —
   it shrinks the question budget.
2. **Draft first, don't interrogate.** From the material (or the user's
   one-paragraph idea), the agent drafts *complete candidate requirements*
   in EARS form ("WHEN … THE SYSTEM SHALL …"), each with a stable candidate
   ID. Unknowns are marked `[NEEDS CLARIFICATION]` inline. Where the agent
   proceeds on a default instead of asking, the default is recorded in an
   **Assumptions** section — silently invented facts are the failure mode
   being designed against.
3. **Bounded questions.** At most 3–5 questions per round, ordered by
   impact (scope/security first), each multiple-choice **with a recommended
   option**, one at a time. Questions already answered by the provided
   material are skipped. Answers are recorded in a dated Q&A file under
   `.github/docs/context/<topic>/` — the interview log is itself collected
   material.
4. **Promote sparingly.** Only material that clears the distillation
   promotion bar becomes `.github/docs/agreements/` content (REQ-### with
   stable IDs, ADRs for constraining choices). Everything else stays as
   context.
5. **PR as the approval gate.** The agent opens an agreements PR containing
   the collected context, the Q&A log, and the drafted agreements. The PR
   body carries the sufficiency evidence: the Epic-decomposition test
   result (see `context-contract.md`). CODEOWNERS routes it to the humans
   who own agreements; their review — inline comments, requested changes,
   eventual approval — is the durable equivalent of Kiro's "Do the
   requirements look good?", but attributable, diff-anchored, and
   `git blame`-traceable years later.

## Design rules distilled in-session

- **Draft-first**: never open with a questionnaire; generate, then refine.
- **Question budget**: hard cap per round; impact-ordered; skip what the
  material already answers.
- **Recommended option**: every question ships choices plus a recommended
  answer, so "accept all recommendations" is a valid fast path.
- **Assumptions ledger**: every defaulted decision is written down where
  the reviewer will see it.
- **Gate = PR review**: no chat-approval shortcut. The review happening in
  the ledger is the scaffold's differentiator over Kiro/spec-kit.

## Example shape (abridged, English; users may reply in their language)

> Agent: I've drafted 12 candidate requirements from your notes
> (REQ-C01…C12), 3 marked `[NEEDS CLARIFICATION]`, 2 assumptions recorded.
> Question 1 of 4 (highest impact): Should offline operation be supported
> in v1? (a) yes, full offline (b) read-only offline (c) online-only —
> **recommended: (c)**, your notes mention no offline use case.

The full localized wizard/interview wording is an implementation-phase
concern; this blueprint fixes the mechanics.
