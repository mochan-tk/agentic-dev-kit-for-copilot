---
name: plan-management
description: Build and maintain the executable plan as a GitHub issue graph — Epics, just-in-time Task decomposition, blocked-by dependencies, the actionable frontier, and replanning after deviations. Use this whenever creating or splitting issues, deciding what can run in parallel, wiring or changing dependencies, reacting to a task outcome that invalidates later tasks, or asking "what should agents work on next".
---

# Plan Management

The plan is not a document; it is the issue graph itself. Epics hold the
outline, Task issues hold executable work orders, `blocked-by` edges hold the
ordering, and the graph's edit history is the plan's change log. A schedule
drawn once never survives contact with reality — so this skill optimizes for
cheap, auditable plan *changes*, not for a perfect initial plan.

Requires GitHub CLI **v2.94.0 or later** (native `--parent`, `--blocked-by`,
`--blocking` support). Check with `gh --version`.

## Data model

| Concept | GitHub primitive | Conventions |
|---|---|---|
| Outline item / phase | Epic issue | label `type:epic`; template `epic.yml`; holds outcome, scope, phase outline |
| Work order | Task issue, sub-issue of an Epic | label `type:task`; template `ai-task.yml`; one `exec:*` label |
| Ordering constraint | Issue dependency (`blocked by` / `blocking`) | the only mechanism for sequencing — never encode order in prose only |
| Ready gate | label `ai:ready` | present only when the brief is complete enough for a context-free agent |
| Plan exceptions | labels `needs:replan`, `needs:human` | set by executors; consumed by planner/orchestrator |
| Risk gate | label `risk:high` | exception only: the task pauses after its plan comment until approved (see Intervening, and `session-orchestration`) |
| Portfolio view | GitHub Project (optional) | group by Epic, surface `Blocked` markers; keep Project fields derived from issues, not the reverse |

**Tracking-graph rule.** Diagnosis walks exactly four edge types: Epic →
sub-issue, `blocked-by`, in-body `#N` citations, and PR `Closes #N`. The one
writing rule that keeps the graph walkable: **an issue derived from another
(follow-up, discovered defect, split) cites its origin as `#N` in one line
of its body** — the `Derived from:` line in the task template exists for
this.

## Rolling-wave decomposition

1. Create Epics for the whole outline up front — cheap, low detail, gives the
   "what comes next" visibility agents need for preparation. One Epic per
   phase, all siblings: the graph is two levels, so an Epic is never a
   sub-issue of another Epic. Order them with `blocked-by`.
2. Decompose an Epic into Task sub-issues only when its phase is about to
   start (or when the frontier is nearly empty). Detail decays; write it late.
3. Every Task must clear the planner quality bar
   (self-contained, checkable, bounded, partitioned, routed —
   see `.github/agents/planner.agent.md`). Only then add `ai:ready`.
   Criteria that can only be met after the merge (a tag, a release, a
   deploy check) must say so in the work order — they commit the PR to
   `Refs #<n>` and a manual close (AGENTS.md §4).
4. Partition for parallelism: tasks meant to run concurrently must have
   disjoint **File ownership** path sets. If two tasks need the same paths,
   add a `blocked-by` edge between them — serialization by dependency beats
   merge-conflict roulette.
