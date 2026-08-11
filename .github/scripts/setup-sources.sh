#!/usr/bin/env bash
# setup-sources.sh — connector activation wizard. Runs preflight checks,
# selects a data-source connector (builtin or speckit), and writes the
# per-project SOURCES.md registry, ready for an activation PR
# (.github/connectors/README.md, "Activation").
#
# The wizard prepares the registry file; it never opens the PR. The
# activation PR — reviewed by humans — is the durable decision, so the
# file it writes carries pin placeholders that are completed from inside
# that PR.
#
# Usage: setup-sources.sh [--source builtin|speckit] [--yes] [--dry-run]
#        setup-sources.sh -h|--help
#
# All GitHub access goes through `gh api` (kept shim-testable). Exit
# codes: 0 success or nothing to do, 1 preflight/runtime failure,
# 2 usage error.

set -euo pipefail

# Consent-gated adopter feedback (ADR-0002): on an unguarded failure in an
# interactive run, offer - default no, full preview, allowlist-only - to
# file the failure upstream. Lib absent or any gate closed: byte-identical.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" ]; then
  # shellcheck source=/dev/null
  if . "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" 2>/dev/null; then
    feedback_arm setup-sources || true
  fi
fi

REGISTRY_REL=".github/docs/context/SOURCES.md"

usage() {
  cat <<'EOF'
Usage: setup-sources.sh [options]

Connector activation wizard: preflight-checks the repository, picks a
data-source connector, and writes the SOURCES.md registry (under
.github/docs/context/) for you to submit as an activation PR.

Options:
  --source <name>  Connector to enable: builtin or speckit. Skips the
                   interactive menu (required when stdin is not a TTY).
  --yes            Write without the confirmation prompt (CI-safe).
  --dry-run        Print the would-be registry entry; write nothing.
  -h, --help       Show this help and exit. No API calls are made.

Preflight (all must pass before anything is written):
  - the current directory is inside a git repository
  - a GitHub remote exists and parses to owner/repo
  - gh is installed and authenticated (gh api user)
  - supported plan: private repositories on the GitHub Free plan are
    unsupported — make the repository public or upgrade the plan

Exit codes: 0 success (or already registered), 1 preflight or runtime
failure, 2 usage error.
EOF
}

fail() { # fail <message...> — preflight/runtime failure, exit 1
  echo "error: $1" >&2
  shift
  while [ $# -gt 0 ]; do echo "  $1" >&2; shift; done
  exit 1
}

usage_error() {
  echo "error: $1" >&2
  usage >&2
  exit 2
}

SOURCE=""
ASSUME_YES=false
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --source)
      [ -n "${2:-}" ] || usage_error "--source requires an argument"
      SOURCE="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done
if [ -n "$SOURCE" ] && [ "$SOURCE" != "builtin" ] && [ "$SOURCE" != "speckit" ]; then
  usage_error "unknown source '$SOURCE' (expected builtin or speckit)"
fi

# --- Preflight -----------------------------------------------------------

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "not inside a git repository" \
          "run this from your project checkout (git init / git clone first)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

REMOTE_URL="$(git config --get remote.origin.url 2>/dev/null || true)"
[ -n "$REMOTE_URL" ] \
  || fail "no 'origin' remote configured" \
          "add your GitHub remote: git remote add origin <url>"

# Accept https://github.com/o/r(.git), git@github.com:o/r(.git),
# ssh://git@github.com/o/r(.git). Trailing /.git stripped first — POSIX
# ERE (BSD sed) has no lazy quantifier.
CLEAN_URL="${REMOTE_URL%/}"
CLEAN_URL="${CLEAN_URL%.git}"
OWNER_REPO="$(printf '%s\n' "$CLEAN_URL" \
  | sed -n -E 's#^(https://|ssh://git@|git@)github\.com[:/]([^/]+/[^/]+)$#\2#p')"
[ -n "$OWNER_REPO" ] \
  || fail "origin remote is not a github.com repository: $REMOTE_URL" \
          "this scaffold's support policy targets github.com"
OWNER="${OWNER_REPO%%/*}"

command -v gh >/dev/null 2>&1 \
  || fail "gh CLI not found" "install it: https://cli.github.com"

LOGIN="$(gh api user --jq .login 2>/dev/null)" \
  || fail "gh is not authenticated" "run: gh auth login"

PRIVATE="$(gh api "repos/$OWNER_REPO" --jq .private 2>/dev/null)" \
  || fail "cannot read repos/$OWNER_REPO via gh api" \
          "check the remote URL and your access to the repository"

