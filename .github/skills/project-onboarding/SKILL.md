---
name: project-onboarding
description: Tune this generic scaffold to a concrete target project — inventory the repo, interview only the gaps, verify every command by actually running it, fill or remove every CUSTOMIZE block, and deliver one evidence-backed onboarding PR. Use this whenever the scaffold lands in a new or existing project, whenever `.github/scripts/tuning-status.sh` reports markers, whenever commands in copilot-instructions are unverified or drift from CI, and whenever a user says "tune/onboard/set up this scaffold for project X".
---

# Project Onboarding

This scaffold ships generic on purpose: project truth is injected once, here,
by procedure — not sprinkled ad hoc. Onboarding succeeds when an agent that
knows nothing about the project can work from `.github/copilot-instructions.md`
alone and every stated command demonstrably runs.

Three invariants govern everything below:

- **The Sync Triangle.** `.github/copilot-instructions.md` (validated
  commands), `.github/workflows/ci.yml` (gates), and
  `.github/workflows/copilot-setup-steps.yml` (cloud-agent env) must state
  the *same* toolchain and commands. Any edit to one is an edit to all three.
- **Evidence or it does not land.** A command enters the Triangle only after
  it has been executed in a clean environment during this onboarding, with
  its output (or failure + workaround) captured for the PR.
- **Onboarding tunes; it does not build.** The deliverables are the tuned
  scaffold, the evidence PR, and the draft Epics — never application code or
  infrastructure changes. Application goals in the adopter's material are
  Epic content; work that cannot run here (missing tools, external systems,
  credentials) becomes a *Deferred from onboarding* entry (P6), not work to
  attempt in-session. P3 runs existing commands to verify them — it does
  not build what they are missing.

## Procedure

### P0 — Status

**Preflight: is the scaffold on the remote default branch?** The install
banner asks the human to commit, but nothing enforces it — and reaching the
remote default branch is a functional prerequisite, not etiquette: GitHub
Actions runs workflows only from the default branch, app/cloud sessions
branch from it and would see no scaffold at all, an uncommitted scaffold
bloats the P5 evidence PR beyond review, and activating branch protection
first locks the adoption commit out of the default branch. Fetch, resolve
the remote default branch, and test whether
`git log origin/<default> -1 --oneline -- .github/copilot-instructions.md`
prints a commit. Empty output means the prerequisite is unmet, in one of
three ways:

- never committed — `git log -1 --oneline -- .github/copilot-instructions.md`
  prints nothing;
- committed but unpushed — the branch has no upstream, or is ahead of it;
- pushed to a non-default branch — the commit exists, but
  `origin/<default>` cannot reach it (the case the two checks above miss:
  everything looks committed and pushed, yet Actions and sessions reading
  the default branch see nothing).

If any holds, ask one consent question — *"The scaffold isn't on the
default branch yet; land it there now? (recommended — onboarding builds on
it)"* — and on yes land the adoption commit
(`git commit -m 'Adopt agentic-dev scaffold'`; the installer left
everything staged) on the default branch yourself: on the default branch a
plain `git push`; on any other branch put the scaffold commit on a branch
cut from `origin/<default>` and push or PR-merge it to the default branch
immediately — never sweep unrelated commits along, and never defer it to
the P5 evidence PR. If the adopter declines, stop onboarding and note how
to resume (land the scaffold on the default branch, re-run
`/onboard-project`). If the push fails (no remote or no permission), record
the blocker; you may continue same-checkout onboarding only after saying
plainly that GitHub Actions, app/cloud sessions, and post-Epic task
execution stay broken until the scaffold reaches the default branch.
**No GitHub write — labels, ruleset, Epic — happens before the scaffold is
reachable from the remote default branch.**

Then run `.github/scripts/tuning-status.sh`. Exit 0 → already tuned; run in re-tune mode
(see Re-tuning) only if something changed. Otherwise the report is your
worklist.

### P1 — Inventory (read-only)

Detect before you ask. Scan for: manifests and lockfiles (`package.json`,
`pyproject.toml`/`requirements*.txt`, `go.mod`, `Cargo.toml`, `pom.xml`,
`platformio.ini`, `Dockerfile`, `Makefile`, `Taskfile*`), existing CI under
`.github/workflows/`, test directories and runners, formatters/linters
configs, monorepo workspaces, and hardware markers (board envs in
`platformio.ini`). Produce an inventory table: area → stack → candidate
build/lint/test commands → confidence. Facts the repository cannot answer
(no manifests, no version files) are recorded as "none found" — never
turned into interview questions. Firmware target envs are judged from the
markers above; which machine physically hosts devices is discovered when
routing first needs it (`exec:ide`), not interviewed up front.

