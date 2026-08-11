# Agentic Development Scaffold (GitHub-native)

Repository wiring for running an AI-agent development lifecycle on GitHub —
with GitHub Copilot cloud (coding) agent, the GitHub Copilot app's
parent/child sessions, Copilot CLI, and IDE agents — such that **the plan,
the work, the evidence, and the lessons all live on GitHub**, not in chat
windows. Everything here is plain files: version it, review it, and let the
improvement loops evolve it.

Two design premises. First, sessions are ephemeral and agents are stateless,
so GitHub (issues, PRs, committed files) is the only shared memory. Second,
**this scaffold is generic by design**: project truth is injected once,
through the `project-onboarding` skill, and kept honest afterwards by
`.github/scripts/tuning-status.sh` — so the same template serves any project and can
be sharply tuned the moment a target arrives.

The execution plane is **Copilot-native**: the GitHub ledger and
`AGENTS.md` stay platform-neutral, while every other agent-facing surface —
skills, custom agents, prompts, instruction files, CI walls — is built for
GitHub Copilot exclusively. Other platforms get the constitution and the
ledger — nothing else is promised.

Human judgment does not spread evenly across this lifecycle; it concentrates
at dispatch and at the **Three Merges**: the **agreement merge** (a
`.github/docs/agreements/` PR turns distilled context into reviewed truth), the
**license merge** (the onboarding evidence PR lands run-verified commands —
every command agents can verify unsupervised widens what may be delegated),
and the **completion merge** (a task PR whose evidence table proves its
acceptance criteria). Everything between these points is designed to run
without a human in the loop.

## The lifecycle

| Phase | What happens | Lives in |
|---|---|---|
| 0. Onboard | Tune the scaffold to the project: inventory → gap interview → run-verified commands → fill every CUSTOMIZE → evidence PR | `project-onboarding` skill, `tuning-status.sh` |
| 1. Collect | Land raw information with provenance — *pluggable via context connectors* (`.github/connectors/`): the built-in interview flow is the default, an existing spec-kit workspace can be adopted instead | `.github/docs/context/` via `context-collection` skill; `/kickoff-context` prompt; `setup-sources.sh` wizard |
| 2. Distill & agree | Turn raw material into reviewed truth (REQ/ADR/glossary/non-goals) via PR — *only when a decision must outlive its task* (promotion bar in the skill); place each piece of knowledge in a context tier. With a non-builtin connector, the enabled source satisfies the same Context Contract | `.github/docs/agreements/` via `context-distillation` skill; contract in `.github/connectors/README.md` |
| 3. Plan & orchestrate | Rolling-wave issue graph (Epics → just-in-time Task sub-issues, `blocked-by` ordering, actionable frontier); parent/child sessions execute it | `plan-management` + `session-orchestration` skills, issue templates |
| 4. Route & execute | Each task carries one `exec:*` label + Routing block deciding surface, role, and model tier | `task-routing` skill, `.github/agents/` |
| 5. Verify & learn | Layered gates (CI → security → AI review → human), evidence tables, and `retro:` PRs that improve the system itself — upstreaming what is project-agnostic | `verification` + `retro` skills, `ci.yml`, rulesets |

## Repository map