if [ "$PRIVATE" = "true" ]; then
  OWNER_TYPE="$(gh api "repos/$OWNER_REPO" --jq .owner.type 2>/dev/null || true)"
  PLAN=""
  if [ "$OWNER_TYPE" = "Organization" ]; then
    PLAN="$(gh api "orgs/$OWNER" --jq .plan.name 2>/dev/null || true)"
  elif [ "$OWNER" = "$LOGIN" ]; then
    PLAN="$(gh api user --jq .plan.name 2>/dev/null || true)"
  fi
  PLAN="$(printf '%s' "$PLAN" | tr '[:upper:]' '[:lower:]')"
  case "$PLAN" in
    free)
      fail "private repository on the GitHub Free plan is unsupported" \
           "the scaffold relies on features that need a paid plan on private repos" \
           "remediation: make the repository public (gh repo edit --visibility public)" \
           "         or: upgrade the owner's plan (https://github.com/pricing)"
      ;;
    ""|null)
      fail "private repository, and the owner's plan could not be determined" \
           "failing closed: private + Free plan is unsupported" \
           "verify the plan of '$OWNER' manually, then re-run" \
           "(or make the repository public: gh repo edit --visibility public)"
      ;;
  esac
fi

# --- Source selection ----------------------------------------------------

RECOMMENDED="builtin"
[ -d "$REPO_ROOT/specs" ] && RECOMMENDED="speckit"

if [ -z "$SOURCE" ]; then
  if [ -t 0 ]; then
    echo "Select the requirements source connector:"
    echo "  1) builtin — draft-first elicitation, no external system"
    echo "  2) speckit — adopt an existing specs/ tree (spec-kit)"
    if [ "$RECOMMENDED" = "speckit" ]; then
      echo "Detected a specs/ directory — speckit recommended."
    fi
    printf 'Choice [%s]: ' "$RECOMMENDED"
    read -r CHOICE || CHOICE=""
    case "$CHOICE" in
      1) SOURCE="builtin" ;;
      2) SOURCE="speckit" ;;
      "") SOURCE="$RECOMMENDED" ;;
      builtin|speckit) SOURCE="$CHOICE" ;;
      *) usage_error "unknown choice: $CHOICE" ;;
    esac
  else
    HINT=""
    [ "$RECOMMENDED" = "speckit" ] \
      && HINT=" (detected specs/ — consider --source speckit)"
    usage_error "no TTY: pass --source builtin|speckit --yes$HINT"
  fi
fi

# --- Build the registry entry --------------------------------------------

TODAY="$(date +%Y-%m-%d)"
HEADER="# Context sources registry

Machine-written by .github/scripts/setup-sources.sh; hand edits land in
activation PRs. Each section records one enabled connector and its
activation pin — see the connectors README (Activation) for the model.
This file is a registry, not collected material: the provenance-header
rule for context files does not apply."

case "$SOURCE" in
  builtin)
    PIN="activation PR #<fill in from inside the activation PR>"
    ;;
  speckit)
    SPEC_SHA="$(git log -1 --format=%H -- specs/ 2>/dev/null || true)"
    if [ -n "$SPEC_SHA" ]; then
      PIN="specs/** adoption SHA $SPEC_SHA"
    else
      PIN="specs/** adoption SHA <record the current specs/** commit SHA>"
    fi
    ;;
esac

ENTRY="## $SOURCE

- status: pending-activation (set to active in the activation PR)
- pin: $PIN
- enabled: $TODAY"

# --- Dry run / confirm / write -------------------------------------------

REGISTRY="$REPO_ROOT/$REGISTRY_REL"

if [ "$DRY_RUN" = "true" ]; then
  echo "dry-run: would write to $REGISTRY_REL:"
  echo
  [ -f "$REGISTRY" ] || { printf '%s\n\n' "$HEADER"; }
  printf '%s\n' "$ENTRY"
  exit 0
fi

if [ -f "$REGISTRY" ] && grep -q "^## $SOURCE\$" "$REGISTRY"; then
  echo "'$SOURCE' is already registered in $REGISTRY_REL — nothing to do."
  exit 0
fi

if [ "$ASSUME_YES" != "true" ]; then
  [ -t 0 ] || usage_error "no TTY for the confirmation prompt: pass --yes"
  printf 'Write %s entry to %s? [y/N]: ' "$SOURCE" "$REGISTRY_REL"
  read -r CONFIRM || CONFIRM=""
  case "$CONFIRM" in
    y|Y|yes|YES) : ;;
    *) echo "aborted — nothing written."; exit 1 ;;
  esac
fi

mkdir -p "$(dirname "$REGISTRY")"
if [ -f "$REGISTRY" ]; then
  printf '\n%s\n' "$ENTRY" >> "$REGISTRY"
else
  printf '%s\n\n%s\n' "$HEADER" "$ENTRY" > "$REGISTRY"
fi

echo "wrote $REGISTRY_REL ($SOURCE)."
echo
echo "Next steps (the activation PR is the durable decision):"
echo "  1. Create a branch and commit $REGISTRY_REL."
echo "  2. Open the activation PR; put the sufficiency-test evidence in"
echo "     its body (connectors README, 'The sufficiency test')."
case "$SOURCE" in
  builtin)
    echo "  3. Fill the activation PR number into the pin line from inside"
    echo "     that PR, then request review."
    ;;
  speckit)
    echo "  3. In the same PR (PR-A), add 'specs/** <owner>' to CODEOWNERS"
    echo "     so future spec changes get owner review (speckit.md, pin)."
    echo "  4. Confirm the recorded specs/** adoption SHA, then request"
    echo "     review."
    ;;
esac
