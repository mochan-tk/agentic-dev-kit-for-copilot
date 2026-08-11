---
mode: agent
description: Start work on a Task issue following the child-session start ritual (read brief, load references, plan.md, claim the issue).
---

Follow the child session protocol in
`.github/skills/session-orchestration/SKILL.md`.

Task issue number: ${input:issueNumber}

1. `gh issue view ${input:issueNumber}` — read the complete brief.
2. Open every referenced agreement/REQ/ADR. If anything is missing or
   contradictory, stop and raise it with me instead of guessing
   (Ambiguity rule, `AGENTS.md`).
3. Restate back to me, briefly: the acceptance criteria, the File-ownership
   paths, and the Verification commands — so we both confirm the same
   understanding of "done".
4. Create branch `task/${input:issueNumber}-<short-slug>` (in a fresh worktree
   if other tasks run in parallel), write `plan.md` (session cache — do not
   commit), and comment on the issue that work is starting with the
   session/branch reference.
5. Then begin, staying strictly inside the ownership paths.