5. Once the round's Task issues exist, correct the Epic body's state line:
   replace the onboarding draft marker (*"Draft from onboarding — … nothing
   is decomposed until you approve."*) with one line naming the phase just
   decomposed and the date. Epics without that marker simply gain the line.
   Rewrite the same line on every later round — an Epic is decomposed many
   times, so a one-shot "approved" claim would go stale immediately. This
   is the one issue body an executing session may edit: AGENTS.md §5 binds
   an agent to its own **Task** issue, and the Epic is the plan it works
   from, not the work order it executes.

## The frontier

**Frontier = open Task issues labeled `ai:ready` whose `blocked by` issues are
all closed.** This is the set an orchestrator may dispatch right now.

- Compute it with `.github/skills/plan-management/scripts/frontier.sh`, or manually per issue:
  `gh issue view <n>` shows `Blocked by:` rows; each listed issue must be
  CLOSED. (Dependency data is also exposed as JSON fields in gh ≥ 2.94 — run
  `gh issue view <n> --json` with no field list to see the exact field names
  your version supports.)
- Before dispatching two frontier tasks together, re-check ownership
  disjointness — the graph guarantees ordering, not file safety.

## Command cookbook

Body files start from the canonical templates bundled with this skill:
`templates/epic-body.md` and `templates/task-body.md` (issue forms in
`.github/ISSUE_TEMPLATE/` mirror the same sections but apply only to the
web UI).

```bash
# Create an Epic (body: copy of templates/epic-body.md, filled in)
gh issue create --title "Epic: <outcome>" --label "type:epic" --body-file epic-body.md

# Create a Task under Epic #12, blocked by #14 and #15 — one call wires
# parent, labels, and dependencies atomically
# (.github/skills/plan-management/scripts/new-task.sh wraps this call; body:
#  copy of templates/task-body.md, filled in)
gh issue create --title "<task title>" --label "type:task,exec:cloud,ai:ready" \
  --body-file task-body.md --parent 12 --blocked-by 14,15

# Re-wire ordering on an EXISTING issue (only here does edit stay in play)
gh issue edit 23 --add-blocked-by 22
gh issue edit 23 --remove-blocked-by 14

# Inspect structure
gh issue view 23            # shows parent, Blocked by:, Blocking: rows
gh issue list --label "ai:ready" --state open --json number,title,labels
```

## Roadmap scheduling

Optional: visualize Epics and Tasks as spans on a Projects v2 roadmap. The
board stays a *view* of the issue graph — fields are derived from issues,
never the reverse (see the Portfolio view row in the Data model). Creation
has an owner: the first decomposition checks for the
board and, when absent, offers `init` with one consent question — declining
never blocks decomposition, and the board can still be attached manually
any time.

Bootstrap the board once per repository (idempotent: reuses the same-title
project, skips existing fields, re-links safely). `init` creates the DATE
fields `Start date` / `Target date` plus a single-select field `Kind`
(options `Epic`, `Task`) so both issue kinds are distinguishable on the
board:

```bash
.github/scripts/setup-project.sh init      # creates "<repo> roadmap", owner = repo owner
```

Projects v2 boards cannot be repo-owned — they always belong to a user or
org, so the board URL is `github.com/orgs/<owner>/projects/<n>` (or
`/users/...`). That is normal. `init` links the board to the repository,
which makes it appear in the repo's **Projects** tab
(`https://github.com/<owner>/<repo>/projects`) — look for it there. Pass
`--owner <login>` only to place the board under a different user/org.

When the board exists, set an issue's schedule span when the Task is
created during decomposition, and update it whenever replanning moves the
schedule (re-running replaces both dates on the existing item). The same
call sets `Kind` automatically
from the issue's labels — `type:epic` → Epic, `type:task` → Task:

```bash
.github/scripts/setup-project.sh dates --project <number> \
  --issue <n> --start 2026-07-07 --target 2026-07-11
```

**One-time manual steps:** in the project UI, add a *Roadmap* view, pick
`Start date` / `Target date` as its date fields, and set **Group by** to
`Kind` so Epics and Tasks render as separate swimlanes. View creation and
configuration (including Group by) are not exposed by the GitHub API, so
`init` cannot script this part; it reminds you on every run.

## Intervening in a task (three doors)

A posted plan is actionable immediately — plans do **not** require
pre-approval (lazy consensus); intervention is the exception, and it takes
exactly one of three doors:

1. **Steer the approach** (order unchanged): comment on the Task issue; the
   executor posts a *revised-plan comment* — conclusions only, never editing
   the old one. The comment sequence is the plan's history
   (`session-orchestration` skill).
2. **Change the order** (scope/criteria changed): edit the issue body — it is
   the requester-owned work order — and post the change comment immediately
   (Replanning §3). Pull `ai:ready` while the brief is stale.
3. **New work discovered**: never bolt it onto the in-flight task — file a
   new issue citing its origin `#N` in one line (tracking-graph rule) and
   wire `blocked-by` as needed.

Exception gate: a task labeled `risk:high` pauses after its plan comment
until an approval comment lands (`session-orchestration`, Risk gate). All
other tasks pass through.

## Replanning procedure

Trigger: a Task closes with recorded deviations; a `needs:replan` label
appears; an Epic's assumptions are invalidated; or the frontier is empty while
the Epic is unfinished.

1. Read the triggering record (issue comment / PR "Deviations" section). The
   trigger must already be written down — if someone asks you to replan from a
   verbal report, record it on the issue first (persistence rule, `AGENTS.md`).
2. Walk the downstream graph: the trigger issue's `Blocking:` list, its Epic's
   remaining sub-issues, and any task whose File ownership or references
   mention the changed area.
3. For each affected issue decide: **keep / modify / split / add / close**.
   Apply the decisions with `gh issue edit` / `create` / `close` — edit the
   graph, don't just talk about it. Closed-as-obsolete issues get a one-line
   reason; never delete issues (history is the audit trail). Every edit to a
   Task issue's **body** gets an immediate change comment on that issue:
   what changed, why, and whether in-flight work must replan. GitHub keeps
   body edit history behind the *edited* dropdown, but it never appears in
   the timeline — the change comment is what keeps the diagnosis trail
   readable top to bottom.
4. Remove `ai:ready` from any task whose brief is no longer accurate; restore
   it only after the brief is fixed.
5. Post one rationale comment on the Epic: what changed, why, and the list of
   added/modified/closed issue numbers. This comment stream is the diff log of
   the schedule.
6. Clear the `needs:replan` label from the trigger issue.

## Anti-patterns

- **Giant tasks** ("implement the whole feature") — undispatchable and
  unreviewable; split until each task fits one session/PR.
- **Hidden ordering** in prose ("do this after the API lands") without a
  `blocked-by` edge — invisible to frontier computation, so it *will* be
  violated by a parallel dispatch.
- **Silent work-order edits** — changing a Task issue's body without the
  change comment above. The timeline no longer explains what the executing
  agent saw at each point, so deviations stop being diagnosable.
- **Plan-in-a-file drift** — maintaining the real plan in a `plan.md` while
  issues rot. Session-local plan files are caches (see
  `session-orchestration`); the graph is the truth.
- **Premature detail** — fully decomposing phase 4 while phase 1 is running;
  you will rewrite it, and stale `ai:ready` tasks are dispatch hazards.
