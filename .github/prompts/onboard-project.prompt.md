---
mode: agent
description: Onboard/tune this scaffold to the current project — inventory, gap interview, run-verified commands, fill every CUSTOMIZE, deliver one evidence PR.
---

Follow `.github/skills/project-onboarding/SKILL.md` end to end.

Scope guard: tune the scaffold, verify commands, draft the Epic — never
implement application code or infrastructure. My application goals become
Epic content; anything that cannot run here becomes a deferred entry.

Optional context from me: ${input:notes}

1. **P0/P1:** preflight first — if the scaffold isn't reachable from the
   remote default branch (uncommitted, unpushed, or pushed only to another
   branch), ask my consent once, then land the adoption commit
   (`Adopt agentic-dev scaffold`) on the default branch yourself before
   anything else; no GitHub write happens before the scaffold is on the
   default branch. Run `.github/scripts/tuning-status.sh`, then inventory the repository
   read-only. Show me the inventory table (area → stack → candidate
   commands → confidence).
2. **P2:** interview me about hand-over only, in sequence: connector
   choice first (built-in chat flow default vs existing spec-kit
   workspace), then collect accordingly — the spec-kit workspace path,
   or my material via file paths, pasted text, or (where the surface
   supports it) files attached to a follow-up chat message.
   Wait for my answers and any material. Then close P2: bootstrap the
   canonical labels (`.github/scripts/setup-labels.sh`), ask my consent
   to enable branch protection now (state the admin PR-only bypass and
   Free-plan caveats) and run `.github/scripts/setup-ruleset.sh` per my
   answer, draft the phase Epics from my goal and material (one per phase,
   siblings never nested, `blocked-by` in order, coarse, draft-marked, no
   decomposition, `/breakdown-epic` pointer at the end of the first
   phase's body), and give me their URLs to review while you verify.
3. **P3:** verify candidate commands by actually running them; keep an
   evidence log (command, prerequisites, result, workarounds). Show me the
   log before applying anything.
4. **P4:** on my approval, apply — fill/remove every CUSTOMIZE across the
   Sync Triangle, fix `applyTo` globs, delete inapplicable example
   instructions, update the layout map, replace the CODEOWNERS template
   owner, activate the chosen context connector
   (`.github/scripts/setup-sources.sh`), seed provided docs into
   `.github/docs/context/` with provenance. Never touch `AGENTS.md`; never
   write agreements.
5. **P5/P6:** prove (`tuning-status.sh` exits 0; gates run once) and open
   one PR titled `scaffold: onboard <project>` with the evidence log in the
   description, plus the retro-log row and any upstream candidates. Append
   everything left undone in P0–P5 to the first phase Epic's body as a
   `## Deferred from onboarding` checklist (to the PR description when the
   Epics were skipped), and end the PR description with a `## Next steps`
   section (merge this PR → review the Epics → `/breakdown-epic` on the
   first phase). You are
   not done at push: the PR must exist (if its creation is blocked, tell me
   and print the exact `gh pr create` command), and the chat message where
   you hand me the PR link must end with the numbered handoff — 1. merge
   the evidence PR, 2. review the draft Epics (link them), 3. run
   `/breakdown-epic` on the first phase when it looks right. Queued or failing checks
   don't waive the handoff: report problems above it, never instead of it.
