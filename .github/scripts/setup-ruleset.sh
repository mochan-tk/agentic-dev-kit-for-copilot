#!/usr/bin/env bash
# setup-ruleset.sh — bootstrap the branch ruleset described in README step 5:
# on the default branch, require a pull request (>= 1 approving review) and
# required status checks, via `POST /repos/{owner}/{repo}/rulesets`.
#
# SAFE BY DEFAULT: the ruleset is created with enforcement `disabled` so it
# never blocks merges until a human consents — either by answering the
# onboarding consent question (which re-runs this script with
# `--enforcement active`) or in repository Settings -> Rules -> Rulesets.
#
# IDEMPOTENT: when a ruleset with the target name already exists and its
# enforcement matches the request, the script reports its id and exits.
# When only the enforcement differs, it updates that one field in place
# (PUT with a partial body leaves rules/conditions/bypass untouched) —
# this is the consent path from a `disabled` bootstrap to `active`.
#
# Requires: gh (authenticated) and jq. Compatible with bash 3.2 (macOS).

set -euo pipefail

# Consent-gated adopter feedback (ADR-0002): on an unguarded failure in an
# interactive run, offer - default no, full preview, allowlist-only - to
# file the failure upstream. Lib absent or any gate closed: byte-identical.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" ]; then
  # shellcheck source=/dev/null
  if . "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" 2>/dev/null; then
    feedback_arm setup-ruleset || true
  fi
fi

usage() {
  cat <<'EOF'
Usage: setup-ruleset.sh [options]

Create a branch ruleset targeting the repository's default branch that
requires:
  - a pull request with at least 1 approving review
  - required status checks (default: all four CI wall jobs —
    quality,task-ritual,scaffold-self-check,copilot-surface)

Repository admins may bypass, for pull requests only: direct pushes stay
blocked for everyone, but an admin can merge a PR through the explicit,
audited "bypass" button. Without this, a solo adopter could never merge
their own PRs (you cannot approve your own), including the onboarding PR.

If a ruleset with the same name already exists, the script updates its
enforcement when the request differs and otherwise changes nothing.

Options:
  -R, --repo <owner/repo>  Target repository. Default: the repository the
                           current directory belongs to (via `gh repo view`).
  --checks <c1,c2,...>     Comma-separated status check contexts to require.
                           Default: quality,task-ritual,scaffold-self-check,copilot-surface.
  --enforcement <mode>     `active` or `disabled`. Default: `disabled`, so
                           the ruleset never blocks merges until a human
                           reviews it and enables it.
  --name <name>            Ruleset name. Default: scaffold-branch-protection.
  --profile <solo|team>    Persist explicit governance intent and create a
                           fresh profile ruleset. Existing rulesets require
                           separate reconciliation.
  --dry-run                Print the request JSON body to stdout and exit
                           without making any API call.
  -h, --help               Show this help and exit.

Examples:
  setup-ruleset.sh --dry-run | jq .
  setup-ruleset.sh -R owner/repo
  setup-ruleset.sh -R owner/repo --checks lint,test --enforcement active

Inspect or remove a created ruleset:
  gh api repos/<owner>/<repo>/rulesets --jq '.[] | {id, name, enforcement}'
  gh api -X DELETE repos/<owner>/<repo>/rulesets/<id>
EOF
}