### P2 — Interview (hand-over only)

The interview covers one topic: **how specification and design material
reaches the scaffold**. Everything else about the repository is
discovered by P1/P3 or when work first needs it — path restrictions are
declared per task in File ownership at decomposition time, secrets
specifics surface when work first touches them (baseline guardrails
already ship in the instructions), and the Projects roadmap board is
offered by the first `/breakdown-epic` run (consent-gated), not
interviewed up front. Every
question must be answerable by a project owner without digging through
the repository.

Ask in sequence, second step branching on the first answer:

1. **Connector choice.** How should specification or design material be
   handed over — through the built-in chat flow (default, needs no
   setup), or by adopting an existing spec-kit workspace already in this
   repo? "Don't know" is a safe answer — it means the default. *(This
   picks a context connector — activation happens in P4, not here.)*
2. **Material intake.**
   - *Spec-kit*: confirm the workspace P1 found (name the directory), or
     ask for its path.
   - *Default*: invite the material — requirements documents, design
     notes, meeting minutes, existing docs. The adopter can give file
     paths or paste text into the answer; on surfaces that support file
     attachments, files can also be attached to a regular chat message
     **after** answering. The question dialog itself takes only a choice
     or typed text — never imply it accepts uploads. Markdown is
     preferred, any readable text works (binary formats are out of
     scope). It will be stored as raw reference material for future
     planning. Extend this invitation unconditionally. When the adopter
     says yes, wait and receive the material (path, pasted text, or
     attachment) before leaving P2. Documents already committed to the
     repository are not part of this question — P1's inventory names
     them and agents read them in place.

   *(Ask in plain form — no scaffold jargon, no scaffold paths, and no
   landing mechanics (copy vs move vs reference index) in the questions
   or the choices; landing is the P4 seed step, not the adopter's
   problem.)*

**Close P2 before starting P3** — verification is the long stretch, so
give the adopter something to review during it:

1. Run `.github/scripts/setup-labels.sh` (idempotent; the installer never
   writes to GitHub — this is where the canonical label set is
   bootstrapped). Record its output in the evidence log.
