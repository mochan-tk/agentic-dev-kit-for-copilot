# ADR-0003: Two-tier task execution — supervisor sessions and per-PR worker sessions

- **Status:** accepted
- **Date:** 2026-08-09
- **Supersedes:** none (amends AGENTS.md §4 "Unit of work")

## Context

AGENTS.md §4 currently binds the unit of work as **1 Task issue = 1 session =
1 branch = 1 PR**: a single executor session posts the claim and plan
comments, implements, iterates on CI, and answers review/audit rounds.

Field evidence from this repository shows that model concentrates all
context growth in one session:

- The issue #80 executor (PR #116) accumulated planning, implementation, a
  CI ritual repair, and a four-finding external audit response in a single
  session. Each rework round compounds: code reads, diffs, test output, and
  CI logs grow fast and are never released.
- The recovery mechanism (Resume protocol,
  `.github/skills/session-orchestration/SKILL.md`) restores a *dead* session
  from the ledger but does nothing to prevent a *live* session from
  bloating; it is an accident response, not a design.
- Stacked PRs (frozen issue #89) do not fit §4 at all: one Task producing
  several dependent PRs has no home in "1 session = 1 PR".

Meanwhile the sessions runtime (GitHub Copilot app, and any orchestrator
with equivalent tools) supports cheap child sessions: creator-nested
spawning, kickoff prompts, plan-approval gates, idle notifications, and
cross-session messages. Sessions are transport, GitHub is storage (§1) —
so nothing prevents splitting execution across sessions as long as every
hand-off is written to the issue ledger.

Context grows at two distinct speeds, which suggests the cut line:

| Concern | Content | Growth |
|---|---|---|
| Supervision | issue body, plan, worker reports, verification results | slow |
| Implementation | source reads, diffs, test output, CI logs, rework | fast |

## Decision

Split task execution into two session tiers and re-anchor §4 on the PR:

1. **1 Task issue = 1 supervisor session.** The supervisor owns the ritual
   and the thread of the task: it posts the claim and plan comments, spawns
   worker sessions, independently verifies their results against ground
   truth, steers rework, and writes the outcome comment. It does not edit
   application code.
2. **1 PR = 1 branch = 1 active worker session.** Each worker implements
   exactly one PR from a complete kickoff (issue link, plan-of-record
   link, file ownership, verification commands), gets CI green, reports
   back, and is then disposable. Rework may go to the same worker or to a
   fresh replacement — the plan and history live on the issue, so
   replacements start cheap. Dispatch is recorded durably: before a
   worker starts, the supervisor posts a worker-dispatch comment on the
   Task issue (worker branch, target PR, scope); a replacement is
   preceded by a comment releasing the old worker and naming its
   successor. A PR has exactly one active worker at any time.
3. **Stacked PRs are the multi-worker case — shape defined now,
   activation still gated by #89.** A Task whose diff must land as N
   dependent PRs gets N sequential workers, each based on the previous
   layer's branch. Mechanics: worker branches `task/<n>-<slug>-p<k>` (or
   the managed-prefix equivalent); only the final layer's PR carries
   `Closes #<n>`, earlier layers carry `Refs #<n>`; the outcome comment
   is posted after the last layer merges; layers merge bottom-up. This
   gives #89's evaluation a concrete execution shape but does **not**
   override its adoption condition: stacked execution stays off until
   the post-GA evaluation recorded on #89 passes.
4. **Small-task exemption from the worker-spawn obligation (explicit,
   not silent).** For trivial tasks the supervisor may skip spawning a
   worker and implement directly — single-session mode — but must declare
   it in the plan comment ("no worker will be spawned"), where it is
   vetoable through the normal plan-review channel. The default for
   everything else is the split.
5. **Plan gates by tier.** The supervisor's gate follows existing policy
   unchanged by this ADR: claim and plan comments always; an explicit
   approval pause only for `risk:high` tasks, lazy consensus otherwise
   (session-orchestration skill). Workers get **no second plan gate**:
   they execute the approved plan in autopilot, and the quality
   checkpoint for their output is the supervisor's PR review. A worker
   whose plan does not survive contact with reality stops and escalates
   to its supervisor (§6) instead of replanning alone.

The resulting session tree (app sidebar view):

