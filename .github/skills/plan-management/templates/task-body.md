<!-- Canonical Task issue body. Mirrors .github/ISSUE_TEMPLATE/ai-task.yml.
     Used when creating Task issues via gh CLI / new-task.sh (issue forms
     apply only to the web UI). Keep the section headings exactly as below —
     agents and scripts parse them. Delete all comments before filing. -->

## Objective

<!-- One sentence: the observable outcome this task delivers. -->

## Context & references

<!-- Links the executing agent must read: agreements this task depends on
     (if any), parent Epic, prior PRs/issues, relevant .github/docs/context files.
     Assume the agent sees NOTHING beyond this issue and these links. Derived
     issues cite the origin as #N in one line (tracking-graph rule,
     plan-management skill); delete the "Derived from" line if this task has
     no origin issue. -->

- Epic: #
- Agreements (if any):
- Facts the agent needs:
- Derived from: #

## Acceptance criteria

<!-- Executable checks that land before implementation (test-first): each
     criterion is provable by running a Verification command or observing an
     artifact — the wall judges, not the account. Cite REQ-### where one
     exists. -->

- [ ]
- [ ]

## Out of scope

<!-- Explicit non-goals for THIS task. The cheapest scope-creep guard. -->

-

## File ownership

<!-- Paths (globs allowed) this task may modify. The diff must stay inside
     them (AGENTS.md §5). Parallel tasks must not overlap. -->

-

## Verification

<!-- How to run the pre-placed tests that decide the acceptance criteria:
     commands with expected results, executable on the routed surface
     (exec:cloud tasks get no hardware). -->

```bash

```

## Routing

<!-- See .github/skills/task-routing/SKILL.md. Mirror Surface as the exec:*
     label on the issue. -->

- Surface: exec:cloud | exec:app | exec:cli | exec:ide
- Suggested role: default | planner | orchestrator | reviewer
- Model/reasoning tier: high-reasoning | standard | fast | local
- Parallel-safe: yes | no — <why>

## Handoff notes

<!-- Optional: state another agent would need to take over or follow up. -->

-
