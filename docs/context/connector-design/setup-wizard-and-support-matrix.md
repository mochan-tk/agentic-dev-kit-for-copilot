---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-06/07); GitHub Docs (plans and feature availability; Projects limits)
retrieved: 2026-08-07
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Setup wizard and support matrix

Agreed install-time UX and platform constraints. GitHub-plan facts are from
public GitHub documentation (re-verify against current docs before
promoting; plans change). As `method: ai-summary`, re-verify via PR review.

## Two-layer separation

- **Wizard (bash, deterministic)**: environment preflight, data-source
  selection, writing the `SOURCES.md` registry (planned file under
  `.github/docs/context/`). No LLM involved.
- **Agent (LLM, adaptive)**: elicitation and tuning, started *after* the
  wizard by the user pasting an exact kickoff prompt the wizard prints in a
  copy-paste box. The box is the boundary between the two layers.

## Wizard flow

- **Q0 — preflight** (before any question):
  - Inside a git repository? If not: stop with guidance.
  - GitHub remote present? If not: offer `gh repo create`.
  - `gh` installed and authenticated? If not: stop with install/auth steps.
  - **Plan/visibility check**: if the repository is private *and* the owner
    is on the Free plan → **hard stop, no continue option**. Rationale
    below. Remediation offered: make the repository public, or upgrade to a
    paid plan.
- **Q1 — data source**: menu offering `spec-kit` / `None yet` (v1);
  `Kiro` / `M365 (workiq)` listed as coming/community. The wizard
  auto-suggests: if `specs/**` exists it recommends the speckit connector.
- **Output**: writes `SOURCES.md` (enabled connector + pin where
  applicable), prints the exact agent kickoff prompt in a box.
- **Mechanics**: interactive even under `curl | bash` via
  `read < /dev/tty`; non-TTY environments skip prompts and print the
  "run this later" instruction; `--source <name>` flag enables
  non-interactive use (CI, scripted adoption).

## Why Free-plan private repositories are unsupported

The scaffold's core gate is *required PR review before merge* (CODEOWNERS +
branch protection / rulesets). On the Free plan, branch protection and
rulesets are **not available on private repositories** — the approval gate
cannot be enforced, so the lifecycle's guarantees silently degrade. Rather
than ship a scaffold whose central promise can be bypassed, the wizard
declares the combination unsupported and stops. ("If you don't like it, go
public or pay" — maintainer decision, no bypass flag.)

## Support matrix (v1)

| Repository | Plan | Supported |
|---|---|---|
| Public | any (incl. Free) | yes |
| Private | paid (Pro/Team/Enterprise) | yes |
| Private | Free | **no — wizard hard-stops** |

## GitHub platform facts collected (Free plan)

- Projects (v2): no cap on the *number* of projects; the operative limits
  are plan-independent (1,200 active items / 10,000 archived items / 50
  views / 50 custom fields per project). Issues are unlimited and free —
  the ledger itself costs nothing.
- Free + private: no branch protection / rulesets (the blocking fact
  above); Actions quota 2,000 minutes/month (sufficient for the scaffold's
  walls on small projects).
- Public repositories: full feature set including rulesets and unlimited
  Actions minutes for standard runners.
