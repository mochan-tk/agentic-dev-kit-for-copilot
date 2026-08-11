---
mode: agent
description: Mine recent PRs, reviews, and failed runs for repeated failure patterns and turn the top ones into a small `retro:` PR.
---

Follow `.github/skills/retro/SKILL.md`.

Lookback window: ${input:lookback} (e.g., "last 20 merged PRs" or "last 2 weeks")

1. Collect signals in the window: rejected/heavily-revised agent PRs, review
   comments that repeat across PRs, CI failures with the same cause, and
   entries flagged as retro candidates in reviews.
2. Cluster into failure classes; keep only classes with **≥2 occurrences**
   (or any single incident-grade event).
3. For the top 1–3 classes, classify the root cause and pick the most
   deterministic asset that can host the fix (CI check > instruction >
   skill), per the skill's table.
4. Show me: each class, its evidence links, the proposed smallest diff, and —
   for always-on files — what you propose to remove or demote to respect the
   Budget rule.
5. On approval, open one PR titled `retro: <what it prevents>` containing the
   asset diffs plus the appended rows in `.github/docs/agreements/retro-log.md`.
