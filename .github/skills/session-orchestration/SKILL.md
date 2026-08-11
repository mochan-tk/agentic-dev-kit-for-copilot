---
name: session-orchestration
description: Protocol for running work through parent/child agent sessions (e.g., the GitHub Copilot app's session tree, or any orchestrator dispatching cloud-agent runs). Use this whenever a session spawns or reports to another session, when starting work on a Task issue in a new session, when writing a completion/blocked/failed report, or when deciding what belongs in plan.md versus GitHub.

---

# Session Orchestration

Session trees and inter-session messages are powerful but **app-local**: a
cloud agent, a teammate, another machine, or you-next-week cannot see them.
GitHub is the only shared memory. Every rule below exists to keep the durable
record on GitHub while using sessions for speed.

## Mapping (two-tier, per ADR-0003)

| Plan object | Session object | Workspace object |
|---|---|---|
| Epic issue | Parent (orchestrator) session | — |
| Task issue | One supervisor session (ritual only, no code edits) | — |
| Pull request | One active worker session | One worktree + branch `task/<n>-<slug>` (or accepted tool-prefixed variant) |

One Task issue per supervisor session — never batch several issues into one
session (reports become unattributable) and never split one issue across
supervisors without replanning first. A PR has exactly one active worker at
a time; use a separate worktree per concurrent worker so parallel sessions
cannot write to the same checkout. For trivial tasks the supervisor may
implement directly (small-task exemption), declared in the plan comment.

**Who posts what:** claim, plan, worker-dispatch, and outcome comments on
the Task issue belong to the **supervisor**; the PR is opened and iterated
by the **worker**. Before a worker starts, the supervisor posts a
worker-dispatch comment (worker branch, target PR, scope); a replacement
worker is preceded by a comment releasing the old worker and naming its
successor.
**Machine-checked format:** the worker-dispatch comment's *first line* must
match the regex `^Dispatching worker`, and the release comment's *first
line* must match `^Releasing worker` — no leading blank line, greeting, or
Markdown heading before either — as enforced by
`.github/scripts/check-task-ritual.sh`. The same wall requires every task to
declare its execution mode (ADR-0003): either a dispatch trail (earliest
dispatch after the earliest plan and before the PR's first commit, a release
between successive dispatches, dispatch and release comments unedited) or a
plan comment carrying the small-task exemption phrase
"no worker will be spawned" (matched case-insensitively; AGENTS.md §4) — a
task showing neither fails the wall.

## Child session protocol

This ritual is executed by the **supervisor** session for its Task issue
(steps 1–5); the implementation itself runs in a worker session dispatched
afterwards (see Worker protocol below). Under the declared small-task
exemption, the supervisor performs both parts single-session.

**Start ritual** (do this before touching any file):
1. `gh issue view <n>` — read the full brief: Objective, Context & references,
   Acceptance criteria, Out of scope, File ownership, Verification, Routing.
2. Open every agreement the issue cites (`REQ-###`, ADR links) — many tasks
   cite none, which is normal. If a cited reference is missing, note it and
   proceed on the issue body; stop and apply the Ambiguity rule
   (`AGENTS.md` §6) only when a reference **contradicts** the issue — do
   not fill gaps with guesses.
3. Write `plan.md` in the implementing session's worktree root (the
   worker's, once dispatched; yours only under the declared small-task
   exemption): restate the acceptance criteria, the
   ownership paths, the verification commands, and your step plan. `plan.md`
   is a **session cache** — convenient, disposable, never authoritative, and
   never a substitute for updating the issue. Do not commit it
   (add to `.gitignore` if needed).
4. Comment one line on the issue: `Starting in session <name/link>, branch
   task/<n>-<slug>` (or the accepted tool-prefixed variant, AGENTS.md §4) —
   the branch is the worker's *intended* branch, forward-looking, and is
   named again in the worker-dispatch comment.
   Now the world knows this task is taken.
   **Machine-checked format:** the claim comment's *first line* must match
   the regex `^(Starting|Resuming) in session` — no leading blank line,
   greeting, or Markdown heading before it — as enforced by
   `.github/scripts/check-task-ritual.sh` (this exact wording has failed CI
   twice when paraphrased).
