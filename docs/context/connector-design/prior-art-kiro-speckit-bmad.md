---
source: https://github.com/github/spec-kit; https://kiro.dev/docs/specs/; https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html; https://github.com/bmad-code-org/BMAD-METHOD; community analyses of Kiro system prompts (Reddit r/kiroIDE, public gists)
retrieved: 2026-08-06
method: web-research
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Prior art: Kiro, spec-kit, BMAD — elicitation and gating patterns

Web research performed during the design session. As `method: web-research`,
re-verify claims against the cited sources before promoting to agreements;
tool behavior changes quickly.

## Kiro (AWS)

- Spec workflow: `.kiro/specs/<feature>/` containing `requirements.md`,
  `design.md`, `tasks.md`.
- **Draft-first, not interview-first**: community-published analyses of its
  internal prompt instruct the agent to "generate an initial version of the
  requirements based on the user's rough idea WITHOUT asking sequential
  questions first". Requirements are user stories plus **EARS**-format
  acceptance criteria (Easy Approach to Requirements Syntax: "WHEN … THE
  SYSTEM SHALL …").
- **Explicit phase gates**: after generating, it asks "Do the requirements
  look good?" via a user-input tool (reason `spec-requirements-review`) and
  is forbidden to proceed to design until explicit approval; same gate
  between design and tasks.
- Gate durability: approval is a chat reply; nothing lands in a reviewable
  ledger unless the user commits the files themselves.

## spec-kit (GitHub)

- Slash-command pipeline: `/speckit.constitution` → `/speckit.specify` →
  `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.implement`;
  artifacts under `specs/<NNN-feature>/` (`spec.md`, `plan.md`, `tasks.md`).
- `/specify`: generates the spec from a one-line description; marks unknowns
  with `[NEEDS CLARIFICATION]`; asks **at most 3** questions inline; where it
  proceeds on defaults it records them in an **Assumptions** section
  (security/scope-affecting unknowns prioritized for asking).
- `/clarify`: **at most 5 questions, one at a time**, each multiple-choice
  (A/B/C…) **with a recommended option**, ordered by impact; every answer is
  written back into the spec as a dated Q&A log — provenance inside the
  artifact itself.
- `/speckit.taskstoissues` exists: converts `tasks.md` into GitHub issues —
  but as a flat transcription (no dependency graph, ownership paths,
  routing, or verification sections). Adjacent to, not overlapping with,
  this scaffold's plan-management layer.
- Positioning per its README: spec-kit is intent-to-spec-to-plan tooling; it
  does not run a governed multi-session execution lifecycle.

## BMAD-METHOD

- Role-based elicitation: distinct agent personas (Analyst, PM, Architect,
  Scrum Master…) each interrogate the idea through their own lens, producing
  PRD and architecture docs; strongest *elicitation depth* of the three.
- Heavyweight adoption cost (own agent bundle and workflow); no GitHub-native
  ledger or execution governance.

## Comparison (Fowler article, SDD tools)

- Positions spec-kit, Kiro (and Tessl) as "spec compilers": spec → plan →
  tasks pipelines of increasing weight, with Kiro described as the lightest
  of the set. Common critique: heavy upfront artifacts, weak feedback loop
  from execution back into the spec.

## What this scaffold borrows vs. adds

Borrowed patterns (into the builtin connector — see
`elicitation-ux-blueprint.md`): draft-first generation; EARS phrasing for
acceptance criteria; bounded question budgets ordered by impact;
multiple-choice with a recommended option; recorded assumptions; Q&A logged
into the artifact.

Added (absent in all three): the approval gate is a **PR review** (durable,
attributable, diff-anchored) instead of a chat "yes"; and the downstream
lifecycle — issue ledger, ritual walls, multi-session orchestration,
verification evidence — which none of the compared tools provide. The
scaffold is a runtime/OS for agentic development; spec compilers are
front-ends that can feed it through connectors.
