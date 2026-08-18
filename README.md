<p align="center">
  <img src="https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/docs/logo.png"
       width="200" alt="A circular emblem: a fairy conductor, eyes closed, raising a baton as notes drift upward">
</p>

# Agentic Development Kit

Three things go wrong when you hand work to AI agents. You cannot **see** what
was done. Decisions **scatter** across chat windows. And you are never sure
**how much** you can safely delegate. This repository is a working answer to
those three — as plain files you can version, review and change.

**Agentic Development** is the name for that answer: a layer of practice laid
over the process you already run. Waterfall, Scrum, Kanban — it replaces none
of them. Requirements, design, implementation, test and release stay exactly
where they are. What changed is *who does the work*. The moment a worker with
no memory joins the team, the process quietly loses the human recall and
oversight it was always built on. This layer fills that hole.

## Two theses

It starts somewhere unremarkable: **an AI agent is a new team member.** You
hand a colleague work as an issue, take delivery as a pull request, and judge
quality by review. GitHub already carries that machinery, so working with
agents needs no new one.

The analogy then breaks in exactly three places, and everything here follows
from them. An agent **loses its memory every morning** — yesterday's agreement
and the correction you typed are both gone. It **multiplies faster than you
can watch** — three capable colleagues become ten overnight. And its
**probation never ends** — trust does not accumulate the way it does with a
human hire.

From the first break comes the thesis the rest hangs on: **conversation
evaporates; only what lands in the repository and its issues persists.** Not a
slogan, a definition. A commit, an issue, a pull request comment — those are
landings. A brilliant exchange inside a session is not, and by tomorrow it is
indistinguishable from something that never happened.

Three disciplines fall out of that, and they are the floor everything else
stands on. **record-before-report**: the outcome is written to the issue
before anyone is told. **verify-before-done**: a claim of completion cites a
command or a check, never a memory. **single-writer**: parallel tasks never
share a file, or the plan serialises them instead.

## The system learns

A first failure is information. **The second of the same kind is a pattern**,
and a pattern is answered with mechanism, not with a reminder in chat — you
are talking to a colleague who forgets every morning. Land the lesson in a
file and it reaches every surface and every future session at once. That is
the `retro` loop, and it is why failure rates fall over a project's life: not
because the models got smarter, but because the conventions grew.

Some lessons turn out not to be about your project at all. Those go back to
the template this kit ships as, so the next project starts where the last one
finished — organizational learning, compounding.

## Start where you are

None of this has to arrive at once.

- **Level 1 — record-before-report.** Make agents write results into issues
  and pull requests first. Doable today, and "invisible" starts shrinking
  immediately.
- **Level 2 — delegate one task properly.** Write one self-contained issue,
  hand it to an agent, watch CI go green, land the merge. One small loop, and
  it doubles as the trial run for how much you can delegate.
- **Level 3 — full operation.** Verification gates, the actionable frontier,
  parallel sessions, the learning loops above.

You can tell which step you are on by the shape of the pain. Results scattered
across chat windows? Start at 1. Delegation works, but only for the one person
who knows the trick? Start at 2. Already running work in parallel? Take the
Level 3 parts in whatever order hurts most.

## How it is put together

Everything here is plain files: version them, review them, let the loops
change them. Two properties shape the rest. The kit is **generic by design** —
project truth is injected once, through the `project-onboarding` skill, and
kept honest afterwards by `.github/scripts/tuning-status.sh`, so the same
template serves any project and can be sharply tuned the moment a target
arrives. And its execution plane is **Copilot-native**: the GitHub ledger and
`AGENTS.md` stay platform-neutral, while every other agent-facing surface —
skills, custom agents, prompts, instruction files, CI walls — is built for
GitHub Copilot exclusively. The lifecycle is conducted from the **GitHub
Copilot app**, whose parent/child sessions carry the orchestration model, with
the Copilot cloud (coding) agent, Copilot CLI and IDE agents executing
individual tasks. Other platforms get the constitution and the ledger —
nothing else is promised.

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
| 1. Collect | Land raw information with provenance — *pluggable via context connectors* (`.github/connectors/`): the built-in interview flow is the default, an existing spec-kit workspace can be adopted instead | `.github/docs/context/` via `context-collection` skill; `setup-sources.sh` wizard |
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
                                   collections and ADRs about the scaffold itself
                                   (the installer never ships it)
