# Scaffold Changelog & Lineage

This is the **source repository** for the agentic-dev kit. Adopting
repositories install it with `.github/scripts/scaffold-init.sh`; this file
tracks the kit's own version history and how instances move between
versions. In an instance, this same file records which version the instance
adopted. The project's own changelog, if any, lives elsewhere — this file is
about the scaffolding only.

Convention: cite issues of *this* repository as a bare `#<n>`. Never carry a
bare number over from another repository — a bare `#<n>` always resolves
here, so an inherited number silently links to an unrelated issue.

<!-- scaffold-version: repo=mochan-tk/agentic-dev-kit-for-copilot sha=unknown date=unknown -->
**Scaffold version adopted by this instance:** v1.0.0 *(this is the template
itself; in a copied instance, update this line when upgrading — the
onboarding PR should confirm it)*

## Upgrading an instance

1. On a branch in the adopted repository, re-run the installer with
   `--upgrade` (one-liner: `curl -fsSL <raw-url>/scaffold-init.sh | bash -s -- --upgrade`;
   pin the source with `SCAFFOLD_REF=<tag|sha>`). Scaffold-owned machinery
   (`.github/scripts|skills|agents|prompts|ISSUE_TEMPLATE/**`, the PR
   template, this changelog) is refreshed in place; tuned surfaces
   (`copilot-instructions.md`, `workflows/`, `CODEOWNERS`,
   `instructions/`, `AGENTS.md`) and `.github/docs/**` are kept and
   listed. Preview with `--upgrade --dry-run`.
2. Review the staged diff (`git diff --cached`) and this changelog's
   entries since your adopted version; port anything the kept files
   need by hand — upgrades change procedures and templates, not your
   project truth.
3. Re-run `.github/scripts/tuning-status.sh` and the CI gates.
4. Land as one PR titled `scaffold: upgrade to vX.Y.Z`; append a
   `.github/docs/agreements/retro-log.md` row (class `scaffold-upgrade`).

## Upstreaming (instance → template)

When a retro fix is project-agnostic, open a matching PR on the template
repository and mark the retro-log Fix cell `[upstreamed]` — see
`.github/skills/retro/SKILL.md`, Upstreaming. That is how future projects
inherit what this one learned.

## Versions

### Unreleased

