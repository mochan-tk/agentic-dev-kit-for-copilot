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
2. **Roadmap board:** before decomposing, look for `<repo> roadmap` in
   `gh project list --owner <owner>`. If absent, search all `type:epic`
   issues (open and closed) for a comment beginning `Roadmap board: declined`.
   Only when no marker exists, ask my consent once to run
   `.github/scripts/setup-project.sh init`; on no, post that exact marker on
   this Epic. A decline never blocks decomposition and is never asked again.
   When the board exists, backfill **every open `type:epic` issue** with
   `setup-project.sh add --project <number> --issue <n>` — onboarding created
   the sibling Epics before this first decomposition.
3. Decompose **only the phase that is about to start** into Task issues.
   Draft each brief per `.github/ISSUE_TEMPLATE/ai-task.yml`: Objective,
   Context & references (agreements if any, facts the agent needs),
   Acceptance criteria, Out of scope,
   File ownership, Verification, Routing.
4. Check the partition: parallel-intended tasks must have disjoint
   File-ownership paths; overlaps get `blocked-by` edges instead.
5. Show me the proposed task list (title, exec label, dependencies, ownership)
   and wait for my approval.
6. On approval, create the issues with
   `.github/skills/plan-management/scripts/new-task.sh` (or the equivalent
   `gh issue create --parent` / `gh issue edit --add-blocked-by` calls) and
   add `ai:ready` only to complete briefs. When the board exists, add every
   created Task with `setup-project.sh add`; a missing `project` scope is
   reported with `gh auth refresh -s project`, never treated as a blocker.
7. Set schedule spans with `setup-project.sh dates` only where real dates are
   known. Dates are evidence, not a condition for appearing on the board.
8. Update the Epic body's state line: replace the onboarding draft marker
   ("Draft from onboarding — … nothing is decomposed until you approve.")
   with one line naming the phase just decomposed and today's date. An Epic
   that never carried the marker simply gains the line. Rewriting it each
   round keeps it true — rolling-wave decomposes the same Epic repeatedly.
9. Post one summary comment on the Epic listing what was created and why,
   including the board outcome (URL, declined, or blocked).
