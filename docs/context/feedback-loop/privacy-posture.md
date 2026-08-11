---
source: Copilot app design session ee068197 (maintainer + session agent, 2026-08-08)
retrieved: 2026-08-08
method: ai-summary
collector: session ee068197 (Copilot app worktree session)
sensitivity: public
status: raw
---

# Privacy posture: allowlist, disclosure, preview

The maintainer's constraint, verbatim in intent: derive the report from
the failure, but never acquire sensitive adopter information. The design
answer is **not-collect over sanitize** — the payload is built only from
an allowlist of structured fields, so sensitive data is never in scope.

## Allowlist — the only fields a report may contain

| Field | Example shape | Why it is safe |
|---|---|---|
| Failing script name | `setup-labels.sh` | Scaffold-owned filename, identical for every adopter |
| Failing step / line label | step name or line number | Scaffold-owned code location |
| Exit code | `1` | Numeric |
| OS + architecture | `Darwin arm64` (from `uname`) | Coarse platform info |
| bash version | `3.2.57` | Tool version |
| gh version | `2.97.0` | Tool version |
| jq version | `jq-1.7` | Tool version |
| Scaffold version | stamped commit SHA | Scaffold-owned identity (`version-identity.md`) |

## Never collected

- Log output or stderr text of any kind — error *messages* can embed
  paths, repository names, URLs, or secrets, so the payload never includes
  them. The adopter may add detail by hand after the issue opens.
- Filesystem paths, `$HOME`, working directory, repository name or slug,
  git remote URLs, branch names.
- Environment variables, tokens, credentials, gh auth state.
- Anything free-form: if a field is not in the allowlist table, it is not
  in the payload.

## Field hardening — allowlist names alone are not enough

Naive sourcing can smuggle sensitive data through allowlisted fields:
`$0` may expand to an absolute path containing the adopter's directory
layout, and `$BASH_COMMAND` at trap time can contain arbitrary command
text including secrets passed as arguments. External review flagged
this; the constraints below are part of the posture, not implementation
detail:

- **Script name** comes from a fixed enum of scaffold-owned basenames
  (the installer + `setup-*` set), never from raw `$0`. Values are
  matched against the enum; anything else is omitted.
- **Failing step** is a scaffold-authored constant label (a step name the
  script itself declares) or a bare line number — never `$BASH_COMMAND`,
  never interpolated text.
- **Every field is validated** against an expected character class and a
  hard length cap before it enters the payload (e.g. versions:
  `[0-9A-Za-z. _()-]`, short caps; exit code: digits only).
- **Omit on parse failure.** A field that fails validation is dropped
  (recorded as `unknown`), never passed through raw. A report with holes
  is acceptable; a report with a leak is not.

## Disclosure and preview requirements

- The full issue title and body are printed to the terminal before the
  consent question; what is previewed is exactly what is sent.
- The prompt states two facts explicitly: the report becomes a **public**
  issue on the upstream repository, and it is created **as the adopter's
  own GitHub account** (via their gh auth) — the scaffold has no service
  identity of its own.
- Default answer is no; non-interactive environments never prompt and
  never send (see `design-session-decisions.md`).
