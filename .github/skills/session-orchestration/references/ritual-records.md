# Ritual records: render, inspect, preflight, publish separately

This is the supervisor's prevention-first path for claim/resume, Plan, and
worker-dispatch comments. Workers execute the approved Plan without another
Plan gate, maintain PR evidence, and report to their supervisor; they never
publish these Task-issue comments. The [main protocol](../SKILL.md) still owns
startup, authorization, disposition, verification, and escalation.

## Interface and limits

Run `bash .github/scripts/task-ritual.sh --help` from the repository root for
the authoritative interface. The implementation and exercised examples landed
in [PR #140](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/pull/140);
the [records suite](../../../scripts/tests/test-ritual-records.sh) defines the
offline fixture format used below.

```text
render <claim|resume|plan|dispatch> --input <json-file|->
preflight <claim|resume|plan|dispatch> --repo <owner/repo>
  --task <positive-number> --body-file <file|-> [--branch <known-branch>]
  [--pr <positive-number>]
```

Rendering takes exactly one JSON object, rejecting unknown fields:

| Kind | Required fields beyond numeric integral `task` (1..9007199254740991) |
|---|---|
| `claim`, `resume` | `session`: supplied nonempty display name; `branch`: valid Git branch |
| `plan` | `content`: supplied nonempty plan prose |
| `dispatch` | `session`, `branch`, and actual `session_id`: at least eight hexadecimal/hyphen characters |

Identity fields are single-line, without controls, leading/trailing whitespace,
commas, parentheses, or ritual-marker injection. Plan prose permits newlines and
tabs, not other controls. Nothing invents a session, branch, plan, or exemption.
Dependencies: Bash 3.2+, jq, git, standard Unix tools; preflight also needs gh.

| Exit | Meaning |
|---|---|
| 0 | Scoped success: render emits only the body; preflight emits observations |
| 1 | Rejected draft/ledger or unavailable read |
| 2 | Usage, input-schema, or missing-dependency error |

Failures emit diagnostics on stderr, not a publishable body on stdout.
Preflight uses explicit GET-only reads. Claim/resume needs no future plan;
plan needs a recorded claim; dispatch needs a recorded claim and plan, plus a
release between successive dispatches for replacement. Supply `--branch` when
known and `--pr` when checking an existing PR: requested but unreadable PR
context fails, never silently downgrades to pre-PR checks. A draft cannot supply
authorization retroactively before an existing commit.

## Publication procedure

1. Read the work order, current ledger, applicable startup decision, and Plan.
   Supply real facts and the substantive plan (goal, approach, ownership,
   verification), not the illustrative fixture prose below.
2. Render locally, then inspect the entire body, including any added context
   and links. Keep the literal first-line markers intact. A dispatch also needs
   target PR and scope; add them below the generated header before inspection.
3. Preflight that exact body against the current ledger. On any failure, stop
   before `gh issue comment`; investigate and escalate invalid prior records.
   Never edit/delete existing comments, backdate timestamps, fabricate approval,
   or silently supersede a malformed record. A fresh Plan is not historical
   repair; follow the existing append-only work-loop and replacement protocol.
4. Publish separately only under the existing procedural authority. Refresh
   preflight immediately before publication: an earlier PASS expires when the
   ledger changes, including another session's claim or dispatch. A race after
   the read is still possible; inspect the posted record and current ledger
   before acting. Neither generation nor PASS proves worker existence,
   authenticated identity, approval, or future CI.

The dispatch order remains **create worker -> confirm actual identity/branch ->
record Dispatching worker -> start implementation**. Rendering a hypothetical
worker cannot replace creation or confirmation. Apply the existing `risk:high`
scope approval, material-change re-approval, and irreversible-live-write
owner-typed GO exception; this procedure adds no universal authorization stage.
Workers do not publish a resume comment or repeat the supervisor's Plan gate.

## Offline executable walkthrough

Run the following Bash blocks in order from the repository root, in one shell.
They use only local fixtures: `o/r`, Task 12, and the displayed identities are
fictional. **Never publish these examples to a real issue.** The shim has no
network fallback and only simulates append-only publication. Do not substitute
real `gh` while running the walkthrough.

Set `RITUAL_EXAMPLE_DIR` to an unused, absolute directory in session artifact
storage, outside the checkout. Keep it for evidence until the PR contains the
commands, inputs, bodies, stdout/stderr, exits, and shim log; do not commit it.
The JSON shape is the records suite's `repo.json`, `issue.json`, and paginated
`comments.json`. Fixed dates below describe fictional historical fixtures, not
timestamps assigned to drafts or any live record.

```bash
set -euo pipefail
: "${RITUAL_EXAMPLE_DIR:?Set an unused absolute session-artifact directory}"
mkdir "$RITUAL_EXAMPLE_DIR"
mkdir "$RITUAL_EXAMPLE_DIR/bin" "$RITUAL_EXAMPLE_DIR/fixtures"
export GH_FIXTURES="$RITUAL_EXAMPLE_DIR/fixtures"
export RITUAL_CALLS="$RITUAL_EXAMPLE_DIR/calls.log"
export RITUAL_API_RETRY_DELAY=0
: > "$RITUAL_CALLS"
cat > "$RITUAL_EXAMPLE_DIR/bin/gh" <<'SHIM'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$RITUAL_CALLS"
if [[ $# -eq 7 && "$1" == issue && "$2" == comment && "$3" == 12 &&
      "$4" == --repo && "$5" == o/r && "$6" == --body-file ]]; then
  test -s "$7"
  printf 'SIMULATED_APPEND %s\n' "$7" >> "$RITUAL_CALLS"
  printf 'OFFLINE: would append the inspected body; no network or ledger write.\n'
  exit 0
fi
[[ $# -ge 4 && "$1" == api ]] || { echo 'BLOCKED invocation' >&2; exit 64; }
endpoint="$2"; shift 2
[[ "$*" == '--method GET' || "$*" == '--paginate --slurp --method GET' ]] ||
  { echo 'BLOCKED non-GET or unknown options' >&2; exit 64; }
case "$endpoint" in
  repos/o/r) cat "$GH_FIXTURES/repo.json" ;;
  repos/o/r/issues/12) cat "$GH_FIXTURES/issue.json" ;;
  'repos/o/r/issues/12/comments?per_page=100')
    [[ "$*" == '--paginate --slurp --method GET' ]] || exit 64
    jq -s '.' "$GH_FIXTURES/comments.json" ;;
  *) echo 'BLOCKED unknown endpoint' >&2; exit 64 ;;
esac
SHIM
chmod +x "$RITUAL_EXAMPLE_DIR/bin/gh"
export PATH="$RITUAL_EXAMPLE_DIR/bin:$PATH"
test "$(command -v gh)" = "$RITUAL_EXAMPLE_DIR/bin/gh"
printf '%s\n' '{"full_name":"o/r"}' > "$GH_FIXTURES/repo.json"
ledger() {
  printf '%s\n' "$1" > "$GH_FIXTURES/comments.json"
  jq '{number:12,comments:length,labels:[{name:"type:task"}],
    url:"https://api.github.com/repos/o/r/issues/12"}' \
    "$GH_FIXTURES/comments.json" > "$GH_FIXTURES/issue.json"
}
fixture_record() {
  jq -n --rawfile body "$1" --argjson id "$2" --arg stamp "$3" \
    '{id:$id,body:$body,created_at:$stamp,updated_at:$stamp,
      issue_url:"https://api.github.com/repos/o/r/issues/12"}'
}
ledger '[]'
```

### Render and inspect all four bodies

The intended branch in claim/resume is forward-looking; the dispatch identity
must instead come from the worker that actually exists. Only this offline
exercise supplies fictional identities. The Plan's content remains caller-owned.

```bash
printf '%s\n' '{"task":12,"session":"Task supervisor","branch":"task/12-x"}' |
  bash .github/scripts/task-ritual.sh render claim --input - > "$RITUAL_EXAMPLE_DIR/claim.txt"
printf '%s\n' '{"task":12,"session":"Task supervisor","branch":"task/12-x"}' |
  bash .github/scripts/task-ritual.sh render resume --input - > "$RITUAL_EXAMPLE_DIR/resume.txt"
printf '%s\n' '{"task":12,"content":"Document the ritual workflow in the two owned skill files; verify offline examples and all Task checks."}' |
  bash .github/scripts/task-ritual.sh render plan --input - > "$RITUAL_EXAMPLE_DIR/plan.txt"
printf '%s\n' '{"task":12,"session":"Task worker","session_id":"abcdef12-3456","branch":"task/12-x"}' |
  bash .github/scripts/task-ritual.sh render dispatch --input - > "$RITUAL_EXAMPLE_DIR/dispatch.txt"
printf '\nTarget: forthcoming draft PR for Task 12.\nScope: the two owned skill files.\n' \
  >> "$RITUAL_EXAMPLE_DIR/dispatch.txt"
cat "$RITUAL_EXAMPLE_DIR/claim.txt" "$RITUAL_EXAMPLE_DIR/resume.txt" \
  "$RITUAL_EXAMPLE_DIR/plan.txt" "$RITUAL_EXAMPLE_DIR/dispatch.txt"
test ! -s "$RITUAL_CALLS"
```

Each successful render exits 0 with empty stderr. Claim/resume starts with
`Starting in session` / `Resuming in session`, plan with `## Plan`, and
dispatch with `Dispatching worker: Task worker (session abcdef12-3456), branch task/12-x`.
Each includes a blank line then `Task: #12`; plan adds a blank line and content.
The dispatch target/scope is part of the inspected and preflighted body.

### Observe the correct stage

Claim and resume are alternatives, not two claims to publish for one start.
The offline snapshots progress independently of the simulated publication.

```bash
bash .github/scripts/task-ritual.sh preflight claim --repo o/r --task 12 \
  --body-file "$RITUAL_EXAMPLE_DIR/claim.txt" --branch task/12-x
bash .github/scripts/task-ritual.sh preflight resume --repo o/r --task 12 \
  --body-file "$RITUAL_EXAMPLE_DIR/resume.txt" --branch task/12-x
C=$(fixture_record "$RITUAL_EXAMPLE_DIR/claim.txt" 1 2026-01-01T09:00:00Z)
ledger "[$C]"
bash .github/scripts/task-ritual.sh preflight plan --repo o/r --task 12 \
  --body-file "$RITUAL_EXAMPLE_DIR/plan.txt" --branch task/12-x
P=$(fixture_record "$RITUAL_EXAMPLE_DIR/plan.txt" 2 2026-01-01T09:05:00Z)
ledger "[$C,$P]"
bash .github/scripts/task-ritual.sh preflight dispatch --repo o/r --task 12 \
  --body-file "$RITUAL_EXAMPLE_DIR/dispatch.txt" --branch task/12-x
```

Each exits 0 with empty stderr and these two stdout lines (`KIND` varies):

```text
PASS: observed KIND draft and ledger checks for o/r#12 only.
Not publication, future CI success, approval, or authenticated session existence. Recheck before separately posting.
```

### Refresh, then separately append (simulated only)

An inspected body and an earlier PASS are not a publication token. The function
below refreshes the observation and stops on failure, before the separate
append-only command. In actual supervisor work, use the real authorized inputs
and current ledger, never this fixture setup. Existing procedural authority must
already apply; the function neither checks nor grants it.

```bash
append_after_refresh() {
  local kind="$1" body="$RITUAL_EXAMPLE_DIR/$1.txt" rc
  if bash .github/scripts/task-ritual.sh preflight "$kind" --repo o/r --task 12 \
      --body-file "$body" --branch task/12-x; then
    gh issue comment 12 --repo o/r --body-file "$body"
  else
    rc=$?
    printf 'STOP: preflight exit %s; no publication.\n' "$rc" >&2
    return "$rc"
  fi
}
ledger '[]'
append_after_refresh claim
append_after_refresh resume
ledger "[$C]"
append_after_refresh plan
ledger "[$C,$P]"
append_after_refresh dispatch
test "$(grep -c '^SIMULATED_APPEND ' "$RITUAL_CALLS")" -eq 4
```

Each call exits 0, emits the two preflight lines and
`OFFLINE: would append the inspected body; no network or ledger write.`
These four simulations are not four actual publications or evidence of approval.

### A stale PASS cannot bypass a failed refresh

The prior dispatch PASS no longer applies to a different ledger. This negative
fixture deliberately lacks the prerequisite claim; no historical live record
is changed. The guarded publication command must not be reached.

```bash
ledger '[]'
rc=0
append_after_refresh dispatch || rc=$?
test "$rc" -eq 1
test "$(grep -c '^SIMULATED_APPEND ' "$RITUAL_CALLS")" -eq 4
test "$(grep -c '^issue comment ' "$RITUAL_CALLS")" -eq 4
cat "$RITUAL_CALLS"
```

The failed preflight emits no stdout and exits 1; stderr is:

```text
error: recorded claim prerequisite is missing
STOP: preflight exit 1; no publication.
```

All API entries in the log are explicit GETs. Four `issue comment` entries are
offline simulations; the failed refresh adds none. The shim cannot invoke real
GitHub, mutate API state, or fabricate an approval. Re-run the records suite for
edited/malformed historical records, replacement releases, optional PR context,
pagination, and production CI-parser round trips; its broader coverage is not
replaced by this walkthrough.