```
AGENTS.md                          Operating constitution (all agents, all surfaces)
SCAFFOLD-CHANGELOG.md              Template lineage: adopted version, upgrade path
LICENSE                            MIT
.gitignore                         Hygiene: session plan.md, OS/editor cruft stay untracked
.gitattributes                     Line-ending pin: scaffold paths stay LF so the bash
                                   scripts survive Windows checkouts (core.autocrlf)
docs/                              This repository's own development records: context
                                   collections and ADRs about the scaffold itself (copied by
                                   "Use this template"; the installer never ships it)
.github/
  CODEOWNERS                       Human review gate on agreements/, workflows/, connectors/
  copilot-instructions.md          Repo practicalities: layout, validated commands, PR mechanics
  dependabot.yml                   Weekly version updates for pinned GitHub Actions
  instructions/                    Path-scoped rules (.github/docs/, firmware/, code review)
  agents/                          Roles: orchestrator, planner, reviewer (*.agent.md)
  skills/                          Procedures (SKILL.md each):
    project-onboarding/              tune this scaffold to the target project
    context-collection/              intake with provenance
    context-distillation/            agreements + context tiering
    plan-management/                 issue graph, frontier, replanning
      scripts/                         frontier.sh, new-task.sh
      templates/                       canonical epic/task issue bodies
    task-routing/                    exec:* surface, role, model tier
    session-orchestration/           parent/child session protocol
    verification/                    gates, evidence, CI-failure triage
    retro/                           failures -> system improvements (+ upstreaming)
  prompts/                         Slash commands: /onboard-project /kickoff-context
                                   /distill-context /breakdown-epic /start-task
                                   /replan /retro
  connectors/                      Context connectors: Contract + conformance rules
                                   (README.md), builtin + speckit definitions, template
  ISSUE_TEMPLATE/                  Web forms mirroring the canonical bodies
  PULL_REQUEST_TEMPLATE.md         Evidence table + deviations + checklist
  workflows/                       ci.yml (quality, task-ritual, scaffold-self-check,
                                   copilot-surface jobs),
                                   copilot-setup-steps.yml (cloud agent env),
                                   retro-hygiene.yml (monthly review issue)
  docs/
    adopter-feedback.md            Feedback mechanism: what is sent, how to disable
    context/                       Phase-1 raw intake
    agreements/                    Phase-2 reviewed truth (+ retro-log.md)
  scripts/
    check-action-pins.sh           Action references SHA-pinned (quality)
    check-md-links.sh              Markdown path references resolve (scaffold-self-check)
    check-template-sync.sh         Issue forms <-> body templates in sync (scaffold-self-check)
    retro-hygiene.sh               Retro candidates + always-on budget report (--create-issue)
    scaffold-init.sh               One-liner installer: adopt (or --upgrade) the scaffold in any repo
    setup-labels.sh                Bootstrap the canonical label set
    setup-project.sh               Bootstrap the optional Projects v2 roadmap board
    setup-ruleset.sh               Branch ruleset for the step-4 gates (consent-gated in onboarding)
    setup-sources.sh               Activate a context connector (writes the SOURCES.md registry)
    tests/                         Offline regression tests for the CI guards (run-tests.sh)
    tuning-status.sh               Tuned or not? (report / --ci / --quiet)
.vscode/mcp.json                   MCP servers for interactive surfaces
.devcontainer/                     Codespaces / Dev Containers env for template contributors
                                   (copied by "Use this template"; the installer never ships it)
```

Everything the scaffold owns lives in `.github/` (plus root `AGENTS.md`,
`README.md`, `SCAFFOLD-CHANGELOG.md`); every other top-level path belongs
to your application and is never touched by the scaffold's checks.

## Conventions at a glance

- **Unit of work:** 1 Task issue = 1 session = 1 worktree/branch
  (`task/<issue-number>-<short-slug>`) = 1 PR (`Closes #<n>`).
- **Labels:** `type:epic`, `type:task`, `ai:ready`, `needs:human`,
  `needs:replan`, and exactly one of `exec:cloud | exec:app | exec:cli |
  exec:ide` per task.
- **Task issue sections (parsed — do not rename):** Objective, Context &
  references, Acceptance criteria, Out of scope, File ownership,
  Verification, Routing, Handoff notes.
- **Frontier** (what may run now): open `type:task` issues labeled
  `ai:ready` whose `blocked by` issues are all closed —
  `.github/skills/plan-management/scripts/frontier.sh`.
- **Reporting:** record-before-report (issue comment first, session message
  second) and verify-before-done (`gh`/`git` ground truth, never memory).
  A task's timeline reads start → plan → outcome; the issue body is the
  requester-owned work order and is never edited by the executing agent.

## How context reaches an agent (tiering)

Always-on files (`AGENTS.md`, `copilot-instructions.md`) stay lean and
universal; path-scoped `.instructions.md` files load only for matching
paths; skills load on demand by description; task-specific context travels
in the Task issue itself. The `context-distillation` skill owns tier
placement; the `retro` skill's Budget rule keeps always-on files from
bloating. Resist the urge to put everything in always-on context — it
degrades every request a little.

## Getting started

**Prerequisites:** `gh` (authenticated — check with `gh auth status`; the
setup scripts refuse to run without it), `jq`, and GitHub Copilot access
on at least one surface (VS Code Copilot Chat, Copilot CLI, or a GitHub
Copilot app session).

**Supported plans:** public repositories work on any GitHub plan; private
ones require a paid plan (the scaffold relies on features that need one),
so `setup-sources.sh` treats private + Free as a hard stop — make the
repository public, or upgrade the plan.

**Platforms:** macOS and Linux natively (every script runs on stock
bash ≥ 3.2).

