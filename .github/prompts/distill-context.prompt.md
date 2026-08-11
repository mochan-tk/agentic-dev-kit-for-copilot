---
mode: agent
description: Distill raw material from .github/docs/context into an agreements PR (REQ-### / ADRs / glossary / non-goals) with tier placement.
---

Follow `.github/skills/context-distillation/SKILL.md`.

Topic directory to distill: .github/docs/context/${input:topic}

1. Read the topic's `INDEX.md` and flagged conflicts first, then the sources.
2. Draft candidates: requirements (next free `REQ-###` IDs), decisions
   (ADR drafts), glossary terms, non-goals — each linked to its source file.
   Apply the skill's promotion bar ("When an agreement is warranted");
   knowledge below the bar stays out and belongs in the Task issues that
   need it.
3. Present conflicts and judgment calls to me as options; do not resolve
   agreement-level conflicts yourself.
4. Assign each piece of knowledge a tier (always-on / scoped / on-demand) per
   the skill's tiering table, and include any instruction/skill file edits the
   tiering implies.
5. Open one PR on a branch `task/<issue-or-topic-slug>` containing the
   agreements diff + tier edits + provenance `status: distilled` updates,
   with a description listing every new/changed REQ/ADR and its source link.