5. Post the plan as a comment on the Task issue **before your first
   commit**: goal restated, intended approach, files you expect to touch,
   verification you will run.
   **Machine-checked format:** the plan comment must contain a `## Plan`
   heading or have a body starting with `Plan:` — literal strings checked
   by `.github/scripts/check-task-ritual.sh`; a plan titled anything else
   does not count. The CI wall fails
   any PR whose linked Task lacks a claim and a plan comment, shows them
   out of chronological order (claim → plan → first commit, committer
   date), shows either comment edited after posting, lacks the `type:task`
   label, or whose PR `Plan:` line does not link a real plan comment on
   that issue in this repository. This comment —
   not `plan.md`, not the PR description — is the plan of record. The
   timeline then reads work order (body) → start → plan → outcome, which is
   what makes deviations diagnosable from one page.

Surfaces that write a plan into the PR description automatically (e.g. the
cloud agent) produce a convenient copy: link the plan comment from the PR
description and treat the issue timeline as authoritative.

**Risk gate** (`risk:high` tasks only): stop after posting the plan comment
and wait for an explicit approval comment from the requester/orchestrator
before the first commit. The default is pass-through — a posted plan on an
unlabeled task is actionable immediately (lazy consensus); the gate exists
only for tasks whose blast radius warrants a pre-flight human eye
(`plan-management`, Intervening).

**Work loop** (the implementing session — the worker, or the supervisor
under a declared exemption): stay inside the ownership paths; commit early
and often;
update `plan.md` freely — and when the plan changes *materially*, post a
fresh plan comment on the issue (never edit the old one; the sequence of
plan comments is the plan's history). If scope drifts, stop and follow the
Ambiguity rule rather than quietly expanding.

**Verify** (before any completion claim): run every command in the issue's
Verification section; then confirm external state with commands, e.g.
`gh pr view <pr> --json state,statusCheckRollup`, `gh pr checks <pr>`,
`git status --short` (must be clean), and, when the task tracked Project
items, `gh project item-list`. Evidence = command + observed result.

**Record before report** — post this comment on the Task issue, then (and
only then) message the parent:

```markdown
## Outcome: <completed | blocked | failed | needs-replan>
**PR:** #<pr-number>
**Evidence:**
| Criterion | Evidence (command / link) | Result |
|---|---|---|
| AC1 ... | `pio test -e native` -> 12 passed | pass |
**Deviations:** <none, or what differs from the brief and why>
**Follow-ups:** <suggested downstream issue changes, or none>
**Scaffold friction:** <none | retro:candidate issue link>
```

The **Scaffold friction** line is optional: fill it when you filed or +1'd a
`retro:candidate` issue during the task (retro skill, §Candidate ledger).

Any `deferred` row in the Evidence table prohibits `Outcome: completed`: the
outcome stays `blocked` or `needs-replan` until the requester revises the
work order (body edit + change comment) to remove or re-home that criterion.
The executor may propose the revision, never make it.

**Post-merge acceptance:** when criteria include steps that happen only
after the merge (a tag, a release, a deploy check), the PR links the issue
with `Refs #<n>`, never `Closes` (AGENTS.md §4). Order: merge → post-merge
steps → outcome comment → close the issue manually. Auto-close would end
the record before the work it certifies exists.

The message to the parent is a pointer, not a payload: outcome word + issue
and PR links. If the parent session is gone, the record still stands — that
is the point. Reports climb one hop at a time: the **worker** reports to its
**supervisor** (PR link, CI status, verification output, deviations); the
supervisor independently verifies against ground truth (`gh pr view/checks`,
diff vs. ownership), posts the outcome comment, and only then reports to the
**Epic orchestrator**. A worker never posts the ritual comments and never
reports past its supervisor.

## Worker protocol (ADR-0003)

A worker session implements exactly one PR from its kickoff. It runs the
plan of record in **autopilot with no plan gate of its own** — plan
approval, where required at all (`risk:high`), happened at the supervisor
tier; lazy consensus otherwise. PR review is the output checkpoint. If the
plan does not survive contact with reality (ownership
too narrow, contradiction with the referenced agreements), the worker stops
and escalates to its supervisor per AGENTS.md §6 — it never replans alone
and never posts comments on the Task issue. When done: PR open, CI green,
report to the supervisor, stop. Rework may return to the same worker or a
fresh replacement — the plan and history live on the issue, so replacements
start cheap.

**Worker kickoff template** — a worker sees only its kickoff and the
ledger, so the kickoff must be complete (kickoff completeness is
load-bearing, ADR-0003):

```markdown
You are the WORKER session for Task issue #<n> in <owner>/<repo>.
- Issue: <issue URL> — read it in full (`gh issue view <n> --comments`).
- Plan of record (execute it; no plan gate of your own): <plan comment URL>
- File ownership (verbatim from the issue — touch EXACTLY these):
  <paths, copied verbatim>
- Verification (run ALL before marking the PR ready):
  <commands, copied verbatim>
- Branch: task/<n>-<slug> (or managed-prefix equivalent). One PR,
  `Closes #<n>` (`Refs #<n>` instead for stacked non-final layers and
  post-merge acceptance, per AGENTS.md §4 and ADR-0003 Decision 3).