```
conductor (human-created root)
└─ Epic orchestrator          — 1 Epic = 1 session (unchanged)
   └─ Task supervisor         — 1 Task = 1 session: claim, plan, verify, outcome
      ├─ worker → PR 1        — 1 PR = 1 branch = 1 session
      └─ worker → PR 2        — stacked layer or rework replacement
```

Roles remain portable (§1): a dead supervisor is replaced by a new session
resuming from the issue; the tree shape is grouping, not memory.

## Consequences

Easier:

- **Context economy by construction.** Supervisor context grows slowly;
  fast-growing implementation context is isolated per PR and discarded
  with the worker. Audit/rework rounds rotate workers instead of bloating
  one session.
- **Stacked PRs get a native shape** (one worker per layer); #89's
  post-GA evaluation now targets a defined execution model instead of an
  open design problem. Its adoption condition stands.
- **Sharper review claim.** A PR is authored only by sessions that did
  nothing but that PR.

Harder / must now be true:

- **+1 session per task** in the common case: more spawns, more kickoff
  prompts, one more report hop (worker → supervisor → Epic orchestrator).
  The small-task exemption bounds this cost.
- **Ritual attribution changes.** Claim and plan comments are posted by the
  supervisor while the PR is opened by a worker;
  `check-task-ritual.sh` must verify comment *existence and order*, not
  same-author identity. Needs an explicit test.
- **Kickoff completeness becomes load-bearing.** A worker sees nothing but
  its kickoff and the ledger; the supervisor's plan comment must carry file
  ownership and verification commands verbatim.
- **Single-writer rule maps to workers.** Concurrent workers under one
  supervisor must own disjoint path sets (§5 applies one level down);
  sequential (stacked) workers inherit the task's ownership.

Follow-up work if accepted:

- Amend AGENTS.md §4 (constitution PR, human-approved).
- Update `.github/skills/session-orchestration/SKILL.md`: mapping table
  gains the worker tier; parent protocol and report formats gain the extra
  hop; kickoff template for workers.
- Update `.github/skills/task-routing/SKILL.md`: routing applies per
  worker (a supervisor may run on a different surface than its workers).
- Verify `check-task-ritual.sh` against split attribution; fix if needed.
- Revise issue #117 (app session-tree documentation) to describe the
  two-tier model; #89 stays open as the post-GA activation tracker for
  stacked execution.

## Resolved design questions

1. **Exemption boundary → self-judged + declared.** Numeric proxies (file
   or line counts) correlate poorly with context growth — a one-file
   change with heavy CI iteration bloats; a ten-file mechanical rename
   does not. The enforceable control is the declaration in the plan
   comment, reviewed at the parent's plan-approval gate. Skills carry a
   heuristic as guidance, not a rule ("expecting more than one rework
   round, or broad code reading? spawn a worker"). Revisit via retro if
   the exemption is abused.
2. **Depth-4 validation → the adoption task itself is the pilot.** The
   risk to retire is not depth but mechanics: kickoff completeness, the
   extra report hop, and the ritual check under split attribution — none
   of which a throwaway pilot exercises realistically. The adoption task
   runs in the new shape (requester → supervisor → worker). One
   precondition is smoke-tested first: an agent-created session must be
   able to spawn its own child. If mechanics fail mid-pilot, the
   supervisor falls back to the declared exemption and lands the PR
   single-session — and the failure becomes recorded evidence to fix
   before the constitution amendment merges.
3. **Worker plan gate → none.** The supervisor's plan gate is the only
   plan approval; a second one would add latency without information.
   §6 covers the failure mode (worker stops and escalates when the plan
   meets reality), and PR review is the output checkpoint. Exploratory
   delegation may use plan mode, but such sessions are research
   delegations, not PR workers.

## References

- AGENTS.md §1, §4, §5 — persistence, unit of work, single-writer.
- `.github/skills/session-orchestration/SKILL.md` — current mapping and
  protocols.
- Issue #80 / PR #116 — field evidence of single-session context bloat.
- Issue #89 (frozen) — stacked PRs; absorbed by this decision.
- Issue #117 — app session-tree documentation; to be revised.
- App `orchestrate` skill (runtime-owned) — "one session ≈ one branch ≈
  one PR", which this decision adopts at the worker tier.