- The onboarding evidence PR no longer fails the `task-ritual` wall. The wall
  demands every PR link a Task issue carrying a start claim and a plan
  comment, but during onboarding no Task exists — the PR *is* the deliverable
  — so every adopter hit a red check on their very first PR and could only
  merge by bypassing it. The wall now exempts that PR when three signals
  agree: the skill-mandated title `scaffold: onboard <project>`, a base
  branch whose scaffold-version marker names a real commit (so the template
  repository itself cannot claim it), and a base that still carries CUSTOMIZE
  markers. The last two make the exemption self-limiting — it holds at most
  once per adopting repository and lapses the moment onboarding merges.
  Separately, the task-link extractor now tolerates a qualifier between
  keyword and number, so the accurate `Refs Epic #2` parses (refs #16).

- Issue references in this changelog no longer mis-resolve. GitHub resolves
  a bare `#<n>` against the repository the file lives in, so the numbers
  inherited from where this kit was developed did not go dead — they linked
  to unrelated issues here, and would have gone on colliding as numbering
  grew into their range. Those citations are dropped (the prose already says
  what changed); references to this repository's own issues stay. A new
  guard, `check-changelog-refs.sh`, fails CI on any bare number above this
  repository's known range, and the changelog header states the convention
  (refs #14).

- The adoption instructions now name skills first: prompt files under
  `.github/prompts/` are a VS Code Copilot Chat feature, so `/onboard-project`
  is not a command in a Copilot app session or in Copilot CLI — it arrives as
  plain text and works only if the model infers a skill was meant. Skills are
  the portable layer (an open standard loaded by VS Code, Copilot CLI, and the
  cloud agent alike), and `.github/skills/project-onboarding/SKILL.md` already
  carries every instruction the prompt does, so nothing is lost by pointing
  adopters at it. The install banner, README steps 2 and 6, the repo map, and
  the Epic template now read "run the `<name>` skill (in VS Code: `/<shortcut>`)";
  the prompt files keep working unchanged for VS Code users (refs #12).

- The install banner now shows a push command that works on the app-session
  path. It previously printed a bare `git push`, which assumes the adopter
  is on the default branch with an upstream configured — neither holds in a
  Copilot app worktree session, where the command fails outright ("no
  upstream branch") and, even when it succeeds elsewhere, pushes to a branch
  Actions never read. Step 1 now states the goal (land the scaffold on the
  remote default branch), prints `git push origin HEAD:<default>` with the
  branch name resolved locally from `origin/HEAD` (placeholder when it
  cannot be resolved), and names the protected-branch alternative in one
  clause (refs #10).

- The install banner now tells adopters to **push**, not just commit. Step
  1 named only `git commit`, so an adopter who followed it literally left
  the scaffold off the remote default branch — where Actions never run,
  breaking label bootstrapping and onboarding mid-flight. The banner now
  names both commands, says why the push matters, and makes clear that
  `/onboard-project` can do both if you skip them; a regression test keeps
  the wording from drifting back (refs #8).

- The README Conventions label list is complete again: it named nine of the
  twelve labels `setup-labels.sh` creates. The three that were missing are
  now covered in the same bullet — `risk:high` (described by its effect:
  pauses a task after its plan comment until a human approves, where the
  default is pass-through), `retro:candidate`, and `from:adopter`. An agent
  reading only the README could not previously know the `risk:high` lever
  existed (refs #3).

- The "Use this template" adoption path is dropped; the installer is the
  single way in and the repository stays non-template. The template path
  copied the whole tree with no filter — this kit's own development
  records (`docs/`, 15 files), its `LICENSE`, `.vscode/`, `.devcontainer/`
  and the full changelog — none of which the installer ships. A brand-new
  repository is still fully served: `git init`, then run the installer
  (refs #1).

- The top-of-README adoption banner is deleted: readers scan for Getting
  started directly, and the banner dual-maintained both the install
  commands and the onboarding journey. Install commands now appear exactly
  once (step 1, restoring the single-carrier principle and superseding
  the "banner stays" note); the journey lives in Getting started,
  where step 2 (Onboard) now points at reviewing the drafted Epic and
  running `/breakdown-epic` (full flow stays in step 6); `gh auth login`
  was already covered by Prerequisites.

- Getting started step 1 inlines both installer one-liners (sh +
  PowerShell) instead of pointing readers back to the top banner ~150
  lines away; the banner stays for repo-page visitors. Supersedes that
  aspect of the dedup: the install commands intentionally appear in
  both places.

- README Getting started is restructured for scannability: every step (and
  the Platforms note) now opens with a bold verb-first lead sentence and
  carries its details as short bullets instead of running prose — all six
  steps, every fact, both `--upgrade` code blocks, and each *Done when:*
  line are preserved.

- The README's duplicated guidance is collapsed into single authoritative
  locations: the banner carries the install one-liners (Getting started
  step 1 now references it), the Platforms paragraph carries the Git
  Bash/WSL warning, and step 1 carries the "Use this template copies the
  whole tree" note — and the `--upgrade` re-run gains a copy-pastable
  bash code block beside the existing PowerShell one, which was lost when
  Windows support was added (334 → 302 lines, no facts
  removed). A full README-vs-reality audit in the same change fixed two
  stale repo-map notes: the CODEOWNERS line now lists all three guarded
  paths (agreements/, workflows/, connectors/) and the setup-ruleset.sh
  line points at the step-4 gates (the ruleset moved from step 5 to
  step 4 when Getting started was renumbered).

- The onboarding closing handoff is now bound to a concrete trigger: the
  chat message that announces the evidence PR must end with the numbered
  handoff block, and problems (queued or failing checks, blockers) are
  reported above the block, never instead of it (from adopter feedback
  adopter re-validation — the durable carriers from the earlier hardening
  worked, but the chat message announced the PR plus CI status and
  dropped the handoff again: "final message" was undefined, "courtesy
  copy" read as optional, and the problem report crowded out the ritual).
  The `/onboard-project` prompt mirrors the trigger.

- The README quickstart banner now names `/breakdown-epic` as the concrete
  move after reviewing the drafted Epic (from adopter feedback — the
  command was only named deep in Getting started, so an
  adopter whose onboarding session ended without the closing handoff had
  no visible path from the Epic to Task issues; the banner is the one
  carrier that does not depend on agent compliance).

- Onboarding now produces durable outputs instead of chat-only ones (from
  adopter feedback — an onboarding run drifted into
  implementing application code, ended without the closing handoff, and
  its undone items evaporated with the session). The skill gains a third
  invariant ("onboarding tunes; it does not build"), a
  `## Deferred from onboarding` ledger appended to the draft Epic body
  (evidence PR description when the Epic was skipped), a mandatory
  `## Next steps` section closing the evidence PR description, and a
  `/breakdown-epic` pointer written into the draft Epic body itself; the
  `/onboard-project` prompt mirrors all three.

- `setup-project.sh init` now detects a **closed** same-title board before
  creating anything (from adopter feedback —
  `gh project list` hides closed projects, so a closed roadmap board was
  invisible to the reuse path and init would create a duplicate, or
  dead-end in orgs that refuse API creation). Init exits with the exact
  reopen command instead of mutating a board a human closed, and the
  terminal failure message now carries the adopter-validated recovery:
  where an org/enterprise silently refuses `createProjectV2` while the
  web UI works, create or rename a board to the exact title and re-run
  init to have fields and the repository link completed.

- `setup-project.sh init` no longer trusts gh's project number blindly
  (from adopter feedback — on Windows,
  `gh project create` answered with number `0`, which gh's own project
  commands treat as "no number supplied", so a successfully created
  board cascaded into a `field-list` failure and was left without
  fields or the repository link): a number that is not a positive
  integer is re-resolved by exact-title lookup, both paths are
  validated before any follow-up command, and the remaining failure
  mode exits with the owner, the title, and the recovery. The header's
  gh requirement now reads `>= 2.45` (`gh project link`) instead of the
  impossible `2.95`.
- The roadmap board gains an owner (from adopter feedback — "attach any
  time later" had no owner: onboarding deferred
  it, the breakdown prompt never mentioned it, and plan-management even
  mandated date spans at decomposition against a board nothing created):
  the first `/breakdown-epic` run now checks for the board and offers
  `setup-project.sh init` with one consent question, sets the created
  Tasks' schedule spans where dates are known, and records the outcome
  in the Epic summary comment; the scheduling obligation is now
  conditional on the board existing, and onboarding P2 defers to that
  owner explicitly. A decline or a missing `project` scope
  (`gh auth refresh -s project`) never blocks decomposition.
- Onboarding P6 gains a closing handoff (from adopter feedback — a real
  run ended at "pushed, PR not created" after
  context compaction, leaving the adopter with no next move): P6 now
  completes only when the evidence PR exists (a blocked creation must
  be stated with the exact `gh pr create` command), and the final
  message must hand the adopter their next moves — merge the evidence
  PR, review the linked draft Epic, run `/breakdown-epic` on it to
  start decomposition (a follow-up named the triggers: the handoff originally
  said only "say the word", which left `/breakdown-epic` and
  `/start-task` undiscoverable).
- The Windows `--upgrade` invocation is now documented (README and the
  `scaffold-init.ps1` header, from adopter feedback): plain `irm … | iex`
  cannot forward flags, so upgrades use the script
  block form `& ([scriptblock]::Create((irm <raw-url>))) --upgrade` —
  the shim already forwards arguments; only the documentation was
  missing.
- Onboarding P0 gains a commit preflight: an uncommitted or unpushed
  scaffold is detected before anything else, and after one consent
  question the agent commits (`Adopt agentic-dev scaffold`) and pushes
  it itself (from adopter feedback — the manual
  banner step was a functional prerequisite with no guard: app/cloud
  sessions see no scaffold at all, the evidence PR bloats, and early
  branch-protection activation locks the adoption commit out). No
  GitHub write (labels, ruleset, Epic) happens before the push; the
  install banner now says onboarding offers to commit for you. A follow-up
  tightened the check to the real prerequisite — the scaffold must be
  reachable from the remote *default branch*, not merely pushed (from
  adopter feedback: a real run landed the adoption commit on a
  feature branch, both legacy checks passed, and GitHub Actions later
  failed mid-flight because the default branch had no scaffold) — and
  the remedy now lands the commit on the default branch immediately,
  never deferring it to the evidence PR.
- The installer gains `--upgrade`: adopted repositories can now pull
  scaffold updates without hand-diffing (from adopter feedback — the
  previous choice was refuse-or-`--force`, and
  `--force` flattens tuned files, so adopters stayed frozen at their
  adopted version). On collision, scaffold-owned machinery (scripts,
  skills, agents, prompts, issue/PR templates, this changelog) is
  refreshed in place while tuned surfaces (`copilot-instructions.md`,
  `workflows/`, `CODEOWNERS`, `instructions/`, `AGENTS.md`) and
  `.github/docs/**` are kept and listed; absent files install in every
  class, so new machinery still arrives. `--upgrade --dry-run` previews
  the class-labeled plan; `--upgrade --force` is a usage error; the
  provenance lines stack and the version marker stays single. A
  dedicated upgrade banner hands off diff review, changelog porting,
  re-verification, and the one-PR landing.
- Onboarding P2-close now asks one branch-protection consent question and
  runs `.github/scripts/setup-ruleset.sh` per the answer — the manual
  "run the script, then enable it in Settings → Rules → Rulesets" step
  most adopters never performed is gone from the handoff (from adopter
  feedback). The installer banner shrinks to two
  next steps (commit → onboard). The script now promotes an existing
  same-name ruleset's enforcement in place (partial-body PUT, verified
  live — rules/conditions/bypass untouched) instead of skipping, and
  the shipped payload grants repository admins a *pull-request-only*
  bypass (actor_id 5, verified live): a solo adopter cannot approve
  their own PRs, so without it activation would deadlock the repository
  on its own onboarding PR; direct pushes stay blocked for everyone.
  Free-plan private repositories are refused by the rulesets API — the
  refusal is recorded in the evidence log and never blocks onboarding.
  New offline guard suite `test-setup-ruleset.sh` pins the payload, the
  skip, the promotion, the write-free dry-run, and the fail-loud list.
- Onboarding now closes P2 by bootstrapping the canonical labels and
  drafting a coarse outline Epic from the adopter's goal and handed-over
  material, handing its URL over for review **while** P3 verification
  runs — from adopter feedback: verification is the long
  stretch and the adopter previously waited idle, with the first Epic
  sequenced entirely after onboarding. The Epic stays draft-marked and
  undecomposed (rolling-wave; no invented REQ-###s); the label bootstrap
  moved out of P4; quick-adopt step ③ becomes "approve the drafted Epic
  (or file your own)"; the legacy path's characterization-tests
  recommendation now targets the draft Epic and is restated in the PR.
- The "register repo-resident docs?" interview question is gone, from
  adopter feedback: its answer was always the recommended
  choice, so it gathered nothing only a human knows. Documents already
  committed to the repository are no longer registered into
  `.github/docs/context/` at all — P1's inventory names them and agents
  read them in place; only handed-over (external) material lands in
  context/. The unconditional hand-over invitation is unchanged.
- Material-intake wording no longer promises an upload control the
  question dialog lacks, from adopter feedback: the
  onboarding invitation now leads with the two universal channels —
  file paths and pasted text — and frames attachments as a
  surface-conditional follow-up sent in a regular chat message after
  answering; interviewing agents are told the dialog itself takes only
  a choice or typed text.
- Label bootstrap folded into onboarding, from adopter feedback: the
  manual "Bootstrap labels" step is gone from the installer's
  handoff banner (now three steps: commit → onboard → ruleset) and from
  README's quick-adopt and Getting-started paths. `/onboard-project`
  already ran `setup-labels.sh`; the onboarding skill now runs it
  unconditionally (it is idempotent) and records the output as evidence.
  The installer stays local-write-only, and `setup-labels.sh` remains
  available for standalone use (`-R owner/repo`).
- CRLF landmine defused, from adopter feedback: the template
  now ships a root `.gitattributes` pinning scaffold paths (`.github/**`
  and the root scaffold files) to LF, and the installer seeds it like
  `README.md`/`.gitignore` (kept untouched when the target already has
  one). A Windows checkout with `core.autocrlf=true` can no longer
  rewrite the bash scripts to CRLF — which breaks them under Git Bash —
  and the `LF will be replaced by CRLF` warning flood during install is
  gone (regression-tested with `core.autocrlf=true`). Existing instances:
  copy the template's `.gitattributes` to your repository root and commit
  it before any branch switch.
- Windows handoff, from adopter feedback: when the installer runs under
  an MSYS shell (Git for Windows exports `MSYSTEM`), the closing banner
  now appends a note to run the `bash ...` next steps inside Git Bash —
  plain `bash` typed into PowerShell may launch the WSL launcher, which
  lacks the user's `gh` login. POSIX banner output is unchanged, and
  README's quick-adopt note and "Bootstrap labels" step now say the same.
- Install progress and speed, from adopter feedback: `scaffold-init.sh`
  prints one plain status line per phase (resolving the ref, downloading
  and unpacking, file plan, installing with file count, staging) instead
  of minutes of silence, and the per-file `dirname`/`mkdir`/`cp` install
  loop is replaced by one `mkdir -p` plus a single `tar` pipe — ~250
  process spawns down to ~3, the dominant cost on Git Bash (MSYS) under
  corporate antivirus. `--dry-run` output is unchanged; no terminal
  control codes, so piped output stays clean.
- Windows install: the repo-root guard in `scaffold-init.sh` no longer
  compares the shell's `pwd -P` to `git rev-parse --show-toplevel` — on
  Git Bash those spell the same directory differently (`/c/...` vs
  `C:/...`), so the documented PowerShell one-liner refused at the real
  repository root. The guard now uses `git rev-parse --show-prefix`
  (empty exactly at the root), and the previously uncovered
  subdirectory-refusal case gained a regression test. From adopter
  feedback.
- Interview is now hand-over only, from adopter feedback: the last
  three non-hand-over questions (forbidden paths, secrets policy, org
  board) are deleted — path limits are per-task File ownership, secrets
  specifics are discover-when-needed, boards attach any time via
  `setup-project.sh` — and the remaining flow is sequenced instead of
  batched: connector choice first, then material intake branching on
  the answer (spec-kit → workspace path; default → chat attachments /
  paths / pasted text, with the register/skip add-on for repo-resident
  docs). `/onboard-project` step 2 reworded to match; the ≤10 bank cap
  is gone.
- Interview bank cut to owner-only questions, from adopter feedback:
  the four infrastructure questions (active vs frozen areas, trusted
  build/lint/test commands, firmware envs/device host, runtime pins)
  are deleted — facts the repo could answer belong to P1/P3, absent
  signals are recorded as "none found", firmware envs are auto-judged
  and the device host is discovered at routing time; the spec
  hand-over invitation (attach in chat / file paths / paste) is now
  extended unconditionally — the register/skip question for
  repo-resident docs is additional, never a replacement — and the
  interviewer receives handed-over material before leaving P2.
  Bank shrinks 9 → 5.
- README "Getting started" step 1 now shows the Windows (PowerShell)
  one-liner next to the `curl` forms — the intro blockquote had it
  since the fix, but the step-by-step guide did not.
- Onboarding question bank revised from adopter feedback, three items
  from one interview: repo-resident docs found by P1 now get a plain
  register/skip question — landing mechanics (copy vs reference index)
  and scaffold paths are banned from question and choices;
  the two hand-over questions share one term, existing vs *future*
  "specification or design material"; the CI/cloud-agent
  constraint questions are deleted — P3 measures gate behavior
  empirically and runner sizing is discover-when-needed. Bank shrinks
  11 → 9.
- Agent-mediated installs no longer lose the handoff: the installer
  banner now addresses an installing AI agent directly — relay the
  next steps to the human and offer to run `/onboard-project` — so the
  guidance survives when the one-liner is executed as a tool call
  from a chat instead of a human terminal. Adopter feedback.
- Onboarding now wires in context connectors: P2 gains a connector
  question (Q10 — built-in interview default vs existing spec-kit
  workspace, "don't know" safe), P4 activates the choice via
  `.github/scripts/setup-sources.sh` and points at `/kickoff-context`
  as the follow-on; `/onboard-project` step list mentions the
  activation. Closes the Epic integration seam reported by adopter
  feedback.
- gh authentication preflight: `setup-labels.sh` and `setup-ruleset.sh`
  now probe `gh api user` up front and fail with `run: gh auth login`
  before doing any work (previously they died mid-run on the first API
  call). The installer treats a present-but-unauthenticated `gh` exactly
  like gh-absent — resolution and tarball fetch fall back to
  `git ls-remote` + codeload, so public adoption works logged-out; fetch
  errors now hint that private sources need `gh auth login`. README
  adoption steps gain step ⓪ (authenticate once). Adopter feedback.
- Onboarding interview: context-intake question (P2 Q9) reworded into
  adopter language — asks for specification/design material, names the
  intake paths (chat attachment, file path, pasted text) and format
  guidance (Markdown preferred); landing mechanics stay in the P4 seed
  step. First adopter-feedback-driven change.
- Windows adoption path: new `.github/scripts/scaffold-init.ps1` bootstrap
  locates Git Bash (standard Git for Windows locations, then `PATH`;
  the WSL launcher is skipped) and re-executes the canonical bash
  installer through it — arguments forwarded, exit code propagated;
  SHA pinning and all safety logic stay in the bash script, the single
  implementation. README documents the PowerShell one-liner; all other
  scaffold scripts run inside Git Bash or WSL.

### v1.0.0 — 2026-08-09

First public release. A generic, Copilot-native template for the agentic
development lifecycle: GitHub issues, pull requests, and committed files
are the only shared memory; human judgment concentrates at dispatch and at
the Three Merges; everything between is designed to run without a human in
the loop.

- Constitution and context tiers: `AGENTS.md` (§1–§9: persistence,
  record-before-report, verify-before-done, unit of work, single-writer,
  ambiguity, rolling-wave planning, English-only, start ritual), always-on
  `copilot-instructions.md`, path-scoped instruction files, and on-demand
  skills.
- Eight skills with scripts and canonical templates: context-collection,
  context-distillation, plan-management (frontier + new-task helpers),
  task-routing, session-orchestration, verification, retro, and
  project-onboarding.
- Proportional agreements: a promotion bar (`context-distillation` skill)
  decides what becomes reviewed truth — most knowledge rides in Task
  issues; substantive agreement changes get a dedicated PR, declared
  wording riders ride the implementation PR.
- Work orders as an issue graph: Epic/Task issue forms mirrored by body
  templates; test-first acceptance criteria (executable checks land before
  implementation — the wall judges, not the account); the tracking graph
  (sub-issue, blocked-by, `#N`, `Closes #N` — `Refs #N` for post-merge
  acceptance) with one-line origin citations; the working plan lands as a
  Task-issue comment before implementation; work-order body edits require
  a change comment.
- Session protocol: start ritual with claim and plan comments; crash-only
  resume (position from ledger + ground truth; orphan detection is the
  parent's duty); three doors for intervening in a running task with a
  `risk:high` gate for the exceptions; four-quadrant diagnosis (work order
  / plan / diff / evidence); an escalation ladder whose failure budgets
  are defined once, in the normative skills.
- Two-tier task execution (ADR-0003): a Task issue may run as a
  supervisor + worker pair — the supervisor dispatches, steers, and
  independently verifies; the worker implements. Every Task declares its
  execution mode on the ledger: a `Dispatching worker` / `Releasing
  worker` comment trail, or a small-task exemption phrase in the plan
  comment. Session teardown is leaf-first (workers before their
  supervisor), and the session-orchestration skill carries the full
  protocol: kickoff completeness, report hops as pointers, ground-truth
  verification of worker claims.
- Three custom agents (planner, orchestrator, reviewer) with pinned
  `tools:` restrictions; `exec:cloud` dispatch by assigning the issue to
  the Copilot coding agent; `copilot-setup-steps.yml` preinstalls the wall
  toolchain for cloud sessions.
- Deterministic CI walls: quality (SHA-pin enforcement, escalation-wording
  check, tuning status), scaffold-self-check (pinned shellcheck +
  actionlint, template-sync, Markdown path references, dev-container
  validation), copilot-surface (strict-YAML frontmatter, size ceilings,
  English-only), task-ritual (claim + plan comments in chronological
  order, plan-before-code, comment immutability, plan-link integrity,
  execution-mode declaration), connectors conformance, and a monthly
  retro-hygiene report — backed by an offline guard-test harness
  (12 suites) that pins every wall's behavior with negative proofs.
- Supply chain: every action pinned to a full commit SHA with an enforced
  `# vX.Y.Z` end-of-line comment; sha256-verified tool downloads;
  `persist-credentials: false` on all checkouts.
- Two adoption paths: `curl -fsSL …/scaffold-init.sh | bash` installs the
  scaffold-owned set at any repo root (write-free `--dry-run`, symlink
  refusal, SHA-resolved fetches, `**Adopted:**` provenance under the
  machine-readable scaffold-version marker in this file), or GitHub
  "Use this template" for brand-new repos.
- Pluggable context connectors (ADR-0001): the collect → distill layer
  sits behind a written Context Contract with a CI conformance wall;
  ships `builtin` (draft-first elicitation via `/kickoff-context`) and
  `speckit` (adopt an existing spec-kit workspace at a pinned revision),
  plus the `setup-sources.sh` activation wizard with plan-aware
  preflight.
- Consent-gated adopter feedback (ADR-0002): on scaffold script failure,
  an interactive TTY session offers — never auto-sends — a pre-filled
  upstream issue built from a fixed eight-field allowlist (no arguments,
  no paths, no environment); the receiving workflow labels `from:adopter`
  from body marker or title prefix without checking out untrusted code.
  Documented for adopters in `.github/docs/adopter-feedback.md`.
- Namespace ownership: the scaffold owns `.github/` plus the root files
  it shipped (`AGENTS.md`, this changelog, seeded `README.md` /
  `.gitignore`); every other path is the application's. The template
  repository's own dev records live in root `docs/` and are **not**
  installed; walls scan scaffold-owned paths only.
- Contributor environment: `.devcontainer/` (ubuntu-24.04, gh + jq +
  sha-pinned shellcheck) reproduces the wall toolchain; CI validates it
  when present.
- Repository bootstrap: label set, branch ruleset (created disabled for
  human review), optional Projects v2 roadmap board; onboarding as a
  procedure (inventory → gap interview → run-verified commands → evidence
  PR) with `tuning-status.sh` keeping the untuned state visible; existing
  codebases start with characterization tests.
- MIT `LICENSE`; the README opens with the after-copying path.
