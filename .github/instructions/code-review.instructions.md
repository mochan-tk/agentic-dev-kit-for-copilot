---
applyTo: "**"
---

# Code Review Standards

These standards guide in-loop Rubber Duck critique, Copilot code review,
agent reviewers (`.github/agents/reviewer.agent.md`), and human reviewers. A
PR in this repository is not just code — it is a claim that a Task issue's
acceptance criteria are met. Review the claim, not only the diff.

They share one standard, not one job:

| Mechanism | Owns | Does not own |
|---|---|---|
| **Rubber Duck** (supported CLI/app surfaces) | In-loop critique of plans, designs, implementations, and tests; contrasting-model blind spots | Final Task audit, formal PR approval, or unsupported surfaces |
| **Copilot code review** | Generic bugs, vulnerabilities, logic defects, and craft in a diff or PR | Task evidence/ownership completeness or formal approval; its result is advisory |
| **Custom `reviewer`** | Task linkage, evidence, CI integrity, ownership, deviations, and governance safety | A second general code/craft pass or implementation fixes |
| **Human + ruleset** | Requirement interpretation, exceptions, CODEOWNERS decisions, formal approval, and merge authority | Re-running the inner implementation loop |

Official references: [Rubber Duck](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/rubber-duck)
and [Copilot code review](https://docs.github.com/en/copilot/concepts/agents/code-review).
Do not infer Rubber Duck support on surfaces GitHub has not documented or the
adopter has not verified.

Rubber Duck runs inside the work loop, before a PR audit, and is therefore not
a numbered PR gate below. Review a PR in this order. A mechanism runs the
checks assigned to it; a human may inspect any row. The custom reviewer is
required only for `risk:high` and governance-surface Tasks (`task-routing`,
Review routing); on ordinary Tasks the human owns checks 1–5 unless that
reviewer is selected.

1. **Evidence (custom reviewer + human).** The PR references its Task issue
   (`Closes #<n>`) and the
   evidence table maps every acceptance criterion to a command, link, or
   artifact. `REQ-###` citations are expected only where such agreements
   exist. Criteria without evidence: request changes.
2. **Ownership (custom reviewer + human).** The diff stays inside the paths
   declared in the issue's
   "File ownership" section; a declared agreements wording rider
   (`docs.instructions.md`) is not a violation. Other out-of-scope files —
   even improvements — mean the plan and the work disagree: request changes
   and suggest `needs:replan`.
3. **Verification integrity (custom reviewer + human).** Tests were added or
   updated for new logic. No test, lint rule, or CI check was deleted, skipped,
   or weakened to get green.
4. **Governance safety (custom reviewer + human).** No credentials,
   unrequested external endpoints, workflow/ruleset changes without explicit
   mandate, or edits to protected decision surfaces outside ownership.
5. **Deviation honesty (custom reviewer + human).** If the implementation
   deviates from the issue, the
   PR's "Deviations" section says so, and downstream issues were flagged.
   Silent deviations are the most expensive class of agent error — flag them
   even when the code itself is good.
6. **Code defects (Copilot code review + human).** Hunt for substantive bugs,
   vulnerabilities, logic errors, and performance failures beyond check 3's
   test-integrity obligation. Rubber Duck should already have challenged
   these in-loop on supported surfaces. AI findings are advisory; they never
   satisfy required approval.
7. **Craft (Copilot code review + human).** Treat naming, structure,
   duplication, and comment quality as lower priority than substantive
   findings. Prefer a few high-value comments over many nits; recurring nits
   belong in an instructions file via the retro skill, not in review threads
   forever.

When no AI review mechanism is enabled or available on the routed surface,
the human reviewer owns checks 6–7 as well.
