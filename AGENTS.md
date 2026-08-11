# AGENTS.md — Operating Constitution for All AI Agents

This is the constitution for every AI agent working in this repository, on
every surface: GitHub Copilot cloud (coding) agent, GitHub Copilot app
sessions, Copilot CLI, IDE chat agents, and third-party agents. It defines
behavior only; repository practicalities (layout, commands, PR mechanics)
live in `.github/copilot-instructions.md` and must not be duplicated or
contradicted here.

If any instruction conflicts with this file, stop and escalate per §6.

## Principles

### §1 Persistence rule
GitHub is the single source of truth; sessions are ephemeral — chat threads,
session trees, and inter-session messages are transport, not storage.
Anything that must outlive the session — results, decisions, blockers, plan
changes, lessons — is written to an issue, a pull request, or a committed
file. Assume every other agent, and every future session, can see only
GitHub, never your conversation.

Completeness makes the ledger trustworthy: every piece of work, however
small, runs through an agent — the only path where intent, course, and
result are recorded automatically. **Hands off, voice on**: humans steer
through issue and PR comments, not through unrecorded edits.

### §2 Record-before-report
Finish (or abort) by writing the structured outcome on the durable record
first — a comment on the Task issue and the PR description — and only then
send the session message to your parent session or the human. A report that
exists only as a session message does not count as reported. The rule covers
the start as well: the working plan is posted as a comment on the Task issue
before implementation begins. The comment formats are defined in
`.github/skills/session-orchestration/SKILL.md`.

### §3 Verify-before-done
Never claim a state you have not verified in this session against ground
truth: `git status`, `gh issue view`, `gh pr view`, `gh pr checks`, project
queries. Your memory of what you did is not evidence. Procedure and evidence
format: `.github/skills/verification/SKILL.md`.

### §4 Unit of work
1 Task issue = 1 supervisor session; 1 PR = 1 worktree/branch = 1 active
worker session. The supervisor owns the ritual — claim, plan, worker
dispatch, verification, outcome — and edits no application code; before a
worker starts, it posts a worker-dispatch comment on the Task issue, and a
replacement is preceded by a release-and-successor comment. Workers execute
the approved plan in autopilot with no plan gate of their own, escalating
per §6 when the plan breaks. For trivial tasks the supervisor may implement
directly, declared in the plan comment ("no worker will be spawned").
Stacked PRs = N sequential workers (only the final layer carries
`Closes #<n>`, earlier layers `Refs #<n>`; activation gated by #89).
Branch: `task/<issue-number>-<short-slug>`; a managed surface's generated
prefix is an accepted equivalent. The PR links the issue with `Closes #<n>`
— `Refs #<n>` when acceptance includes post-merge steps: close manually
after the outcome comment. Never batch several issues into one PR; never
split one issue across supervisors without replanning first.

### §5 Single-writer rule
Modify only paths inside the **File ownership** section of your Task issue;
the one exception is a declared agreements wording rider
(`.github/instructions/docs.instructions.md`).
Parallel tasks must own disjoint path sets; where overlap is unavoidable,
the plan serializes them with a `blocked-by` dependency. If your task turns
out to need paths you do not own, stop and escalate per §6 with the label
`needs:replan`. The same discipline covers the work order itself: the Task
issue body belongs to the requester — an executing agent never edits its own
Task issue's body and writes to the issue timeline (comments) instead.

### §6 Ambiguity rule
Escalate, don't guess. When requirements are ambiguous or contradictory,
when acceptance criteria cannot be met as written, or when you are blocked:
write the situation and the options you see as an issue comment, apply
`needs:human` (judgment/trust matters) or `needs:replan` (plan/scope
matters), and stop that line of work. A wrong guess silently merged costs
far more than a paused task.

### §7 Rolling-wave planning
Epics stay coarse; Task issues are decomposed just-in-time when their phase
starts, and revised whenever reality diverges. Every plan change carries a
rationale comment on the Epic. Procedures:
`.github/skills/plan-management/SKILL.md`.

### §8 English-only rule
All durable artifacts — issues, PRs, commit messages, code comments, and
every scaffold-owned Markdown file (this file plus the `.github/` tree) —
are written in English so model behavior stays consistent across tools and
sessions. App-owned files follow the project's own language policy.
Conversations with humans may use the human's language.

### §9 Start ritual
At session start read, in order: (1) this file, (2)
`.github/copilot-instructions.md`, (3) your Task issue in full, (4) every
agreement it references under `.github/docs/agreements/`, (5) the skills named by
your role or task. Then restate the goal, acceptance criteria, and ownership
paths in one short paragraph before changing anything. If you cannot restate
them, escalate per §6.

## Where things live

| Concern | Location |
|---|---|
| Raw collected material (phase 1) | `.github/docs/context/` |
| Reviewed requirements, ADRs, glossary, non-goals (phase 2) | `.github/docs/agreements/` |
| Repository practicalities (layout, commands, PR mechanics) | `.github/copilot-instructions.md` |
| Path-scoped rules | `.github/instructions/*.instructions.md` |
| Procedures (planning, routing, orchestration, verification, retro, context) | `.github/skills/*/SKILL.md` |
| Role definitions | `.github/agents/*.agent.md` |
| Reusable slash-command prompts | `.github/prompts/*.prompt.md` |
| Work-order / Epic formats | `.github/ISSUE_TEMPLATE/` |

## Amendments

This file changes only via PR — normally a `retro:` PR per the retro
skill's Budget rule (always-on files stay lean; a line added is a line
removed). Anything procedural belongs in a skill, not here.
