# Adopter feedback — what is sent, what is never collected

The scaffold's interactive scripts can *offer* — never send automatically —
a structured failure report to the scaffold maintainers. This page is the
complete description of that mechanism: read it before answering the
consent prompt, or to turn the mechanism off. Governing decision: ADR-0002,
kept in the scaffold repository at
`docs/agreements/adr/ADR-0002-consent-gated-adopter-feedback.md` — a
development record that is not installed into adopter projects.

## How it works

- The offer appears only when a scaffold-owned interactive script — the
  installer (`.github/scripts/scaffold-init.sh`) or one of the `setup-*`
  scripts (setup-labels, setup-project, setup-ruleset, setup-sources) —
  fails on an unexpected error. Deliberate exits with remediation messages
  never trigger it.
- Filing uses your own `gh` CLI and your own GitHub account: the report
  becomes a **public issue** on the upstream scaffold repository. The
  scaffold has no service identity and no telemetry endpoint; the only
  network action is a single `gh issue create`, and only after you consent.
- The upstream target is read exclusively from the `scaffold-version`
  marker in `SCAFFOLD-CHANGELOG.md`. A missing or invalid marker means no
  offer at all — the target is never guessed.
- Every gate fails closed: no offer in CI (`CI` or `GITHUB_ACTIONS` set to
  any non-empty value), in non-interactive runs (stdin and stderr must both
  be terminals), or when `gh` is not installed. The mechanism itself reads
  no environment variable that enables, bypasses, or retargets the offer;
  the filing step is a plain `gh issue create`, so `gh`'s own standard
  configuration (such as `GH_HOST`) applies to it exactly as to any other
  `gh` command you run.

## What is sent

Exactly these eight fields — nothing else. The allowlist rationale lives in
the scaffold repository at `docs/context/feedback-loop/privacy-posture.md`
(a development record, not installed):

| Field | Source |
|---|---|
| Script name | fixed enum of scaffold script names — never `$0` |
| Failing line number | recorded by the error trap — never command text |
| Exit code | numeric |
| OS and architecture | `uname -s` / `uname -m` |
| bash version | `$BASH_VERSION` |
| gh version | `gh --version` |
| jq version | `jq --version`, or `unknown` when jq is absent |
| Scaffold version | the commit SHA from the version marker |

- Every value is validated against a fixed character class and length cap
  and must be a single line. A value that fails validation is sent as
  `unknown`, never raw — a report with holes is acceptable, a report with
  a leak is not.
- The full issue title and body are printed to your terminal before the
  question. The preview shows the same title and body strings that are
  passed to `gh` — nothing is added, removed, or re-formatted between the
  preview and the send.
- The default answer is **No**. Only a literal `y` (or `Y`) sends; Enter,
  `n`, or any other input declines.

## What is never collected

- No log output, stderr text, or error messages — messages can embed
  paths, repository names, URLs, or secrets, so the design is
  *not-collect over sanitize*: they are out of scope entirely.
- No filesystem paths, working directory, repository name or slug, git
  remote URLs, or branch names.
- No environment variables, tokens, credentials, or gh auth state.
- Nothing free-form: a field that is not in the table above cannot enter
  the payload.

## Declining and disabling

- **Decline once:** press Enter (or `n`) at the prompt. Nothing is sent
  and nothing changes: same exit code, no network action. The only
  difference from an unwired script is the offer text you just read (when
  a gate closes the offer instead — CI, non-interactive, no `gh` — the
  failure path is byte-identical to a script without the mechanism).
- **Disable:** delete `.github/scripts/feedback-lib.sh`. Every wired
  script checks that the file is readable before sourcing it and continues
  silently without it — no other edits are needed and no functionality is
  lost. The deletion holds until a scaffold upgrade: re-running the
  installer restores the file, so delete it again after upgrading.
- **Report manually instead:** open an issue on the scaffold repository
  using the Adopter feedback form (`.github/ISSUE_TEMPLATE/feedback.yml`).
  The same posture applies there: reference, don't paste — never include
  secrets, tokens, or logs with private paths.

## Receiving side

Reports carry a fixed marker: the `[adopter-feedback]` title prefix and an
HTML comment in the body. On the scaffold repository, a workflow
(`.github/workflows/adopter-feedback.yml`) applies the `from:adopter`
label on marker detection, so reporters need no permissions on that
repository. The label is triage input only — it routes the report to
maintainers and grants nothing.