.github/
  CODEOWNERS                       Human review gate on agreements/, workflows/, connectors/
  copilot-instructions.md          Repo practicalities: layout, validated commands, PR mechanics
  dependabot.yml                   Weekly version updates for pinned GitHub Actions
  instructions/                    Path-scoped rules (.github/docs/, firmware/, code review)
  agents/                          Roles: orchestrator, planner, reviewer (*.agent.md)
  skills/                          Procedures (SKILL.md each):
    project-onboarding/              tune the installed scaffold to the project
    context-collection/              intake with provenance
    context-distillation/            agreements + context tiering
    plan-management/                 issue graph, frontier, replanning
      scripts/                         frontier.sh, new-task.sh
      templates/                       canonical epic/task issue bodies
    task-routing/                    exec:* surface, role, model tier
    session-orchestration/           parent/child session protocol
    verification/                    gates, evidence, CI-failure triage
    retro/                           failures -> system improvements (+ upstreaming)
  prompts/                         VS Code Copilot Chat shortcuts to the skills
                                   above (the app loads the skills directly)
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
    governance-status.sh           Effective branch-governance sensor: health vs intent
    governance-drift.sh            Upgrade-drift sensor: control definitions vs tuned files
    ownership-overlap.sh           Parallel-dispatch sensor: Task ownership overlap
    setup-ruleset.sh               Branch ruleset actuator and dry-run candidate preview
    setup-sources.sh               Activate a context connector (writes the SOURCES.md registry)
    tests/                         Offline regression tests for the CI guards (run-tests.sh)
    tuning-status.sh               Tuned or not? (report / --ci / --quiet)
.vscode/mcp.json                   MCP servers for interactive surfaces
.devcontainer/                     Codespaces / Dev Containers env for kit contributors
                                   (the installer never ships it)
```

Everything the scaffold owns lives in `.github/` (plus root `AGENTS.md`,
`README.md`, `SCAFFOLD-CHANGELOG.md`); every other top-level path belongs
to your application and is never touched by the scaffold's checks.

## Conventions at a glance

- **Unit of work:** 1 Task issue = 1 session = 1 worktree/branch
  (`task/<issue-number>-<short-slug>`) = 1 PR (`Closes #<n>`).
