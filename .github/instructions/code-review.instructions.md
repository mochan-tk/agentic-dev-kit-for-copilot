---
applyTo: "**"
---

# Code Review Standards

These standards guide Copilot code review, agent reviewers
(`.github/agents/reviewer.agent.md`), and human reviewers alike. A PR in this
repository is not just code — it is a claim that a Task issue's acceptance
criteria are met. Review the claim, not only the diff.

Check, in this order:

1. **Evidence.** The PR references its Task issue (`Closes #<n>`) and the
   evidence table maps every acceptance criterion to a command, link, or
   artifact. `REQ-###` citations are expected only where such agreements
   exist. Criteria without evidence: request changes.
2. **Ownership.** The diff stays inside the paths declared in the issue's
   "File ownership" section; a declared agreements wording rider
   (`docs.instructions.md`) is not a violation. Other out-of-scope files —
   even improvements — mean the plan and the work disagree: request changes
   and suggest `needs:replan`.
3. **Verification integrity.** Tests were added or updated for new logic. No
   test, lint rule, or CI check was deleted, skipped, or weakened to get green.
4. **Safety.** No secrets or credentials; no new external endpoints that are
   absent from the issue; no workflow/ruleset changes without explicit mandate.
5. **Deviation honesty.** If the implementation deviates from the issue, the
   PR's "Deviations" section says so, and downstream issues were flagged.
   Silent deviations are the most expensive class of agent error — flag them
   even when the code itself is good.
6. **Craft.** Only after 1–5 pass, review naming, structure, duplication, and
   comment quality. Prefer a few high-value comments over many nits; recurring
   nits belong in an instructions file via the retro skill, not in review
   threads forever.