2. Ask the branch-protection consent question — one question, three
   choices — then act on the answer immediately with
   `.github/scripts/setup-ruleset.sh` (idempotent: it promotes an
   existing same-name ruleset's enforcement instead of duplicating).
   The question text must state both caveats: repository admins keep an
   explicit, audited *pull-request-only* bypass button (that is how a
   solo adopter merges their own PRs — self-approval is impossible —
   while direct pushes stay blocked), and private repositories on a
   Free plan are refused by the rulesets API.
   - **Enable now** (recommended) — run with `--enforcement active`.
   - **Create disabled, review later** — run with the default; enabling
     happens in Settings → Rules → Rulesets or by re-running with
     `--enforcement active`.
   - **Skip** — run nothing; note the command for later.
   Record the choice and the script output in the evidence log. An API
   refusal (Free-plan private repo) is recorded the same way and never
   blocks onboarding.
3. Draft the **phase Epics** on GitHub from the stated goal and the
   handed-over material, using the Epic form fields (outcome, success
   criteria, scope, coarse phase outline) — one Epic per phase of the
   outline, as siblings; an Epic is never a sub-issue of another Epic. A
   one-phase outline yields exactly one. Wire them `blocked-by` in phase
   order, since ordering lives in dependencies, not prose. Keep every Epic
   coarse — no Task decomposition, no invented REQ-### IDs; cite
   handed-over documents by name. Open each body with a draft marker:
   *"Draft from onboarding — review and edit freely; nothing is decomposed
   until you approve."* End the **first phase's** body with the next-move
   pointer: *"When this Epic looks right, run `/breakdown-epic` on it."* —
   the pointer rides in the body because the closing chat handoff may never
   reach whoever picks the Epic up. Later phases stay coarse until their
   turn and say so instead.
4. Hand the adopter every Epic URL, first phase first, with: review these
   while I verify.

Skip the drafts (labels and the consent question still run) only when the
adopter stated no goal and handed over nothing — then note the Epic form
for later.

### P3 — Verify by running

In a clean checkout, execute candidate commands in dependency order. Record
for each: exact command, environment prerequisites, runtime, result. Failures
are content: capture the error and the working workaround — these notes go
into copilot-instructions so no agent rediscovers them. Never promote an
unrun command.

### P4 — Apply

- Fill every `CUSTOMIZE` block in the Triangle files with P3-verified
  content; delete the placeholder steps/warnings they replace.
- Area instructions: fix `applyTo` globs; delete inapplicable examples
  (e.g., `firmware.instructions.md` when there is no firmware); add one
  `.instructions.md` per detected area that has real rules (one concern per
  file).
- Repository layout map in copilot-instructions: make it match reality.
- `.github/CODEOWNERS`: replace the template owner with this project's
  user or team on every rule (clearing its `CUSTOMIZE:` sentinel) — a
  copied file that still names the template author cannot gate reviews.
- Run `.github/scripts/setup-sources.sh` to activate the connector chosen
  in P2 step 1 (records it in the SOURCES.md registry); `/kickoff-context` is
  the follow-on that lands future context through it. Skip only when the
  adopter kept the default and no spec-kit workspace exists — then note
  the wizard can be run later.
- Seed material handed over in P2 step 2 into `.github/docs/context/<topic>/`, landed
  as Markdown with provenance headers (`context-collection` skill),
  whatever form it arrived in (path, pasted text, attachment).
  Repo-resident documents are **not** copied into `.github/docs/context/` — they
  stay in place and are read where they live. Do **not**
  write agreements — distillation is a separate, human-gated phase.
- Do **not** touch `AGENTS.md` (Budget rule; behavior is project-independent).

### P5 — Prove

`.github/scripts/tuning-status.sh` exits 0; the new CI gates run green once end to
end (or documented-red with a linked issue); `copilot-setup-steps.yml`
executes via its own workflow_dispatch. Definition of tuned = all three.

### P6 — Record

One PR titled `scaffold: onboard <project>`: the Triangle diffs, the
inventory table, the interview answers, and the P3 evidence log in the
description. Append a `.github/docs/agreements/retro-log.md` row (failure class:
`onboarding`). List any project-agnostic improvements you noticed as
upstream candidates (see the retro skill, Upstreaming).

Then write the **Deferred from onboarding ledger**: collect every item
left undone or unverified across P0–P5 — commands that could not run
(missing tools), external operations (pushes, deploys, credentials,
resource provisioning), skipped or declined consent steps — and append
them to the **first phase Epic's** body as a `## Deferred from onboarding`
section, one checklist line each with the blocking reason — the ledger is
about onboarding, so it rides the Epic that is ready to move, not every
phase. When the Epics were skipped, carry the same section in the evidence
PR description instead.
Chat is not a carrier: a deferred item that exists only in the final
message evaporates with the session.

P6 is not complete when the branch is pushed — it is complete when the
**evidence PR exists**. If PR creation is blocked (approval gate, missing
permission), say so explicitly and print the exact `gh pr create` command
for the adopter instead of ending the turn silently. Either way, the chat
message that announces the evidence PR (its URL, or the blocked-PR
command) ends with the **closing handoff** — this numbered block, links
filled in. Queued checks, CI failures, or other problems do not waive it:
report them *above* the block, never instead of it.

1. Review and merge the evidence PR (the license merge).
2. Review and edit the P2-close draft Epics — link them here, first phase
   first (or say they were skipped and point at the Epic form).
3. When the first phase's Epic looks right, run `/breakdown-epic` on it —
   decomposition into Task issues starts only on your approval, one phase
   at a time; each ready Task then runs via `/start-task`.

The same three moves ride durable carriers: the evidence PR description
**ends with a `## Next steps` section**, and the first phase Epic's body
already carries its `/breakdown-epic` pointer (P2-close). Durable copies exist
because chat can die; the chat block exists because adopters read chat,
not PR descriptions — neither substitutes for the other, and a PR
announcement without the block is an unfinished P6. This checklist lives
here, not in conversation memory, precisely so a compacted session still
finishes the ritual.

## Existing codebases (the legacy path)

Onboarding an existing codebase follows P0–P6 unchanged — but the first work
order *after* onboarding is **characterization tests, not a feature**: fix
the current behavior of the areas agents will touch (approval/golden-master
style where no spec exists). Automated checks are the ceiling on agent
autonomy (verification skill), so each characterization test widens the
delegable license; areas without one stay routed `exec:ide` until the wall
exists. Put this recommendation into the P2-close draft Epic (as its first
phase or a sibling draft) and restate it in the onboarding PR.

## Re-tuning

Re-run P1→P6 (scoped to the delta) when: a new manifest/lockfile type
appears; CI and copilot-instructions disagree; `copilot-setup-steps` fails
for the cloud agent; or a retro identifies stale commands. Drift between the
Triangle files is itself a retro trigger.

## Must NOT

- Invent agreements, requirements, or ADRs.
- Weaken or delete existing gates to make onboarding "pass".
- Leave a command in the Triangle that was not executed in P3.
- Introduce non-English durable artifacts.
