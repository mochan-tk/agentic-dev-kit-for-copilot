---
source: repository-owner-supplied HOTL review attachment
retrieved: 2026-08-16
method: verbatim
collector: Task #72 worker session
sensitivity: public
status: raw
---

# Human-on-the-Loop and Loop Engineering Review of `agentic-dev-kit-for-copilot`

Repository: [mochan-tk/agentic-dev-kit-for-copilot](https://github.com/mochan-tk/agentic-dev-kit-for-copilot)

## Conclusion

This OSS aligns **very strongly with the principles of Human-on-the-Loop (HOTL) and Loop Engineering**.

More precisely, however, it is best described as:

> **Human-on-the-inner-loop / Human-in-the-governance-loop**

In other words:

- Humans have largely been removed from the **fast inner loop** of implementation, testing, correction, and retry.
- Humans still participate in the **outer governance loop** for policy decisions, high-risk judgments, and final merge acceptance.

At the current stage, this is not a flaw. It is a reasonable form of gradual autonomy. However, as the number of tasks and agents grows, **monitoring, exception handling, and final merging can become the next human bottlenecks**.

My evaluation is as follows.

| Evaluation Area | Score |
|---|---:|
| Alignment with HOTL principles | **9.0 / 10** |
| Maturity of loop design | **8.5 / 10** |
| Maturity as an operational control system | **7.0 / 10** |
| Overall | **8.0 / 10** |

In one sentence:

> **It already has strong protocols, ledgers, guardrails, and learning mechanisms, but it does not yet have a fully trustworthy state estimator or a complete human-facing control console.**

This score is an architectural review of the repository's design and implementation. Because the repository is still relatively new and there is not yet enough public evidence of long-running use across multiple organizations with large numbers of agents, the empirical part of the assessment has an uncertainty of approximately ±0.5.  
Source: [SCAFFOLD-CHANGELOG.md](https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/SCAFFOLD-CHANGELOG.md)

---

## 1. Positioning the Term “Human-on-the-Loop”

First, one clarification: **Human-on-the-Loop itself is not a newly invented term**. In autonomous-systems research, the categories Human-in-the-Loop, Human-on-the-Loop, and Human-out-of-the-Loop have been used for some time.

What is newly receiving attention is the application of this idea to coding agents. The work is shifting away from:

- writing each individual prompt;
- correcting each AI output one by one;

and toward:

- designing the loop in which agents operate;
- building observability;
- defining stopping conditions and budgets;
- intervening only when abnormal conditions occur;
- improving the loop itself rather than merely fixing individual outputs.

This is the core of **Loop Engineering**.

IBM describes Loop Engineering as designing workflows in which agents iteratively move toward a user's goal. In discussions associated with Martin Fowler's ecosystem, the same direction appears: humans do not continuously operate agents step by step; instead, they manage the loop or harness in which agents work, and when problems occur, they improve the harness rather than only repairing the generated output. Addy Osmani similarly frames the human role as accountability and boundary-setting in the outer loop, rather than performing each individual task.

Under this definition, `agentic-dev-kit-for-copilot` is already more than a template for GitHub Copilot. It is clearly becoming a **development-loop harness**.

References:

- [NIST: EU-US Terminology and Taxonomy for Artificial Intelligence](https://www.nist.gov/document/eu-us-terminology-and-taxonomy-artificial-intelligence-second-edition)
- [Repository README](https://github.com/mochan-tk/agentic-dev-kit-for-copilot)

---

## 2. The Multiple Nested Loops in This OSS

This OSS does not implement a single loop. It implements multiple nested loops.

| Layer | Loop | Current Primary Actor | Human Position |
|---|---|---|---|
| Implementation loop | Understand → modify → test → correct | PR worker | Outside the loop |
| Task loop | Plan → dispatch → monitor → verify → retry | Task supervisor | Intervenes only on exceptions |
| Epic loop | Calculate frontier → parallel dispatch → integrate → replan | Epic orchestrator | Intervenes when direction changes |
| Governance loop | Agreements → risk judgment → approval → merge | Primarily human | Inside the loop |
| Learning loop | Collect failures → analyze causes → improve guards → upstream changes | Agent + human | Final approval and direction-setting |

The repository itself states that human judgment should be concentrated at dispatch and the “Three Merges,” while the work between those points should proceed without continuous human involvement. The Three Merges roughly correspond to governance boundaries around shared-rule agreement, installation and adaptation, and acceptance of deliverables.

Therefore, this OSS already expresses the central HOTL idea accurately:

> **Do not remove humans from software development entirely. Remove them from the fast inner loop and move them into the accountable outer loop.**

---

## 3. Evaluation Score Breakdown

| Evaluation Axis | Score | Assessment |
|---|---:|---|
| Placement of human involvement | **9.5** | Humans are concentrated around judgment, exceptions, and merges |
| Persistent state and traceability | **8.5** | The GitHub ledger is strong, but event authenticity has gaps |
| Completion criteria and verification | **8.5** | Evidence-based validation is already strong |
| Intervention, stopping, and recovery | **7.5** | The concepts exist, but operations are not yet fully structured |
| Observability and control console | **5.5** | Information exists, but it is not integrated for supervisors |
| Risk-proportional autonomy | **5.5** | Current management is still largely binary through `risk:high` |
| Parallel execution and conflict management | **8.0** | Issue graphs, worktrees, and the single-writer model are strong |
| Learning from failure | **9.0** | The philosophy of converting retrospectives into mechanisms is excellent |

---

## 4. Areas That Strongly Align with HOTL

### 4.1 Humans Are Shifted from “Doing Work” to “Making Decisions”

The README and `AGENTS.md` adopt a `hands off, voice on` model. Humans do not silently edit work directly; instead, they provide direction through comments and other visible mechanisms.

The repository also establishes principles such as:

- GitHub is the single source of truth;
- sessions may disappear;
- Issues, pull requests, comments, and files are persistent records;
- record before reporting;
- verify evidence before declaring completion.

Reference: [AGENTS.md](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/AGENTS.md)

This is essential for HOTL. A human supervising from outside the loop cannot depend on an agent's private reasoning or temporary chat history. They need **externalized, observable state**.

---

### 4.2 Clear Separation of Supervisor, Worker, and Orchestrator Roles

The OSS defines a role structure such as:

- 1 Task = 1 supervisor session;
- 1 PR = 1 worktree / branch / worker;
- the supervisor does not write application code;
- the worker focuses on implementation;
- the Epic orchestrator calculates the frontier and dispatches Tasks.

It also distinguishes simple subagent calls from independent sessions and records startup rituals such as claim, plan, branch, and session identifiers.

Reference: [Session Orchestration Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/session-orchestration/SKILL.md)

This creates a structure in which **higher-level agents supervise lower-level agents on the loop**, rather than requiring a human to supervise every action directly.

HOTL is therefore applied recursively:

- a human supervises the overall Epic;
- an orchestrator supervises a set of Tasks;
- a supervisor supervises workers;
- workers run tool and test loops.

This recursive supervisory architecture is relatively advanced.

---

### 4.3 “Automated Checks Define the Ceiling of Agent Autonomy”

Verification design is one of the repository's strongest areas.

It includes:

- defining acceptance criteria before implementation;
- preferring deterministic checks;
- layering tests, security checks, AI review, and human review;
- judging completion by evidence rather than self-report;
- escalating after repeated failure;
- explicitly recording deferred evidence instead of treating unverified conditions as complete.

Reference: [Verification Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/verification/SKILL.md)

In HOTL, if humans inspect every deliverable in detail, they become the bottleneck again.

Humans should not need to read the entire codebase every time. They should be shown:

- the goal;
- the diff;
- the checks that were run;
- the results;
- unverified items;
- risks;
- the agent's uncertainty.

This OSS is already moving strongly in that direction.

---

### 4.4 Lazy Consensus and Exception-Based Intervention

At the planning stage, the design does not require prior approval for every action. Instead:

- plans are published and execution normally proceeds;
- humans may redirect when needed;
- humans may change sequencing;
- humans may add work;
- explicit approval is required only for cases such as `risk:high`.

Reference: [Plan Management Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/plan-management/SKILL.md)

This is a textbook HOTL pattern.

In HITL:

> A human must repeatedly say, “You may proceed.”

In HOTL:

> Work proceeds by default, while humans retain the authority to stop it, redirect it, or change priorities.

This OSS already follows the latter model.

---

### 4.5 Crash-Only Recovery

The repository includes recovery principles such as:

- restoring state from GitHub records when a session fails;
- allowing a successor session to claim the work;
- having the parent detect orphaned work;
- escalating repeated failure to a human.

Reference: [Session Orchestration Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/session-orchestration/SKILL.md)

For long-running autonomous loops, it is more important to build a loop that can recover from failure than to assume the agent will succeed 100 percent of the time.

This is another area where the design goes beyond a simple collection of prompts.

---

### 4.6 Retrospectives Improve the Harness, Not Just the Output

The retrospective mechanism is the most clearly Loop-Engineering-oriented part of the repository.

When the same problem occurs twice, the repository does not treat it merely as an individual mistake. It treats it as evidence that something is missing from:

- instructions;
- skills;
- tests;
- CI;
- templates;
- guards.

It prioritizes converting lessons into stronger, more mechanical assets such as:

- deterministic tests;
- CI checks;
- templates;
- skills;
- commands;
- instructions.

Reference: [Retro Skill](https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/skills/retro/SKILL.md)

This is exactly the HOTL and Loop Engineering principle:

> When an output is wrong, do not only ask a human to fix the output. Improve the loop that produced it.

This area deserves a score above 9.

---

## 5. The Largest Weakness Is Not Yet the Control Console, but Sensor Trustworthiness

### P0-1. Fix the Authenticity and Freshness of the Task Ritual

Public Issue #6 identifies several weaknesses in the current Task ritual check:

- marker comments are detected using regular expressions over comment bodies;
- the system does not sufficiently validate the identity or authorization of the commenter;
- CI is not necessarily rerun when an `issue_comment` is added, edited, or deleted;
- a previously green result may remain stale after a comment is deleted or modified;
- in a public repository, a third party may be able to post a comment that matches the expected format.

This is not a minor CI defect.

It undermines the **trustworthiness of state observation**, which is foundational to HOTL.

When humans supervise from outside the loop, they do not directly observe every internal action. They rely on Issues, comments, Checks, and PR states as sensors. If those sensors can be forged or become stale, the supervisor is making decisions based on an incorrect state.

Reference: [Issue #6](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6)

#### Recommended Improvements

Re-evaluate related PR state when `issue_comment` events occur, including:

- `created`;
- `edited`;
- `deleted`.

GitHub Actions supports these event types.

Reference: [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions?use_case=bi%3Futm_source%3DHyperGPT&utm_medium=HyperStore)

Do not treat free-form comments as the source of truth. Bind structured events to the relevant task and attempt.

```yaml
schema: loop-event/v1
event_type: worker-dispatched
task: 123
attempt_id: task-123-attempt-2
session_id: abcdef
actor: mochan-tk
actor_role: supervisor
branch: task-123
pull_request: 456
head_sha: 0123456789abcdef
source_comment_id: 987654
occurred_at: 2026-08-16T00:00:00Z
```

At minimum, validate:

- whether the actor is authorized;
- whether the actor has the required repository permission;
- whether the Task, PR, branch, and head SHA match;
- whether the attempt ID is the current attempt;
- whether the source comment has been deleted or edited;
- whether the Check was issued for the current PR head SHA;
- whether the Check was issued by the expected GitHub App.

Ideally, humans and agents should not create authoritative state by writing arbitrary comments. Instead, a **GitHub App should record the structured event**, and the human-readable comment should be a rendered representation of that event.

For workflows triggered by `issue_comment`, avoid checking out and executing untrusted PR code in a privileged context. Permissions and secrets must remain minimal. GitHub explicitly warns about running untrusted code in trusted contexts.

Reference: [Secure Use of `pull_request_target`](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)

---

## 6. There Is a Gap Between Governance Documentation and the Actual Ruleset

### P0-2. Enforce the Intent of CODEOWNERS Through the Ruleset

The current CODEOWNERS design states that human review is required for areas such as:

- agreements;
- workflows;
- connectors;

and that this should be enforced in combination with a Ruleset.

However, the current Ruleset setup, based on the configuration reviewed, does not fully enforce all of the following:

- mandatory code-owner review;
- dismissal of stale approvals after new pushes;
- approval of the latest push by a separate user;
- resolution of all review threads before merge;
- strict required checks against the latest base branch.

Reference: [setup-ruleset.sh](https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/setup-ruleset.sh)

This creates a state in which:

> Human governance is documented, but a general approval may still be technically sufficient.

The more the inner loop is automated, the less ambiguous the outer governance boundary can be.

#### Recommended Ruleset

For governance-related paths, enable at least:

- Require code owner review;
- Dismiss stale approvals on push, or Require approval of the latest push;
- Require conversation resolution;
- Bind required checks to the expected GitHub App;
- Strict status checks, or Merge Queue;
- tightly limited administrator bypass with recorded reasons;
- separate rules for agreements, hooks, workflows, rulesets, guards, and retrospective promotion.

GitHub supports these through Rulesets and branch protection. Merge Queue can validate changes against the latest base branch and against other changes entering the queue.

Reference: [Available Rules for Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)

The current `tuning-status` primarily checks markers and placeholders. It does not fully express whether the repository is in a safe governance state.

Reference: [Project Onboarding Skill](https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/skills/project-onboarding/SKILL.md)

A separate status command should be added:

```text
governance-status
├─ branch ruleset active
├─ code owner review enforced
├─ stale approval policy
├─ required check source pinned
├─ merge queue enabled
├─ bypass actors
├─ workflow permission posture
└─ known accepted risks
```

“Installed” and “safely governed” should be reported separately.

---

## 7. An Explicit State Machine Is Needed

### P0-3. Move Beyond Inferring State from Labels and Comments

The repository records substantial state, but that state is distributed across:

- Issue labels;
- Issue bodies;
- plan comments;
- claim comments;
- dispatch comments;
- pull requests;
- CI;
- session sidebars;
- human comments.

Humans and orchestrators currently infer the current state by interpreting these artifacts.

This is strong as a ledger, but **implicit as a state machine**.

In HOTL, a supervisor should be able to answer immediately:

- What is currently running?
- Where is work stopped?
- Is it waiting normally or stuck abnormally?
- Whose decision is required?
- When was the last progress observed?
- Which attempt is current?
- What action will resume the work?
- How far can the system roll back?

A formal state machine should therefore be introduced.

```text
draft
  ↓
ready
  ↓
claimed
  ↓
planned
  ↓
dispatched
  ↓
running
  ↓
verifying
  ↓
review_ready
  ↓
approved
  ↓
queued
  ↓
merged
  ↓
observing
  ↓
accepted
```

Exceptional states should be modeled separately:

```text
blocked_human
needs_replan
failed
timed_out
cancelled
superseded
rolled_back
```

Labels and comments should not be treated as the state itself.

> **Structured events and a transition validator should be authoritative. Labels, comments, Projects, and dashboards should be projections of that state.**

This would allow the system to mechanically reject:

- duplicate dispatches;
- completion reports from stale attempts;
- branch mismatches;
- invalid state transitions.

---

## 8. A Human-Facing Supervision Console Is Missing

### P1-1. Build a HOTL Human-Machine Interface on GitHub

The repository already contains rich information, but supervisors must inspect multiple locations.

That is manageable with a few agents. It will not scale to 10, 20, or 50 parallel Tasks. Humans will spend time:

- opening Issues;
- reading comments;
- opening PRs;
- reading Checks;
- inspecting session status;
- investigating blockers;
- checking how long a task has been stalled;
- determining whether human judgment is required.

This merely shifts the bottleneck from human implementation to **human monitoring**.

The system needs an **exception console** that surfaces only items requiring attention.

#### Information to Show on One Screen

| Item | Meaning |
|---|---|
| Current state | `running`, `verifying`, `blocked`, and so on |
| State age | Time spent in the current state |
| Last heartbeat | Most recently observed activity |
| Attempt count | Current retry number |
| Worker / supervisor | Current responsible actors |
| Head SHA | Exact change set being verified |
| Evidence status | Evidence for each acceptance criterion |
| Risk tier | Required level of human involvement |
| Budget status | Time, retries, AI credits, and change size |
| Human action | Decision currently required from a human |
| Recovery action | `resume`, `retry`, `replan`, `cancel`, and so on |

#### Operations Humans Should Be Able to Perform

```text
pause
resume
cancel
reroute
request-evidence
request-replan
change-priority
approve-exception
reject
rollback
```

Free-form comments can remain available, but routine intervention should be structured.

This would evolve the model from:

> `hands off, voice on`

to:

> **hands off, structured control on**

---

## 9. Risk Management Is Too Binary

### P1-2. Move from `risk:high` to Graduated Supervision

The current `risk:high` mechanism is important, but real risk is not binary.

The following changes carry very different kinds of risk:

- fixing a typo in a README;
- adding tests;
- internal refactoring;
- modifying authentication;
- changing personal-data handling;
- changing GitHub Actions permissions;
- applying a production database migration;
- introducing a breaking public API change;
- modifying agreements or agent policy.

Risk should be assessed across dimensions such as:

- blast radius;
- reversibility;
- proximity to production or customers;
- secrets, personal data, and confidential data;
- required privileges;
- regulatory or contractual impact;
- novelty and ambiguity;
- testability;
- observability;
- dependency criticality;
- whether the change modifies the control mechanism itself.

#### Recommended Supervision Levels

| Tier | Examples | Human Involvement |
|---|---|---|
| A: Low / reversible | Documentation, bounded tests, mechanical corrections | Automatic execution; after maturity, auto-merge with sampled audit |
| B: Normal | Ordinary implementation with strong automated tests | HOTL; human approval at completion |
| C: High | Authentication, permissions, personal data, production impact | Approval before planning, approval at completion, named accountable owner |
| D: Restricted | Secret handling, destructive operations, legal judgment | Manual-only or prohibited |

The system should also raise the risk tier dynamically when:

- the number of changed files or lines exceeds the plan;
- changes cross file-ownership boundaries;
- the same test repeatedly fails;
- flaky results appear;
- acceptance criteria change during execution;
- a new external dependency is added;
- the agent attempts to access secrets or elevated permissions;
- the budget is exceeded;
- rollback becomes difficult.

---

## 10. Role Boundaries Still Depend on Behavioral Discipline

### P1-3. Restrict Supervisors and Reviewers by Capability

The architecture states that:

- the orchestrator does not implement;
- the supervisor does not write application code;
- the reviewer performs independent verification.

However, orchestrators and reviewers may still have shell or `execute` access, which technically allows file modification. The repository itself recognizes that `execute` may become a boundary hole.

Reference: [Orchestrator Agent Definition](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/agents/orchestrator.agent.md)

The current separation is therefore:

> instruction-based separation rather than capability-based separation.

As the number of agents grows, role separation based only on instructions becomes fragile.

#### Recommended Improvements

- give the orchestrator a read-only workspace by default;
- give the reviewer a verification-only workspace;
- allow only workers to write to the target branch;
- detect direct supervisor modifications through CI;
- compare session role with commit author and branch operations;
- reject dangerous operations through tool-call policy;
- allowlist commands by role.

GitHub Copilot hooks can intervene at session start, session end, prompt submission, and tool invocation. They can be used for authorization, validation, and auditing. Because hook coverage may vary by environment, hooks should not be the sole enforcement layer. Final boundaries should still be enforced through CI and Rulesets.

Reference: [Use Hooks with Copilot Coding Agent](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/use-hooks)

---

## 11. Heartbeats, Timeouts, Budgets, and Circuit Breakers Are Needed

### P1-4. Distinguish “Thinking” from “Stalled”

The repository already includes orphan detection and recovery procedures, but large-scale supervision requires mechanical monitoring of:

- the last heartbeat;
- maximum time allowed in each state;
- sessions that exist but are not progressing;
- work dispatched but never claimed;
- plans with no subsequent commits;
- CI failures followed by no retry;
- supervisors that have not received worker results;
- human escalations with no assigned owner.

Stopping conditions also need more than a retry counter.

#### Recommended Task Budget

```yaml
budget:
  max_attempts: 3
  max_wall_clock_minutes: 90
  max_ai_credits: 20
  max_changed_files: 12
  max_changed_lines: 800
  max_concurrent_workers: 2
  max_external_tool_calls: 30
```

When a budget is exceeded, the system should not merely fail. It should transition explicitly:

```text
running
  → budget_exceeded
  → blocked_human
```

The human should then be given structured choices:

- grant additional budget;
- reduce scope;
- reroute to a more capable model;
- clarify requirements;
- cancel the task.

If the Copilot SDK is used as an optional runtime adapter, it can provide:

- session resumption by session ID;
- soft caps on AI credits;
- usage by model or token;
- session events.

However, SDK dependency should not become a core requirement. The repository's current portability, with GitHub as the durable ledger, should be preserved.

Reference: [Copilot SDK Session Persistence](https://docs.github.com/en/copilot/how-tos/copilot-sdk/features/session-persistence)

---

## 12. Final Merge Will Become the Next Bottleneck

### P2-1. Introduce Delegation Licenses Rather Than Eliminating Human Approval

The current design removes humans from the implementation loop while retaining human judgment at the completion merge.

That is safe, but parallel execution can create a new queue:

```text
20 agents working
      ↓
15 PRs review-ready
      ↓
1 human reviewer
      ↓
merge queue backed up
```

To advance HOTL further, not every PR should receive the same level of human review. The system should define **classes of work that may be delegated**.

Trust should not be attached to a model or agent as a whole.

> **Trust should be granted to the combination of task class × target path × verification harness × historical performance.**

Example:

```yaml
delegation_license:
  task_class: documentation-and-tests
  allowed_paths:
    - docs/**
    - tests/**
  forbidden_paths:
    - .github/workflows/**
    - agreements/**
  required_checks:
    - quality
    - task-ritual
    - security
  max_risk_tier: A
  max_changed_files: 8
  auto_merge: true
  sampled_human_audit_rate: 0.2
```

Only low-risk tasks with strong verification should qualify for automatic merge, and only when all of the following hold:

- Merge Queue is used;
- required checks pass;
- checks correspond to the current head SHA;
- the change does not require code-owner approval;
- the task is within budget;
- the change stays within scope;
- no risk escalation occurred.

However, because Issue #6 and the Ruleset-governance gap remain unresolved, the repository should **not immediately enable broad auto-merge**.

Start in shadow mode:

> Record which PRs would have qualified for automatic merge, but still require a human to approve them.

Then compare the system's judgment against human decisions and measure escaped defects.

---

## 13. Include Post-Merge Observation in the True Outer Loop

### P2-2. Move from “Merged Means Done” to “Observed Outcome Means Done”

The repository already contains concepts such as deferred evidence and post-merge acceptance, but a more complete loop should include:

```text
merge
  ↓
deploy
  ↓
canary / staging verification
  ↓
production observation
  ↓
accepted
```

When an abnormality occurs:

```text
observing
  ↓
degraded
  ↓
rollback
  ↓
incident / retro
```

Reference: [Session Orchestration Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/session-orchestration/SKILL.md)

The system should observe more than test success:

- error rate;
- latency;
- user-visible regressions;
- security alerts;
- support tickets;
- business metrics;
- rollback events;
- production evidence tied to acceptance criteria.

This allows the agentic development loop to close not when a PR is created, but when the software has actually delivered the intended outcome.

---

## 14. Measure the Effectiveness of Retrospective Assets

The current retrospective design is excellent, but adding a mechanism does not automatically mean the system improved. Otherwise, instructions and workflows will accumulate indefinitely.

Each retrospective asset should record metadata such as:

```yaml
retro_asset:
  incident_pattern: missing-start-proof
  introduced_by: issue-123
  mechanism: ci-check
  owner: platform-team
  expected_effect: prevent false dispatch completion
  metric: recurrence_rate
  review_after_runs: 50
  expires_or_revalidates_at: 2026-12-01
```

Measure:

- recurrence rate before and after introduction;
- false positives;
- false negatives;
- additional human work;
- burden on agent context;
- added CI duration;
- whether the rule is being bypassed or becoming ceremonial.

The repository should also support **mechanism retirement** for obsolete instructions and duplicated guards.

Otherwise, every loop improvement increases context and ceremony until neither agents nor humans can understand the system.

---

## 15. Move from Magic-String Rituals to Structured Events

The current approach of expressing claim, plan, dispatch, and similar milestones through comments and validating their sequence through CI is a strong early implementation.

The system already checks:

- PR-to-Task linkage;
- start declarations;
- plans;
- worker dispatch;
- ordering relative to the first commit.

Reference: [CI Workflow](https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/workflows/ci.yml)

However, at larger scale, the following become ritual tax:

- writing exact marker strings;
- preserving comment formats;
- manually copying session IDs;
- repeating dispatch information in multiple locations.

A more mature interface would use commands such as:

```bash
agentic task claim 123
agentic task plan 123 --file plan.md
agentic worker dispatch 123 --branch task-123
agentic task handoff 123 --pr 456
```

A command or GitHub App operation would then:

- generate a structured event;
- render a GitHub comment;
- update labels;
- update Checks;
- update Projects;
- write the audit log.

Neither humans nor agents should need to author authoritative magic strings directly.

---

## 16. Mechanically Prevent Parallel-Execution Conflicts

The current design already manages parallel work well through:

- file ownership;
- a single-writer principle;
- Issue graphs;
- `blocked-by`;
- frontier calculation.

Reference: [Plan Management Skill](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/raw/refs/heads/main/.github/skills/plan-management/SKILL.md)

The design can be strengthened further by automatically detecting overlapping ownership before dispatch.

Example:

```text
Task A owns: src/auth/**
Task B owns: src/auth/token.ts
```

The system should detect this conflict before execution and choose one of the following:

- serialize the Tasks;
- split ownership;
- create an integration Task;
- block one Task.

Conflict detection should eventually consider more than file paths:

- package or module;
- API schema;
- database table;
- migration;
- configuration key;
- public interface;
- shared test fixture.

This prevents conflicts at loop-design time rather than repairing merge conflicts later.

---

## 17. Detect Governance Drift During Upgrades

The current upgrade policy preserves user-customized files such as:

- workflows;
- CODEOWNERS;
- instructions;
- `AGENTS.md`.

Reference: [Repository README](https://github.com/mochan-tk/agentic-dev-kit-for-copilot)

This is user-friendly, but it creates a risk: an important upstream security improvement may not be applied because a customized file is intentionally preserved.

Upgrade logic should compare a security-control manifest rather than only file diffs.

```text
Security control manifest
├─ ritual actor validation
├─ issue_comment freshness
├─ current-head check binding
├─ code-owner enforcement
├─ workflow permissions
├─ hooks policy
└─ required check source
```

The upgrade process should warn:

> A required control introduced in v1.2 is not active in this project.

This preserves customization while exposing **governance drift**.

---

## 18. Recommended Target Architecture

A mature version of the system could be organized as follows:

```text
┌─────────────────────────────────────┐
│ Human intent / policy plane         │
│ agreements・risk policy・budget     │
│ delegation license・merge authority │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│ Loop control plane                  │
│ state machine・event store          │
│ scheduler・heartbeat・circuit breaker│
│ routing・WIP limit・alerting         │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│ Execution plane                     │
│ Copilot app / cloud / CLI / IDE     │
│ orchestrator / supervisor / worker  │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│ Verification plane                  │
│ CI・security・independent review    │
│ deployment・production signals      │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│ Human supervision console           │
│ exceptions・approvals・audit        │
│ pause・resume・reroute・rollback    │
└─────────────────────────────────────┘
```

The current OSS already contains:

- the beginnings of a policy plane;
- an execution plane;
- a verification plane;
- a GitHub-based event ledger;
- a learning loop through retrospectives.

The major missing pieces are:

- the **Loop Control Plane**;
- the **Human Supervision Console**.

---

## 19. Practical Improvement Roadmap

### v1.1 — Trusted State

First, establish trustworthy state.

1. Fix Issue #6.
2. Re-evaluate state on `issue_comment` create, edit, and delete.
3. Validate actor permissions.
4. Bind attempt ID, head SHA, and comment ID.
5. Introduce `loop-event/v1`.
6. Add a transition validator.
7. Add governance-path-specific Rulesets.
8. Add a `governance-status` command.
9. Pin required checks to their expected source.
10. Strengthen regression tests for the guards themselves.

### v1.2 — Supervision

Next, make the system operable by supervisors.

1. Add a Task-state dashboard.
2. Add heartbeats and an orphan scanner.
3. Introduce typed escalation.
4. Add `pause`, `resume`, `cancel`, and `reroute`.
5. Introduce risk tiers.
6. Add budgets and circuit breakers.
7. Add an ownership-overlap checker.
8. Add role-specific hook policies.
9. Add exception-only notifications.
10. Add a human action queue.

### v1.3 — Graduated Autonomy

Then reduce human bottlenecks.

1. Introduce delegation licenses.
2. Add shadow auto-merge.
3. Integrate Merge Queue.
4. Add sampled human audits.
5. Track trust by task class.
6. Measure human minutes per Task.
7. Measure escaped defects.
8. Automatically raise and lower autonomy tiers.
9. Add deploy, observe, and rollback loops.
10. Measure retrospective effectiveness.

### v2 — Runtime Control Plane

After the need is validated, extract the control layer into a GitHub App or independent controller.

- Keep GitHub as the durable ledger.
- Connect Copilot app, cloud, and CLI through adapters.
- Keep the Copilot SDK optional.
- Allow other agent environments to connect to the same protocol.
- Make the protocol, not the UI, the core abstraction.

This would allow the project to grow beyond a Copilot-specific OSS into an:

> **Agentic Development Control Protocol**

---

## 20. The README Positioning Can Also Be Strengthened

The repository is already more than a development kit for Copilot.

The README could position it with language such as:

> **Agentic Dev Kit for Copilot is a GitHub-native control harness for Human-on-the-Loop software development. It lets Copilot agents execute inner development loops autonomously while humans govern goals, risk, exceptions, and acceptance from the outer loop.**

A more detailed description would be:

> **This is not merely a template for assigning work to GitHub Copilot. It is a GitHub-native control harness for safely supervising and controlling, from the outer loop, the development loops executed by multiple Copilot agents.**

The README could add a section such as:

```text
How this implements Human-on-the-Loop
├─ Loop boundaries
├─ Human decision points
├─ Agent decision points
├─ Intervention contract
├─ State machine
├─ Risk tiers
├─ Evidence model
└─ Known limitations
```

This would make the project's differentiation much clearer.

---

## Final Assessment

This OSS does not merely happen to be compatible with the recent Human-on-the-Loop terminology. **Its original design philosophy is already strongly aligned with HOTL.**

Its strongest elements are:

- using GitHub as a durable ledger;
- concentrating humans around decision points;
- converting planning into executable Issue graphs;
- separating supervisors from workers;
- judging completion through evidence;
- converting failures into harness improvements through retrospectives;
- supporting recovery under the assumption that sessions may disappear.

The next major improvement is not another agent skill or a more capable model.

It is:

> **a trustworthy state machine, structured events, risk-proportional intervention, and a supervisor-facing control console.**

If only three priorities are selected, they should be:

1. **Fix state authenticity, including Issue #6, and align the actual Ruleset with the documented governance model.**
2. **Introduce an explicit state machine and `loop-event/v1`.**
3. **Build a supervision console and risk-tier model that surface only exceptions requiring human action.**

Once those capabilities are added, this OSS can evolve from a development kit that aligns with Human-on-the-Loop into:

> **an Agentic Development Control Plane that makes Human-on-the-Loop operationally viable.**
