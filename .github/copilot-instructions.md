# Copilot Repository Instructions

Trust these instructions. Search the codebase only when something here is
missing or demonstrably wrong — and when that happens, propose a fix to this
file as part of your PR (see the retro skill).

## First contact

At the start of a session, run `bash .github/scripts/tuning-status.sh --quiet`
— on Windows, `pwsh .github/scripts/run.ps1 tuning-status.sh --quiet` instead,
because typing `bash` there reaches the WSL launcher rather than Git Bash even
when Git for Windows is correctly installed.

Read three outcomes: **0** means tuned; **1** means **not onboarded**;
**anything else**, including a missing interpreter/script or bad invocation,
means the check failed to run successfully. Report the error and next step,
never tuned/untuned or permission to proceed.
For exit 1, acknowledge untuned. Read any explicit owner decline linked from
the current work order/kickoff and verify its repository/work scope and
continuing applicability. If applicable, continue only already-authorized
work without asking again or starting inventory/tuning. Otherwise offer
`/onboard-project` and wait for explicit yes/no before other work. Source
markers, `sha=unknown`, forks, chat memory, or unrelated/revoked/contradictory
decisions are not substitutes. A new explicit onboarding request still enters
that workflow. See the canonical [startup scenarios](skills/session-orchestration/SKILL.md#startup-scenarios).

`AGENTS.md` at the repository root defines the operating protocol
(persistence rule, record-before-report, verify-before-done, unit of work,
single-writer rule, Ambiguity rule). It applies to you in full. This file adds the operational
details Copilot needs to work efficiently in this repository.

## Repository layout

The scaffold owns `.github/` plus the root files it shipped (`AGENTS.md`,
`README.md`, `SCAFFOLD-CHANGELOG.md`); every other top-level path belongs
to the application.

<!-- CUSTOMIZE: Keep this map accurate; it saves agents expensive exploration.
     Example:
     - `firmware/`  — PlatformIO project. Envs defined in `firmware/platformio.ini`.
     - `server/`    — API server. Entry point `server/src/index.ts`.
     - `app/`       — client app.
     - `.github/docs/context/`    — raw collected material (read for background).
     - `.github/docs/agreements/` — reviewed decisions (read before designing anything).
-->
- `.github/docs/context/` — raw collected material.
- `.github/docs/agreements/` — reviewed requirements, ADRs, glossary, non-goals.
- `.github/skills/` — procedures. `.github/instructions/` — path-scoped rules.
- `.github/agents/` — role definitions (orchestrator, planner, reviewer).

## Environment setup and validated commands

If `CUSTOMIZE` markers remain below, **First contact** (top of file) applies.

Run steps in this order. Do not improvise alternative commands when these work.

Scaffold-level (always valid, before and after tuning):
`bash .github/scripts/check-copilot-surface.sh` — validates the Copilot
execution-plane surface: frontmatter, ceilings, English-only.

<!-- CUSTOMIZE: Replace with commands verified to work in a clean environment,
     including known failures and workarounds. Keep this in sync with
     `.github/workflows/copilot-setup-steps.yml` so your interactive and cloud
     environments match. Example:

     1. `npm ci`               — install server/app dependencies (~2 min).
     2. `pip install platformio` — required before any firmware command.
     3. `npm test`             — full unit test suite; must pass before any PR.
     4. `pio test -e native -d firmware` — firmware logic tests on the host.
        Note: `pio test` without `-e native` tries to reach real hardware and
        will fail in cloud environments — never use it there.
-->

## Models

Recorded during onboarding (P2); `auto` means the app decides.

- **Implementation:** `auto`

Use it when dispatching implementation work. Review behavior is selected
per Task and surface (`task-routing`, `verification`), not frozen here.

## Working a Task issue

The Task issue body is your work order: you read it, you never edit it
(AGENTS.md §5). It follows
`.github/ISSUE_TEMPLATE/ai-task.yml` and contains: Objective, Context &
references, Acceptance criteria, Out of scope, File ownership, Verification,
and Routing. Read all of it before writing code.

**Supervisors** own Task-issue claim/resume, Plan/update, worker-dispatch,
release, escalation, and outcome comments. Follow the
[Child session protocol](skills/session-orchestration/SKILL.md#child-session-protocol),
including existing `risk:high` approval and record-before-report.
**Workers** follow [Worker protocol](skills/session-orchestration/SKILL.md#worker-protocol-adr-0003):
execute the approved plan, maintain PR evidence and its Plan link, run every
Verification command, and report to the supervisor; never post duplicate
Task-issue comments. Stop scope/authority conflicts and escalate to the
supervisor, who records them. See [supervisor](skills/session-orchestration/SKILL.md#scenario-supervisor)
and [worker](skills/session-orchestration/SKILL.md#scenario-worker) scenario rows.

Implementation stays on `task/<issue-number>-<short-slug>` (or managed-prefix
equivalent), inside **File ownership**; never weaken checks to pass. Only a
Task supervisor with a declared small-task exemption may implement directly.
Conductors keep their fixed role and cannot take that exemption (AGENTS.md §4).

## Pull request conventions

- Title: imperative mood, mirrors the Task issue title.
- Body: fill `.github/PULL_REQUEST_TEMPLATE.md` completely, including
  `Closes #<n>` and the evidence table.
- Keep PRs reviewable: one Task issue per PR; if the diff exceeds roughly 400
  changed lines outside generated code, propose splitting via `needs:replan`
  instead of pushing on.

## Things that will get your PR rejected

- Diff touches paths outside the issue's File ownership section.
- Acceptance criteria without evidence, or verification commands not run.
- Secrets, tokens, or credentials in code or config.
- PII, credentials, or customer data pasted into issues, PRs, or commit
  messages — reference access-controlled storage instead (verification
  skill, "Reference, don't paste").
- Modified CI workflows, rulesets, or checks without an explicit mandate.
- Non-English persistent artifacts (code comments, docs, commit messages).
