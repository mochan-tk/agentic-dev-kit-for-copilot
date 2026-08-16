---
name: retro
description: Convert repeated failures, recurring review comments, and incidents into permanent system improvements — targeted diffs to instructions, skills, agreements, templates, or CI, delivered as small `retro:` PRs and logged. Use this when the same class of mistake or review nit appears a second time, after any incident or rejected agent PR worth learning from, and during periodic reviews of whether the always-on instruction files have gone stale.
---

# Retro

Every guidance file in this repository (`AGENTS.md`, instructions, skills,
templates, workflows) is itself version-controlled and PR-reviewable — which
means the system can learn. Retro is the loop that makes it happen: a failure
observed twice is not bad luck, it is a missing asset. Fixing the instance
helps once; fixing the asset helps every future session of every agent.

## Trigger

- The same failure class or review comment appears for the **second** time
  (twice is the threshold: once may be noise, and encoding noise bloats the
  always-on budget).
- An agent PR is rejected, an incident occurs, or a task fails twice —
  regardless of repetition.
- Scheduled hygiene: periodically ask "which always-on lines have not mattered
  recently?" and demote them (see Budget rule).

## Candidate ledger

The trigger fires at the second occurrence — so first occurrences must be
counted somewhere durable. That ledger is `retro:candidate` issues (AGENTS.md
§1: GitHub, never chat or local notes).

1. **Search before filing:**
   `gh issue list --label retro:candidate --search "<keyword>"`.
2. **File** if absent: title `retro-candidate: <one-line friction>`, body =
   link to the occurrence plus one line of context, label `retro:candidate`.
3. **+1** if present: comment on the candidate with the new occurrence link.
   The comment body must **start with `Occurrence:`** — that marker is what
   the hygiene script counts; ordinary discussion never increments the count.
   Occurrence count = 1 (the filing) + N (`Occurrence:` comments).
4. **Promote** at count >= 2: run the Procedure below; the `retro:` PR closes
   the candidate with a comment linking the fix.

The monthly hygiene job surfaces candidates overdue for promotion.

## Classify the root cause, then pick the asset

| Root cause | Fix lands in |
|---|---|
| Agents lacked a fact or decision | `.github/docs/agreements/` (via the agreements PR process) |
| A rule existed only in someone's head or a review thread | `.github/instructions/*.instructions.md` or `AGENTS.md` (mind the tier — see `context-distillation` §Tiering) |
| A multi-step procedure was improvised inconsistently | a skill under `.github/skills/` (new or amended) |
| The brief allowed the mistake | `.github/ISSUE_TEMPLATE/ai-task.yml` or the planner quality bar |
| Nothing would have caught it automatically | a CI check / lint rule / test in `.github/workflows/` or the codebase |

Prefer the **most deterministic** asset that can host the fix: a CI check
beats an instruction line, because instructions are advice and checks are
walls.

## Source-template-only platform review

This repository is the source template for adoption. When the scaffold marker
reads `sha=unknown`, the monthly hygiene job may compare the kit's committed
checkpoint baseline against official Copilot platform URLs, but it must do so
only as a rendered audit. Upstream titles, URLs, and content are treated as
untrusted input: they are shown for inspection, never evaluated as fact, and
never interpolated into shell commands.

- The script compares official checkpoint values against the committed baseline
  file `.github/scripts/platform-capability-baseline.tsv` using the source's
  canonical URL and a deterministic kind (`title`, `rss_guid_date`, or a file
  hash kind such as `docs_sha` / `changelog_sha`). It never interprets a scraped
  title as a command, a policy, or a local truth source.
- A fetch failure, a missing authoritative value, a redirect away from the
  official source, or a non-authoritative source result is reported as `unknown`,
  and the committed baseline remains the keeper of the source-template truth.
- A value mismatch is `changed`; an exact match is `unchanged`.
- Changed rows render the source, the old and new values, the exact official
  URL, and the five-question checklist used to decide whether the baseline
  should advance or the local mechanism should retire. Baseline advancement is
  PR-only, and every changed source gets a one-line outcome in the PR: `adopt`,
  `retire local mechanism`, `watch`, or `not relevant`. This is the
  deterministic, engine-class counterpart to the earlier Rubber Duck/#68
  review-model seed: it is an official capability ledger, not a model summary or
  an AI-generated assessment.

## Procedure

1. Gather the evidence: links to the ≥2 occurrences (PR review threads,
   failed runs, issue comments).
2. Write the **smallest diff** that would have prevented the latest
   occurrence. Resist writing an essay; one sharp rule outperforms three
   vague ones.
3. Apply the **Budget rule** for always-on files (`AGENTS.md`,
   `copilot-instructions.md`): they must stay lean (target well under ~150
   lines each). When adding a line, look for a line to remove or demote to a
   scoped/on-demand tier. Unbounded growth of always-on context is how the
   system gets slowly worse while everyone follows the process.
4. Open a PR titled `retro: <what it prevents>`, containing the asset diff
   plus one appended row to `.github/docs/agreements/retro-log.md`:

```markdown
| 2026-07-03 | Cloud tasks kept claiming HIL criteria | verification skill + ai-task template: hardware criteria must defer to exec:ide follow-up | #142 #155 |
```

5. Human review approves — a retro PR changes how all agents behave, so it
   gets the same scrutiny as an agreement.

## Upstreaming project-agnostic fixes

When the root cause is scaffold-generic — it would bite any project built
from this template, not just this one — land the fix here first, then open a
matching PR on the scaffold **template repository** and prefix the retro-log
Fix cell with `[upstreamed]`. Project tunings (Sync Triangle content, globs,
layout maps) never go upstream. This closes the second improvement loop:
instances feed the template that future projects inherit
(`SCAFFOLD-CHANGELOG.md` documents versions and the upgrade path back down).

## Anti-patterns

- **Scar tissue rules**: encoding a one-off into always-on instructions.
- **Vague morals** ("be more careful with tests") — if it cannot change a
  concrete next action, it is not a fix.
- **Fix-without-log**: the retro-log row is what lets future hygiene passes
  see why a rule exists; a rule with no traceable origin cannot be safely
  removed later.