REPO=""
CHECKS="quality,task-ritual,scaffold-self-check,copilot-surface"
ENFORCEMENT="disabled"
NAME="scaffold-branch-protection"
DRY_RUN="false"
PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -R|--repo)
      [[ -n "${2:-}" ]] || { echo "error: $1 requires an owner/repo argument" >&2; exit 2; }
      REPO="$2"; shift 2 ;;
    --checks)
      [[ -n "${2:-}" ]] || { echo "error: --checks requires a comma-separated list" >&2; exit 2; }
      CHECKS="$2"; shift 2 ;;
    --enforcement)
      case "${2:-}" in
        active|disabled) ENFORCEMENT="$2" ;;
        *) echo "error: --enforcement must be 'active' or 'disabled'" >&2; exit 2 ;;
      esac
      shift 2 ;;
    --name)
      [[ -n "${2:-}" ]] || { echo "error: --name requires a value" >&2; exit 2; }
      NAME="$2"; shift 2 ;;
    --profile)
      case "${2:-}" in
        solo|team) PROFILE="$2" ;;
        *) echo "error: --profile must be 'solo' or 'team'" >&2; exit 2 ;;
      esac
      shift 2 ;;
    --dry-run)
      DRY_RUN="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1 (run with --help for usage)" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 1; }

# Build the request body with jq so every value is safely quoted. `$name`,
# `$enforcement`, and `$checks` below are jq variables, not shell expansions.
# shellcheck disable=SC2016
PAYLOAD="$(jq -n \
  --arg name "$NAME" \
  --arg enforcement "$ENFORCEMENT" \
  --arg checks "$CHECKS" \
  '{
    name: $name,
    target: "branch",
    enforcement: $enforcement,
    # Repository-admin bypass, pull requests only (actor_id 5 = the admin
    # repository role; verified live against the rulesets API). Solo
    # adopters cannot approve their own PRs, and rulesets grant admins no
    # implicit bypass — without this a solo repository deadlocks on its
    # own onboarding PR. Direct pushes remain blocked even for admins;
    # the PR bypass is an explicit button and is visible in the UI.
    bypass_actors: [
      { actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "pull_request" }
    ],
    conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
    rules: [
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews_on_push: false,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_review_thread_resolution: false
        }
      },
      {
        type: "required_status_checks",
        parameters: {
          strict_required_status_checks_policy: false,
          required_status_checks:
            ($checks | split(",")
                     | map(gsub("^\\s+|\\s+$"; ""))
                     | map(select(length > 0))
                     | map({context: .}))
        }
      }
    ]
  }')"