- Environment notes: <OS/shell quirks, tool constraints, anything not in the repo docs>
- Do NOT post comments on the issue; report to your supervisor session and stop.
```

## Parent session protocol

1. Dispatch only from the frontier (`plan-management` skill), after checking
   that concurrently dispatched tasks have disjoint File-ownership paths.
   For `exec:cloud` tasks, dispatch natively to the Copilot coding agent —
   assignment / `gh agent-task` — per the coding-agent section of
   `.github/skills/task-routing/SKILL.md`.
   Dispatching a `risk:high` task? Its child pauses after the plan comment —
   review promptly and reply with an approval (or steer) to release it.
   A dispatched cloud task whose PR shows *no* checks has usually not
   failed: many organizations gate workflow runs from this class of actor,
   leaving every run at `action_required` until someone approves it from
   the repository's Actions tab. Read the agent's own run before concluding
   anything — `gh run list` showing `Running Copilot cloud agent → success`
   next to `CI → action_required` means the work landed and only CI is
   waiting. The gate is an organization Actions policy, not a repository
   setting, so it cannot be cleared from here; where no such policy exists,
   nothing appears and there is nothing to do.
2. **Issue-first, dedicated-session — no exceptions for infra/ops.** Ad-hoc
   requests (e.g. a human asking "can you deploy this?"), and cloud/deploy/
   infra work in general (provisioning, secrets, deploy unblocking), get a
   Task issue created *before* any work begins, and run in a dedicated child
   session like any other task — never inline in the parent. No issue, no
   work: evidence recorded after the fact on a closed issue does not count.
3. When dispatching a **supervisor**, pass the issue number only — the
   issue is the brief. If
   you feel the need to add substantial instructions in the dispatch message,
   the brief is incomplete: fix the issue first. Supervisor→worker kickoffs
   are the exception: they use the complete Worker kickoff template above,
   because kickoff completeness is load-bearing (ADR-0003) and the worker
   never re-derives scope from the issue alone.
4. Steer with short course-correction messages when session logs show drift;
   prefer steering over restarting.
5. On receiving a report: verify the record exists on the issue and spot-check
   the evidence with your own `gh` calls before updating labels/Project state
   or dispatching dependents. An unrecorded report is returned to the child
   with one instruction: record first.
6. Route `needs-replan` outcomes to the planner procedure
   (`plan-management` §Replanning) and post the rationale on the Epic.

## Copilot app session tree

The GitHub Copilot app instantiates this protocol with a visible session
tree. Two structural facts shape it:

- **Conductor pattern.** Agents cannot create root sessions; only a human
  can. The human therefore keeps one long-lived root session — the
  *conductor* — from which all orchestration descends (conductor → Epic
  orchestrator → Task supervisor → worker). The conductor steers; it does
  not implement.
- **Creator nesting.** A session created by an agent nests under its
  creator in the sidebar. The tree shape is grouping, not memory: roles are
  portable (§1), and a dead session at any tier is replaced by a successor
  resuming from the ledger.

App tools that instantiate the protocol:

| Tool | Protocol step |
|---|---|
| `create_session` (kickoff prompt, mode, model) | Dispatch a supervisor or worker with a complete kickoff; choose mode (`autopilot` for workers) and model per the routing block |
| `open_issue_session` | Dispatch straight from a Task issue — the issue is the brief |
| `respond_to_session_plan` | The `risk:high` plan-approval gate, exercised by the parent |
| `notify_on_idle` | Wake the parent when a child finishes — the dispatch loop's completion signal |
| `send_session_message` | Steering, escalation (§6), and the report hop (pointer, not payload) |
| `archive_session` | Dispose of a finished worker; its context is released, the record stays on GitHub |

**Teardown order is leaf-first.** `archive_session` works only on sessions
its caller created, so archiving a supervisor before its workers strands
the workers — no agent can remove them afterwards, only a human. Workers
stay alive through review (rework returns to the same worker), so teardown
runs after the merge, not at closeout: the requester messages the
supervisor to tear down → the supervisor archives its worker(s) and
acknowledges → only then does the requester archive the supervisor.

## Resume protocol (crash-only)

Sessions die without warning — network, quota, machine sleep, closed laptop.
The scaffold has **no dedicated resume machinery** on purpose: the ordinary
start ritual *is* the resume path (crash-only design — recovery and startup
are the same code path).

- **Successor session**: run the start ritual (AGENTS.md §9) exactly as for a
  fresh task, then derive the current position from the ledger + ground
  truth: the issue timeline (start / plan / latest comments), the branch
  (`git log`, `git status`), and the PR (`gh pr view/checks`). What is not on
  GitHub did not happen — do not reconstruct intent from memory or chat.
- **Claim before touching**: post a *resume comment* on the Task issue
  (`Resuming in session <name/link>, branch task/<n>-<slug>`) before any
  commit. The claim prevents two sessions from silently owning one task; if
  the timeline shows another live claim, stop and escalate instead.
- **Orphan detection is the parent's duty**: a task with a start comment, no
  Outcome comment, and a dead session is an orphan. The parent (or any
  orchestrator sweeping the frontier) either dispatches a successor — which
  claims as above — or comments the task back to the frontier.
- **Repeat failure**: if the resumed attempt dies the same way the first one
  did, apply `needs:human` and stop. Two identical session deaths signal
  infrastructure, not approach — crash-resume is exempt from the three-strike
  ladder (Escalation below).

## Escalation

Execution failures climb a three-tier ladder. The boundary at every tier is
the **same failure three times**: then the work hands up one tier.

An attempt counts toward the *same failure* only when both the command or
check **and** the observed root-cause signature match. The counter resets
only after a materially different intervention grounded in new evidence —
changed code, configuration, inputs, ownership, or approach. A plain retry,
restart, or fresh session never resets it.

1. **Agent** — self-correction inside the session; vary the approach between
   attempts. Three identical failures spend this tier's budget.
2. **Parent session** — rephrase the work order, split it, or re-route it to
   a different surface or model. The same three-failure budget applies.
3. **Human** — label `needs:human` and stop the affected line of work.

Judgment and trust failures skip the ladder and go straight to a human: an
agreement in `.github/docs/agreements/` turns out wrong; credentials/security issues
appear; or two sessions claim the same ownership paths. These are not
execution failures — humans own those.
