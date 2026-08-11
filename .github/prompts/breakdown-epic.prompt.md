---
mode: agent
description: Decompose an Epic issue into self-contained, routed, dependency-wired Task sub-issues (rolling-wave, current phase only).
---

Act as the planner defined in `.github/agents/planner.agent.md`, following
`.github/skills/plan-management/SKILL.md` and
`.github/skills/task-routing/SKILL.md`.

Epic issue number: ${input:epicNumber}

1. Read the Epic (`gh issue view ${input:epicNumber}`) and every agreement it
   references — many Epics cite few or none. Flag contradictions before
   planning; a missing agreement is not a blocker, so put the needed facts
   directly into the Task issue bodies.
2. Decompose **only the phase that is about to start** into Task issues.
   Draft each brief per `.github/ISSUE_TEMPLATE/ai-task.yml`: Objective,
   Context & references (agreements if any, facts the agent needs),
   Acceptance criteria, Out of scope,
   File ownership, Verification, Routing.
3. Check the partition: parallel-intended tasks must have disjoint
   File-ownership paths; overlaps get `blocked-by` edges instead.
4. Show me the proposed task list (title, exec label, dependencies, ownership)
   and wait for my approval.
5. On approval, create the issues with
   `.github/skills/plan-management/scripts/new-task.sh` (or the equivalent
   `gh issue create --parent` / `gh issue edit --add-blocked-by` calls) and
   add `ai:ready` only to complete briefs.
6. **Roadmap board:** if the board is missing (repo Projects tab, or
   `gh project list --owner <owner>`), ask my consent once to run
   `.github/scripts/setup-project.sh init`; on yes, set the created Tasks'
   schedule spans with `setup-project.sh dates` where dates are known.
   Never block decomposition on this: a decline is simply noted, and a
   missing `project` scope is reported with `gh auth refresh -s project`.
7. Post one summary comment on the Epic listing what was created and why,
   including the board outcome (URL, declined, or blocked).