if [[ -n "$PROFILE" ]]; then
  if [[ "$PROFILE" == "solo" && "$DRY_RUN" == "true" ]]; then
    echo "dry-run: explicit solo candidate; no API call made." >&2
    printf '%s\n' "$PAYLOAD"
    exit 0
  fi

  command -v gh >/dev/null 2>&1 \
    || { echo "error: gh CLI not found on PATH" >&2; exit 1; }
  if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
  [[ "$REPO" == */* ]] \
    || { echo "error: repository must be owner/repo, got: $REPO" >&2; exit 2; }

  if [[ "$DRY_RUN" != "true" ]]; then
    gh api user --jq .login >/dev/null 2>&1 \
      || { echo "error: gh is not authenticated" >&2; exit 1; }
    if ! RULESETS_JSON="$(gh api "repos/$REPO/rulesets")"; then
      echo "error: could not list rulesets for $REPO; aborting before writes." >&2
      exit 1
    fi
    EXISTING_ID="$(printf '%s' "$RULESETS_JSON" \
      | jq -r --arg name "$NAME" '[.[] | select(.name == $name)][0].id // empty')"
    if [[ -n "$EXISTING_ID" ]]; then
      echo "error: ruleset '$NAME' already exists; explicit-profile reconciliation required." >&2
      exit 1
    fi
  fi

  if [[ "$PROFILE" == "team" ]]; then
    if ! REPO_JSON="$(gh api "repos/$REPO")"; then
      echo "error: repository metadata unavailable for team profile." >&2
      exit 1
    fi
    DEFAULT_BRANCH="$(printf '%s' "$REPO_JSON" | jq -r '.default_branch // empty')"
    if [[ -z "$DEFAULT_BRANCH" ]]; then
      echo "error: repository metadata has no default branch." >&2
      exit 1
    fi
    if ! CHECK_RUNS="$(gh api \
      "repos/$REPO/commits/$DEFAULT_BRANCH/check-runs?filter=latest&per_page=100" \
      --paginate)"; then
      echo "error: check-run evidence unavailable for team profile." >&2
      exit 1
    fi

    CONTEXTS="$(jq -nr --arg checks "$CHECKS" \
      '$checks | split(",") | map(gsub("^\\s+|\\s+$"; ""))
       | map(select(length > 0)) | .[]')"
    [[ -n "$CONTEXTS" ]] \
      || { echo "error: team profile requires at least one check context." >&2; exit 1; }
    COMMON_ID=""
    while IFS= read -r context; do
      IDS="$(printf '%s' "$CHECK_RUNS" | jq -s -c --arg context "$context" \
        '[.[].check_runs[] | select(.name == $context) | .app.id]')"
      if ! printf '%s' "$IDS" | jq -e '
        length > 0
        and all(.[]; type == "number" and . >= 0 and floor == .)
        and (unique | length == 1)
      ' >/dev/null; then
        echo "error: invalid or ambiguous issuer evidence for context '$context'." >&2
        exit 1
      fi
      CONTEXT_ID="$(printf '%s' "$IDS" | jq -r 'unique[0]')"
      if [[ -n "$COMMON_ID" && "$COMMON_ID" != "$CONTEXT_ID" ]]; then
        echo "error: requested check contexts have different issuers." >&2
        exit 1
      fi
      COMMON_ID="$CONTEXT_ID"
    done <<EOF
$CONTEXTS
EOF

    PAYLOAD="$(printf '%s' "$PAYLOAD" | jq --argjson app "$COMMON_ID" '
      (.rules[] | select(.type == "pull_request").parameters) |=
        (.dismiss_stale_reviews_on_push = true
         | .require_last_push_approval = true
         | .require_code_owner_review = true
         | .required_review_thread_resolution = true)
      | (.rules[] | select(.type == "required_status_checks").parameters) |=
        (.strict_required_status_checks_policy = true
         | .required_status_checks |= map(. + {integration_id: $app}))
    ')"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "dry-run: explicit team candidate from GET-only evidence; no mutation made." >&2
    printf '%s\n' "$PAYLOAD"
    exit 0
  fi

  VARIABLE_PATH="repos/$REPO/actions/variables/SCAFFOLD_GOVERNANCE_PROFILE"
  VARIABLE_EXISTS="true"
  VARIABLE_RESULT=""
  if ! VARIABLE_RESULT="$(gh api "$VARIABLE_PATH" 2>&1)"; then
    case "$VARIABLE_RESULT" in
      *"HTTP 404"*) VARIABLE_EXISTS="false" ;;
      *) echo "error: governance profile variable is unreadable: $VARIABLE_RESULT" >&2; exit 1 ;;
    esac
  fi
  VARIABLE_BODY="$(jq -n --arg value "$PROFILE" \
    '{name: "SCAFFOLD_GOVERNANCE_PROFILE", value: $value}')"
  if [[ "$VARIABLE_EXISTS" == "true" ]]; then
    if ! printf '%s' "$VARIABLE_BODY" | gh api --method PATCH "$VARIABLE_PATH" --input - >/dev/null; then
      echo "error: could not update governance profile variable." >&2
      exit 1
    fi
  else
    if ! printf '%s' "$VARIABLE_BODY" \
      | gh api --method POST "repos/$REPO/actions/variables" --input - >/dev/null; then
      echo "error: could not create governance profile variable." >&2
      exit 1
    fi
  fi

  if ! RESPONSE="$(printf '%s' "$PAYLOAD" \
    | gh api --method POST "repos/$REPO/rulesets" --input -)"; then
    echo "error: governance intent persisted, but ruleset creation failed." >&2
    exit 1
  fi
  RULESET_ID="$(printf '%s' "$RESPONSE" | jq -r '.id')"
  echo "Created ruleset '$NAME' (id: $RULESET_ID, enforcement: $ENFORCEMENT) on $REPO."
  echo "Recorded governance profile: $PROFILE."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  # stdout carries only the JSON body (pipeable to jq); notes go to stderr.
  echo "dry-run: request body for POST /repos/{owner}/{repo}/rulesets; no API call made." >&2
  printf '%s\n' "$PAYLOAD"
  exit 0
fi

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found on PATH" >&2; exit 1; }
gh api user --jq .login >/dev/null 2>&1 \
  || { echo "error: gh is not authenticated" >&2; echo "  fix: run: gh auth login" >&2; exit 1; }

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$REPO" == */* ]] || { echo "error: repository must be owner/repo, got: $REPO" >&2; exit 2; }