- **Labels:** `type:epic`, `type:task`, `ai:ready`, `needs:human`,
  `needs:replan`, and exactly one of `exec:cloud | exec:app | exec:cli |
  exec:ide` per task. Three more are situational, not per-task:
  `risk:high` pauses a task after its plan comment until a human approves
  (the default is pass-through), `retro:candidate` marks observed friction
  for the retro loop, and `from:adopter` marks a feedback report — triage
  input, not a work order.
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
setup scripts refuse to run without it), `jq`, and the **GitHub Copilot
app** — the lifecycle runs on its session hierarchy (a program session
starts each Epic's session, which supervises its Tasks), which no other
surface provides. Copilot CLI and IDE chat execute individual tasks
alongside it; they are not substitutes for the app.

**On Windows**, also install [Git for Windows](https://gitforwindows.org) —
the app already requires Git, and its `bash.exe` is what runs these scripts.
Do not type `bash` there: the installer leaves `…\Git\bin` off `PATH` by
design, so `bash` finds the WSL launcher in `System32` instead. Run scaffold
scripts through the launcher, which locates the real Git Bash for you:
`pwsh .github/scripts/run.ps1 <script.sh> [arguments]`.

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
   curl -fsSL https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.sh | bash
   ```

   On Windows, use the PowerShell bootstrap (it locates Git for Windows
   and runs the same bash installer through Git Bash):

   ```powershell
   irm https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.ps1 | iex
   ```

   - Installs only what the scaffold owns — `.github/**`, `AGENTS.md`,
     `SCAFFOLD-CHANGELOG.md` — plus `README.md` / `.gitignore` /
     `.gitattributes` when you have none; never `LICENSE` or `.vscode/`.
   - Stages the files without committing and records the adoption in
     `SCAFFOLD-CHANGELOG.md`; the seeded `.gitattributes` pins scaffold
     paths to LF so the bash scripts survive Windows checkouts.
   - Commit them however your repository works — directly on the default
     branch, or through a pull request. Step 4's ruleset makes the pull
     request mandatory once it is in place, so the ritual wall exempts the
     PR that adds `AGENTS.md` and `copilot-instructions.md` to a repository
     that has neither. It has no Task issue to link because it is what
     brings the ritual with it.
   - Safety: collisions refuse unless you pass `--force`; `--dry-run`
     previews the plan and writes nothing; symlinked paths always
     refuse; the fetch is pinned to a commit SHA resolved before
     download.
   - `SCAFFOLD_REPO=owner/repo` and `SCAFFOLD_REF=<tag|branch|sha>`
     select a different source or version.
   - Until onboarding completes, CI shows `scaffold not onboarded`
     warnings and agents are told not to trust the command sections.

   **Already adopted?** Re-run with `--upgrade` to pull a newer scaffold
   (append `--dry-run` to preview first):

   - Scaffold-owned machinery is refreshed in place; your tuned surfaces
     (`copilot-instructions.md`, workflows, `CODEOWNERS`, instructions,
     `AGENTS.md`) and `.github/docs/**` are kept and listed.
   - Review the staged diff and land it as one PR.

   ```sh
   curl -fsSL https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.sh | bash -s -- --upgrade
   ```

   On Windows, plain `irm … | iex` cannot forward flags, so invoke it as
   a script block:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.ps1))) --upgrade
   ```

   *Done when:* `.github/scripts/tuning-status.sh` lists the pristine `CUSTOMIZE`
   markers and exits non-zero — the untuned state is machine-visible.
2. **Onboard** — run the `project-onboarding` skill in a Copilot app
   session.

   - It inventories the repo, asks only the gaps, verifies commands by
     running them, and fills or removes every `CUSTOMIZE` block across
     the Sync Triangle (`copilot-instructions.md` ⇄ `ci.yml` ⇄
     `copilot-setup-steps.yml`).
   - Along the way it bootstraps the canonical label set
     (`.github/scripts/setup-labels.sh` — idempotent; `-R owner/repo`
     targets another repo) and drafts one outline Epic per phase from your
     goal and material for you to review.
   - It ends with one evidence PR — review and merge it (the **license
     merge**). Manual fallback: search the repo for `CUSTOMIZE` and fill
     by hand.
   - After the merge, review the drafted Epics and break the first phase
     down into Task issues with the `plan-management` skill; full flow in
     step 6.

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

### Governance sensors and dry-run actuator ([ADR-0004](.github/docs/agreements/adr/ADR-0004-hotl-governance-sensors.md))

[ADR-0004](.github/docs/agreements/adr/ADR-0004-hotl-governance-sensors.md)
draws a hard line: repository governance is observed by sensors and
changed only by explicit adopter action. The three sensors below never mutate.
`setup-ruleset.sh` is an actuator only when you invoke it without `--dry-run`.
Use this section after onboarding or upgrades, before parallel dispatch, and
before you rely on branch governance to gate agent work.

- `bash .github/scripts/ownership-overlap.sh -R <owner/repo> <task>...` checks
  Task **File ownership** declarations before parallel dispatch. Exit **0**
  means the checked Tasks do not overlap; **1** means at least one overlap was
  found; **2** means usage, authentication, or API failure; **3** means at
  least one Task's ownership is uncheckable. The overlap check is a
  conservative literal-prefix approximation, so false positives serialize work
  rather than allowing an unproven parallel dispatch. Shared changelog
  ownership is intentionally not suppressed.
- `bash .github/scripts/governance-drift.sh --root . --strict` checks whether
  the current governance control definitions still match the tuned scaffold.
  Run it after installation, after scaffold upgrades, or whenever you suspect
  the control catalog drifted. Exit **0** means the report completed with no
  unwaived missing control under strict mode; **1** means strict drift was
  found; **2** means invalid input, schema, or dependency evidence blocked the
  report.
- `bash .github/scripts/governance-status.sh -R <owner/repo>` checks whether
  effective branch governance matches declared intent closely enough to trust.
  Exit **0** means required controls are healthy with complete evidence; **1**
  means a required control is `OFF`; **2** means usage or dependency failure;
  **3** means at least one required fact is `UNKNOWN` or `UNCHECKABLE`, which
  outranks `OFF` and is never safe to treat as healthy. API or authorization
  failure therefore remains unknown, not inactive.
- `bash .github/scripts/setup-ruleset.sh -R <owner/repo> --profile solo|team --dry-run`
  previews a fresh ruleset candidate, and `--profile solo|team --reconcile --dry-run`
  previews how the canonical same-name ruleset would be reconciled. Exit **0**
  means a valid preview was produced; **1** means dependency, authentication,
  API, canonical-ruleset, or issuer evidence blocked the operation; **2** means
  invalid usage. Reconciliation requires both an explicit profile and exactly
  one canonical ruleset with the expected name.

`governance-status.sh` accepts one-shot `--profile solo|team` overrides for the
status check itself, while persisted `SCAFFOLD_GOVERNANCE_PROFILE` is the
repository's declared long-lived intent. `solo` is the viable minimum profile.
`team` is the opt-in hardened profile that additionally expects stale-review
dismissal, latest-push approval, code-owner review, review-thread resolution,
strict required checks, and required-check source binding. This repository's
current docs must not be read as claiming that either profile is persisted
today; inspect the live status output for that fact.

Limits remain explicit. Eligible merge queues require `merge_group` CI
coverage before you can rely on them. Authenticated runtime events, immutable
roles, heartbeats, budgets, circuit breakers, pause/resume/cancel, and a
supervision console remain outside repository-file authority. Revisit
[#6](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6)
before enabling external contributors, delegation licenses, or auto-merge,
whichever comes first.
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
   - When decisions must outlive their tasks, distill them
     (`context-distillation`) →
     agreements PR → human merges (= agreement). Skip when there is nothing
     above the promotion bar yet — most knowledge rides in Task issues.
   - Review the Epics drafted during onboarding — edit or replace them (form
     or `templates/epic-body.md`) — then break the first phase down
     (`plan-management`) → approve → Task issues
     exist, wired and routed.
   - Dispatch the frontier: `exec:cloud` → assign the issue to Copilot;
     `exec:app` → open a parent session with the **orchestrator** agent and
     let it spawn one child session per task (`session-orchestration`);
     `exec:ide` → a human pairs in the IDE (hardware work lands here).
   - PRs flow through the gates; on deviations replan (`plan-management`);
     periodically run the `retro` skill so the system learns. Monthly, `retro-hygiene.yml` files
     a `Retro hygiene review <YYYY-MM>` issue surfacing promotion-overdue
     retro candidates and always-on budget drift.
   *Done when:* the first task PR merges with its evidence table — you have
   closed the loop once, and the kit is carrying your project.

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
