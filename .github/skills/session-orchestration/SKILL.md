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
| The Epic set (whole project) | One Project session (conductor of conductors) | — |
| Epic issue | Parent (orchestrator) session | — |
| Task issue | One supervisor session (ritual only, no code edits) | — |
| Pull request | One active worker session | One worktree + branch `task/<n>-<slug>` (or accepted tool-prefixed variant) |

One Task issue per supervisor session — never batch several issues into one
session (reports become unattributable) and never split one issue across
supervisors without replanning first. A PR has exactly one active worker at
a time; use a separate worktree per concurrent worker so parallel sessions
cannot write to the same checkout. For trivial tasks **a Task supervisor**
may implement directly (small-task exemption), declared in its plan comment;
conductors have no such exemption — see Role boundaries.

**A sub-agent is not a session.** The `agent` tool starts a helper *inside the
caller's workspace*: same checkout, same branch, same write access, gone when
the turn ends. Only `create_session` yields the isolated workspace and branch
this model depends on. Calling a sub-agent "the Epic session" satisfies the
word and defeats the isolation — the work lands in the conductor's own
checkout, which is exactly what the layering exists to prevent. So: dispatch
an Epic or a Task by creating a session, and prove it **started** before the
work proceeds. Existence is not that proof — a session can sit there having
run nothing — and neither is the status the app reports. The proof is on
GitHub: the Task supervisor's claim comment, read with `gh`. This is not a
worker-comment requirement (see [role rows](#scenario-worker)); workers keep
evidence on their PR and report to their supervisor. No supervisor claim,
no Task start, whatever the sidebar shows. When it has not started,
dispatch once more; if the second attempt leaves the issue equally silent,
escalate with `needs:human`, because what is broken is the tooling and not
the plan. What that emphatically does not license is finishing the work here:
a dispatch that will not start is the moment a conductor is most tempted to
implement, and giving in is the boundary violation below, not an exception to
it. Sub-agents remain fine for what they are — bounded read-only research
inside one turn.

**Role boundaries.** A session's role is fixed when it is created; it is not
something a session reasons its way out of mid-run. A conductor (Project or
Epic) that finds itself about to edit application files, check out a Task
branch, or commit has met the boundary, whatever the justification: file or
locate the Task issue, dispatch it, and verify — or escalate (§6). "It is
small" is not a route around this; the small-task exemption belongs to Task
supervisors, whose job is that one Task, and it does not extend to a
conductor deciding to do the work itself.

**What enforces this, and what does not.** The `orchestrator` role withholds
`edit`, which is a real runtime grant. It keeps `execute`, because every
conducting step runs on it — the frontier script, `gh` reads for
verification, `gh` writes for labels, comments and merges — and a shell can
also write files, so the grant narrows the path without closing it. Nothing
here can pin a role to a session, deny writes per session, or hand a
conductor a read-only workspace: those are runtime features this scaffold
does not control. The same limit shows up at dispatch: whether a session that
ran nothing is reported as failed rather than idle, whether its launch error
ever reaches the creator, whether a turn count rides the notification, and
whether a retry exists at all belong to the app — which is precisely why the
start check above looks at GitHub, the one place this scaffold can see.
Treat the rules above as rules, not as a fence — and when
a conductor crosses them anyway, that is a retro, not a footnote.

**Who posts what:** claim, plan, worker-dispatch, and outcome comments on
the Task issue belong to the **supervisor**; the PR is opened and iterated
by the **worker**. Before implementation, the supervisor **creates the
worker session, confirms it exists with its actual identity and branch, then
records `Dispatching worker`, then releases the worker to implement**. It names
the session name, session ID, branch, target PR, and scope; use the
[render/preflight procedure](references/ritual-records.md). Generation never
proves worker existence. No verified worker, no implementation: a comment for a
session that was never created records a split that did not happen, which is
the one thing this trail exists to show (ADR-0003). A supervisor that cannot
raise a worker either declares the small-task exemption in its plan comment
and implements directly, or escalates — it does not write the comment
anyway. <a id="worker-disposition"></a>Before irreversible worker teardown or replacement, the supervisor's
release-and-successor or closeout record names the worker head SHA, whether
uncommitted work exists, its preservation location (or an explicit discard
decision and reason), and the single authority owning that disposition.
A replacement record releases the old worker and names its successor.
Preservation is not approval as mergeable: name any reused artifacts and
their fresh authorization in the record, and re-verify them before use.
Never present an earlier approval as a new one
([#6](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6)).
These are procedural duties, not runtime pause/resume or authentication.
**Machine-checked format:** the worker-dispatch comment's *first line* must
match the regex `^Dispatching worker`, and the release comment's *first
line* must match `^Releasing worker` — no leading blank line, greeting, or
Markdown heading before either — as enforced by
`.github/scripts/check-task-ritual.sh`. That first line also carries the
worker's identity, in this shape:

```
Dispatching worker: PR #12 worker (session 6af9582d-42d1-425d-82c8-f9ec651225a8), branch task/12-fix-esp32
```

The branch is compared against the PR's head ref, so a dispatch written for
one task cannot satisfy another's trail. The session ID is the evidence that
a session was really raised; CI cannot confirm it, because session trees are
app-local, so it is recorded for humans and later audits rather than
machine-verified. The same wall requires every task to
declare its execution mode (ADR-0003): either a dispatch trail (earliest
dispatch after the earliest plan and before the PR's first commit, a release
between successive dispatches, dispatch and release comments unedited) or a
plan comment carrying the small-task exemption phrase
"no worker will be spawned" (matched case-insensitively; AGENTS.md §4) — a
task showing neither fails the wall.

## Startup scenarios

Run the First contact status command on every fresh, child, replacement, or
resumed session. Read the owner decision linked from the current work
order/kickoff and the relevant issue timeline: it must explicitly decline
onboarding, cover this repository and work scope, and still apply. Carry the
link and scope into child kickoffs and PR evidence; do not reconstruct either
from chat memory. If the evidence cannot be read, do not assume a decline.

This is the canonical instruction-contract table, not a runtime enforcement
mechanism or measured model-compliance test. Status is the report/quiet exit
contract; CI's warning-only exit 0 does not establish tuned. A decline is not
authentication, a new implementation release, or a waiver of claim/plan,
`risk:high` approval, ownership, verification, or human merge authority
(ADR-0004). Conflicting authority is escalated through the supervisor.

| Scenario | Expected next action |
|---|---|
| <a id="scenario-tuned"></a>Tuned repository: status exits 0 | Report tuned; follow the authorized Task and role protocol. |
| <a id="scenario-fresh"></a>Fresh untuned adopter, or no applicable decline: status exits 1 | Acknowledge not onboarded; offer `/onboard-project` and wait for explicit yes/no before other work. On yes, enter onboarding; a no covers only its stated scope. |
| <a id="scenario-decline"></a>Intentionally untuned source template: exit 1 plus a linked, applicable owner decline | Acknowledge untuned and cite the decision; continue only already-authorized work without repeating the question or starting inventory/tuning. Keep CUSTOMIZE. |
| <a id="scenario-inherited"></a>Child, replacement, or resume: exit 1 with that same decline covering its work | Read and carry the decision link/scope; apply the scoped-decline action without a new onboarding or readiness approval stage. Existing per-Task approval conditions still apply. |
| <a id="scenario-invalid"></a>Missing/unreadable, unrelated, revoked, or contradictory decline | No reusable opt-out: exit 1 follows the fresh-adopter question; conflicting authority is escalated, not permission to proceed. A source marker, `sha=unknown`, fork, prior unrelated Epic, or chat memory never suffices. |
| <a id="scenario-error"></a>Startup command fails to run successfully: any other outcome, including missing interpreter/script or bad invocation | Report the error and next diagnostic step; do not classify tuned/untuned or use a decline to proceed past the error. |
| <a id="scenario-request"></a>New explicit request to onboard, even after a decline | Enter project-onboarding's existing workflow, handling startup errors truthfully; the prior decline is not a permanent opt-out. |
| <a id="scenario-supervisor"></a>Task supervisor, including resume or declared small-task exemption | Own issue claim/resume, Plan/update, dispatch/release, escalation, and outcome; verify the worker's PR record before outcome and report. Under the exemption, also implement; a conductor cannot take it. |
| <a id="scenario-worker"></a>Worker, including replacement/resume | Execute the approved plan; maintain PR evidence, verify, and report one hop to the supervisor. Never post Task-issue comments; supervisor records plan changes, escalation, and outcome. |

## Child session protocol

This ritual is executed by the **supervisor** session for its Task issue
(steps 1–5); the implementation itself runs in a worker session dispatched
afterwards (see Worker protocol below). Under the declared small-task
exemption, the supervisor performs both parts single-session.

**Prevention before publication:** for claim/resume, plan, and dispatch, use
[`task-ritual.sh`](references/ritual-records.md): render -> inspect -> read-only
preflight -> separate append-only publication. Stop on failure; escalate
malformed prior records, never silently supersede them. PASS expires as the
ledger changes: refresh immediately before posting; it proves neither future
CI nor authenticated identity and does not replace the existing risk gate.

**Start ritual** (do this before touching any file; apply the
[startup scenarios](#startup-scenarios) without inventing another gate):
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
and wait for an explicit requester/orchestrator approval comment before the
first commit.
The approval names permitted scope, execution authority, and risk once.
Within that scope, test -> red -> implement -> green needs no further
approvals. Re-approval is required only for material changes to production
impact, authority, ownership, or acceptance criteria, never a stage transition.
Tasks without `risk:high` remain actionable on posting the plan (lazy
consensus; `plan-management`, Intervening). The explicit exception remains
an owner-typed GO immediately before an irreversible live write; it is not
a stage gate for other work. Human merge authority is unchanged.

**Work loop** (the implementing session — the worker, or the supervisor
under a declared exemption): stay inside the ownership paths; commit early
and often; update `plan.md` freely. When the plan changes *materially*, the
worker stops and reports to the supervisor, who posts a fresh plan comment
(never edits the old one; the sequence is the plan's history). If scope
drifts, follow the Ambiguity rule rather than quietly expanding.

**Verify** (before any completion claim): run every command in the issue's
Verification section; then confirm external state with commands, e.g.
`gh pr view <pr> --json state,statusCheckRollup`, `gh pr checks <pr>`,
`git status --short` (must be clean), and, when the task tracked Project
items, `gh project item-list`. Evidence = command + observed result.

**Record before report** — the supervisor posts this comment on the Task
issue, then (and only then) messages its parent. The worker records evidence
in its PR before reporting to that supervisor; it does not post this comment:

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
- Startup context: <linked owner onboarding decision and repository/work
  scope, or none; carry applicable scope to replacement/resumed workers>.
  Apply [startup scenarios](.github/skills/session-orchestration/SKILL.md#startup-scenarios);
  a decline does not grant a new implementation release.
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

## Project session protocol

One Project session per project, created by onboarding as its closing move
(`project-onboarding` P6) once the phase Epics exist, and kept for the life
of the plan. It conducts conductors: it never decomposes, dispatches Tasks,
or edits code itself. Its first move waits for the onboarding evidence PR to
merge — a phase started against a half-tuned repository verifies nothing.

1. **Start an Epic's session when that phase's turn comes** — when its
   `blocked-by` Epics are closed, or the frontier has run dry. Hand it the
   Epic number and nothing else; the Epic is the brief. Name it `Epic #<n>`
   (session naming: §Copilot app session tree).
2. **Epic sessions are siblings, not descendants.** An Epic session that
   sees the next phase becoming actionable reports that to the Project
   session rather than starting a peer itself: sessions spawning their
   successors nest one level deeper per phase, and after a few phases the
   tree is unreadable. Epics are siblings in the issue graph; their sessions
   mirror that.
3. **Watch across Epics, not within one.** Phase-spanning trouble is the
   Project session's business: an Epic whose blockers never clear, a
   dependency that turns out to be backwards, repeated escalations of the
   same shape. Within an Epic, its own session decides.
4. **Replan across phases** (`plan-management` skill) when reality diverges
   from the outline — reordering phases, splitting one, dropping another.
   Record the rationale on the affected Epic, not in session memory.
5. **Ending.** Project sessions die like any other: before one ends, the
   state of play must be legible from GitHub alone — each Epic's status
   visible from its issue, its comments, and the board. Whoever restarts a
   Project session reads the graph, not the transcript.

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
   issue is the brief, and name the session `Task #<n> supervisor`
   (workers: `PR #<n> worker`; naming rule in §Copilot app session tree). If
   you feel the need to add substantial instructions in the dispatch message,
   the brief is incomplete: fix the issue first. Supervisor→worker kickoffs
   are the exception: they use the complete Worker kickoff template above,
   because kickoff completeness is load-bearing (ADR-0003) and the worker
   never re-derives scope from the issue alone.
4. Steer with short course-correction messages when session logs show drift;
   prefer steering over restarting.
5. On receiving a supervisor report: verify the issue record and spot-check
   the evidence with your own `gh` calls before updating labels/Project state
   or dispatching dependents — `gh` calls are the whole of it, because the
   artifact is CI's to verify and not yours to rebuild (`verification`
   §The layers). An unrecorded report is returned to the child
   with one instruction: record first. **Silence is checked the same way.** A
   supervisor that wakes its parent having written nothing on the issue has
   not been quietly productive — it has not started, or it has died. Read
   the issue before concluding anything; this is not a requirement for
   duplicate worker comments (see [worker row](#scenario-worker)).
6. Route `needs-replan` outcomes to the planner procedure
   (`plan-management` §Replanning) and post the rationale on the Epic.
7. When the Epic's phase is done — its Tasks closed, their PRs merged, the
   Epic's own state line current — tell the Project session so the next
   phase gets a session, then stop. Do not start that session yourself and
   do not carry on as it: the Project session keeps Epic sessions siblings
   (see Project session protocol), and a session that continues into the
   next phase makes the tree a single thread again. Stay open until the
   Epic closes — rework and late questions come back here. If
   no Project session is running, say so in the Epic's closing comment and
   name the next Epic, so a human or a fresh Project session can pick it up.

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

**Name sessions after what they work on**, so a sidebar of open sessions can
be read without opening any of them: `Project`, `Epic #1`, `Task #6
supervisor`, `PR #12 worker`. Keep the `#` — a bare number could be anything,
and a worker's PR number is not its Task's. Issue titles stay out: names are
display strings in a narrow column, where short and uniform beats descriptive
and truncated.

App tools that instantiate the protocol:

| Tool | Protocol step |
|---|---|
| `create_session` (kickoff prompt, mode, model) | Dispatch a supervisor or worker with a complete kickoff; choose mode (`autopilot` for workers) and model per the routing block |
| `open_issue_session` | Dispatch straight from a Task issue — the issue is the brief |
| `respond_to_session_plan` | The `risk:high` plan-approval gate, exercised by the parent |
| `notify_on_idle` | Wake the parent when a child stops. A wake is not a completion — it fires identically for finished, dead, and never-started — so what happened is read on the issue, not inferred from the notification |
| `send_session_message` | Steering, escalation (§6), and the report hop (pointer, not payload) |
| `archive_session` | Dispose of a finished worker; its context is released, the record stays on GitHub |

**Teardown order is leaf-first.** `archive_session` works only on sessions
its caller created, so archiving a supervisor before its workers strands
the workers — no agent can remove them afterwards, only a human. Workers
stay alive through review (rework returns to the same worker), so teardown
runs after the merge, not at closeout: the requester messages the
supervisor to tear down → the supervisor records the disposition above and
archives its worker(s) → acknowledges → only then does the requester archive
the supervisor.

**Conducting sessions are not torn down with them.** Teardown covers the
executing layers only: workers and Task supervisors, which carry the
heaviest context and whose record already lives on GitHub. An **Epic
session lives until its Epic closes**; the **Project session lives as long
as the plan**. Keeping them is what makes the tree readable — `Epic #1` and
`Epic #2` side by side — and guarantees a live session owns starting the
next phase. Archiving them instead leaves the plan with no conductor, and
the next phase gets absorbed into whatever session is still open.

## Resume protocol (crash-only)

Sessions die without warning. The ordinary start ritual *is* the resume
path: this is procedural recovery, **not runtime pause/resume machinery**.

- **Disposition before loss**: follow the canonical
  [worker disposition duties](#worker-disposition) before teardown or replacement.
- **Successor session**: run the start ritual (AGENTS.md §9) exactly as for a
  fresh task, using the [inherited-decline](#scenario-inherited) and
  [supervisor](#scenario-supervisor)/[worker](#scenario-worker) rows, then
  derive the current position from the ledger + ground truth: the issue
  timeline (start / plan / latest comments), the branch
  (`git log`, `git status`), and the PR (`gh pr view/checks`). What is not on
  GitHub did not happen — do not reconstruct intent from memory or chat.
- **Supervisor claim before touching**: the supervisor posts a *resume
  comment* on the Task issue
  (`Resuming in session <name/link>, branch task/<n>-<slug>`) before any
  commit. The claim prevents two sessions from silently owning one task; if
  the timeline shows another live claim, stop and escalate instead. A worker
  follows its existing dispatch, or the supervisor's release-and-successor
  record for a replacement; it never posts its own resume comment.
- **Orphan detection is the parent's duty**: a task with a start comment, no
  Outcome comment, and a dead session is an orphan. The parent (or any
  orchestrator sweeping the frontier) either dispatches a successor — which
  follows the role-specific claim/dispatch duties above — or comments the
  task back to the frontier.
- **Repeat failure**: if the resumed attempt dies the same way the first one
  did, the supervisor records `needs:human` and stops (workers report to it).
  Two identical session deaths signal infrastructure, not approach —
  crash-resume is exempt from the three-strike
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