# Idempotency: a ruleset with the target name already existing means a prior
# run (or a human) owns it — skip instead of creating a same-name duplicate.
# The list call must succeed before we may create anything: proceeding on a
# failed list could re-create a duplicate the guard exists to prevent.
if ! RULESETS_JSON="$(gh api "repos/$REPO/rulesets")"; then
  echo "error: could not list rulesets for $REPO — aborting before any creation attempt." >&2
  echo "       Check repository access and gh auth, then re-run." >&2
  exit 1
fi
EXISTING_ID="$(printf '%s' "$RULESETS_JSON" \
  | jq -r --arg name "$NAME" '[.[] | select(.name == $name)][0].id // empty')"
if [[ -n "$EXISTING_ID" ]]; then
  EXISTING_ENFORCEMENT="$(printf '%s' "$RULESETS_JSON" \
    | jq -r --arg name "$NAME" '[.[] | select(.name == $name)][0].enforcement // "unknown"')"
  if [[ "$EXISTING_ENFORCEMENT" == "$ENFORCEMENT" ]]; then
    echo "Ruleset '$NAME' already exists on $REPO (id: $EXISTING_ID, enforcement: $EXISTING_ENFORCEMENT) — skipping creation."
    echo "Inspect: gh api repos/$REPO/rulesets/$EXISTING_ID"
    echo "Delete:  gh api -X DELETE repos/$REPO/rulesets/$EXISTING_ID"
    exit 0
  fi
  # Enforcement differs: update that one field in place. PUT with a
  # partial body is a partial update for rulesets — rules, conditions,
  # and bypass actors are left as they are (verified live). This is how
  # a `disabled` bootstrap gets promoted to `active` after consent.
  if [[ "$ENFORCEMENT" == "active" ]]; then
    echo "warning: enforcement 'active' starts blocking merges on $REPO immediately." >&2
  fi
  gh api --method PUT "repos/$REPO/rulesets/$EXISTING_ID" \
    -f enforcement="$ENFORCEMENT" >/dev/null
  echo "Updated ruleset '$NAME' (id: $EXISTING_ID) on $REPO: enforcement $EXISTING_ENFORCEMENT -> $ENFORCEMENT."
  echo "Inspect: gh api repos/$REPO/rulesets/$EXISTING_ID"
  exit 0
fi

if [[ "$ENFORCEMENT" == "active" ]]; then
  echo "warning: enforcement 'active' starts blocking merges on $REPO immediately." >&2
fi

RESPONSE="$(printf '%s' "$PAYLOAD" | gh api --method POST "repos/$REPO/rulesets" --input -)"
RULESET_ID="$(printf '%s' "$RESPONSE" | jq -r '.id')"

echo "Created ruleset '$NAME' (id: $RULESET_ID, enforcement: $ENFORCEMENT) on $REPO."
echo "Inspect: gh api repos/$REPO/rulesets/$RULESET_ID"
echo "Delete:  gh api -X DELETE repos/$REPO/rulesets/$RULESET_ID"
if [[ "$ENFORCEMENT" == "disabled" ]]; then
  echo "Enable after review: Settings -> Rules -> Rulesets (set enforcement to Active)."
fi