- On Windows use WSL2, Git Bash, or the dev container — and type scaffold
  commands into a Git Bash prompt: plain `bash ...` in PowerShell may
  resolve to the WSL launcher, which lacks your `gh` login.
- Contributing to the template itself? Open it in GitHub Codespaces or VS
  Code Dev Containers — `.devcontainer/` provisions gh, jq, and the
  CI-pinned shellcheck.

1. **Install the scaffold** — at the root of your repository (new or
   existing), run the installer. Swap in your `<owner>/<repo>` to adopt
   from a fork.

   ```sh
   curl -fsSL https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.sh | bash
   ```

   On Windows, use the PowerShell bootstrap (it locates Git for Windows
   and runs the same bash installer through Git Bash):

   ```powershell
   irm https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.ps1 | iex
   ```

   - Installs only what the scaffold owns — `.github/**`, `AGENTS.md`,
     `SCAFFOLD-CHANGELOG.md` — plus `README.md` / `.gitignore` /
     `.gitattributes` when you have none; never `LICENSE` or `.vscode/`.
   - Stages the files without committing and records the adoption in
     `SCAFFOLD-CHANGELOG.md`; the seeded `.gitattributes` pins scaffold
     paths to LF so the bash scripts survive Windows checkouts.
   - Safety: collisions refuse unless you pass `--force`; `--dry-run`
     previews the plan and writes nothing; symlinked paths always
     refuse; the fetch is pinned to a commit SHA resolved before
     download.
   - `SCAFFOLD_REPO=owner/repo` and `SCAFFOLD_REF=<tag|branch|sha>`
     select a different source or version.

   **Already adopted?** Re-run with `--upgrade` to pull a newer scaffold
   (append `--dry-run` to preview first):

   - Scaffold-owned machinery is refreshed in place; your tuned surfaces
     (`copilot-instructions.md`, workflows, `CODEOWNERS`, instructions,
     `AGENTS.md`) and `.github/docs/**` are kept and listed.
   - Review the staged diff and land it as one PR.

   ```sh
   curl -fsSL https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.sh | bash -s -- --upgrade
   ```

   On Windows, plain `irm … | iex` cannot forward flags, so invoke it as
   a script block:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mochan-tk/ttt1-copilot/main/.github/scripts/scaffold-init.ps1))) --upgrade
   ```

   **Alternative for a brand-new repo:** click **Use this template** on
   GitHub and clone.

   - Copies the whole tree — including this template's `LICENSE`,
     `.vscode/`, and `.devcontainer/`, none of which the installer ships.
   - Replace the license with your own; keep the dev container for a
     ready gh/jq/shellcheck environment, or delete it.
   - Until onboarding completes, CI shows `scaffold not onboarded`
     warnings and agents are told not to trust the command sections.

   *Done when:* `.github/scripts/tuning-status.sh` lists the pristine `CUSTOMIZE`
   markers and exits non-zero — the untuned state is machine-visible.
2. **Onboard** — run `/onboard-project` in VS Code Copilot Chat, Copilot
   CLI, or a Copilot app session (any surface that reads
   `.github/prompts/`), or hand any capable agent
   `.github/skills/project-onboarding/SKILL.md`.

   - It inventories the repo, asks only the gaps, verifies commands by
     running them, and fills or removes every `CUSTOMIZE` block across
     the Sync Triangle (`copilot-instructions.md` ⇄ `ci.yml` ⇄
     `copilot-setup-steps.yml`).
   - Along the way it bootstraps the canonical label set
     (`.github/scripts/setup-labels.sh` — idempotent; `-R owner/repo`
     targets another repo) and drafts an outline Epic from your goal and
     material for you to review.
   - It ends with one evidence PR — review and merge it (the **license
     merge**). Manual fallback: search the repo for `CUSTOMIZE` and fill
     by hand.
   - After the merge, review the drafted Epic and run `/breakdown-epic`
     on it to turn it into Task issues (full flow: step 6).

   *Done when:* `.github/scripts/tuning-status.sh` exits 0 on the merged main.
3. **MCP** — interactive surfaces read `.vscode/mcp.json`; for the cloud
   agent and Copilot code review, mirror the servers in *Repository
   settings → Copilot*.

   - Secrets there must be prefixed `COPILOT_MCP_`; scope each server to
     the minimal `tools` list.
   - Keep the cloud agent's firewall and recommended allowlist enabled —
     extend the allowlist per-domain when a task genuinely needs it,
     never disable wholesale.

   *Done when:* each surface you use lists the servers you expect (skip
   this step if you use none).
4. **Branch ruleset on `main`** — require a pull request, the CI checks
   from `ci.yml`, and at least one approval from someone other than the
   author (this is what makes agent PRs human-gated); optionally
   restrict who can modify `.github/workflows/` and
   `.github/docs/agreements/`.

   - Onboarding asks for your consent and runs
     `.github/scripts/setup-ruleset.sh` accordingly — activation is your
     explicit choice, never silent.
   - Repository admins keep a pull-request-only bypass (the explicit,
     audited "bypass" button), because a solo adopter cannot approve
     their own PRs; direct pushes stay blocked for everyone.
   - Declined or skipped during onboarding? Re-run the script with
     `--enforcement active` later — it promotes the existing disabled
     ruleset in place instead of duplicating it.

   *Done when:* the ruleset shows **Active** in Settings → Rules →
   Rulesets, and an unapproved test PR is blocked from merging.
5. *(Optional)* **Roadmap board** — `.github/scripts/setup-project.sh init`
   creates (or reuses) "<repo> roadmap" and links it to the repo.

   - Fields: `Start date` / `Target date` plus a `Kind` single-select
     (Epic/Task). Boards are always user/org-owned; the link surfaces
     the board in the repository's Projects tab.
   - Schedule issues with the `dates` subcommand — it also sets `Kind`
     from the `type:epic` / `type:task` labels.
   - Manual steps remain: create the Roadmap view in the project UI and
     group it by `Kind` (`.github/skills/plan-management/SKILL.md`,
     Roadmap scheduling). At org level you can additionally define issue
     types and a Project with a Blocked view, keeping Project fields
     derived from issues.

   *Done when:* the board is visible in the repository's Projects tab.
6. **First run:**
   - Collect sources into `.github/docs/context/<topic>/` (`context-collection`).
   - When decisions must outlive their tasks, run `/distill-context` →
     agreements PR → human merges (= agreement). Skip when there is nothing
     above the promotion bar yet — most knowledge rides in Task issues.
   - Review the Epic drafted during onboarding — edit or replace it (form
     or `templates/epic-body.md`) — then run `/breakdown-epic` → approve →
     Task issues exist, wired and routed.
   - Dispatch the frontier: `exec:cloud` → assign the issue to Copilot;
     `exec:app` → open a parent session with the **orchestrator** agent and
     let it spawn one child session per task (`/start-task` inside each);
     `exec:ide` → a human pairs in the IDE (hardware work lands here).
   - PRs flow through the gates; on deviations run `/replan`; periodically
     run `/retro` so the system learns. Monthly, `retro-hygiene.yml` files
     a `Retro hygiene review <YYYY-MM>` issue surfacing promotion-overdue
     retro candidates and always-on budget drift.
   *Done when:* the first task PR merges with its evidence table — you have
   closed the loop once, and the scaffold is carrying your project.

## Scaffold lineage & upgrades (the second loop)

Within a project, the `retro` skill evolves this wiring via `retro:` PRs.
Across projects, improvements flow both ways through the template
repository: project-agnostic retro fixes are **upstreamed** (retro skill,
Upstreaming section), and instances **upgrade** by diffing against template
tags and cherry-picking while keeping their tunings — procedure and version
history in `SCAFFOLD-CHANGELOG.md`. Rule of thumb: procedures, templates,
and gates are upgradable; the Sync Triangle content and `applyTo` globs are
project truth and stay put.

## Adopter feedback (consent-gated, allowlist-only)

When an interactive scaffold script fails unexpectedly, it *offers* — never
sends automatically — to file a public issue upstream via your own `gh`,
containing only a fixed eight-field allowlist: no logs, paths, or
environment data. The body is previewed first, the default answer is No,
and deleting `.github/scripts/feedback-lib.sh` disables the offer.
Full description: `.github/docs/adopter-feedback.md`.

## Origin note

Licensed MIT (see `LICENSE`).

Conventions here encode one team's answers to: "how do we stay oriented when
many agents work in parallel?" (issue graph + frontier + record-before-report),
"how do we switch tools without re-briefing?" (routing labels + shared
instructions/skills read by every surface), and "how do we keep agents
honest?" (evidence tables + verify-before-done + layered gates). Adjust via
PRs; log the reasons in `.github/docs/agreements/retro-log.md`.
