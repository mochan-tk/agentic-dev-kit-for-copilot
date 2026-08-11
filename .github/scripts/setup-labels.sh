#!/usr/bin/env bash
# setup-labels.sh — create/refresh the canonical label set this scaffold
# relies on (plan-management, task-routing, session-orchestration skills).
# Idempotent: uses `gh label create --force`.
#
# Usage: setup-labels.sh [-R owner/repo] | setup-labels.sh -h|--help

set -euo pipefail

# Consent-gated adopter feedback (ADR-0002): on an unguarded failure in an
# interactive run, offer - default no, full preview, allowlist-only - to
# file the failure upstream. Lib absent or any gate closed: byte-identical.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" ]; then
  # shellcheck source=/dev/null
  if . "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" 2>/dev/null; then
    feedback_arm setup-labels || true
  fi
fi

usage() {
  cat <<'EOF'
Usage: setup-labels.sh [options]

Create or refresh the 12 canonical scaffold labels on a repository.
Idempotent: existing labels are updated in place (gh label create --force).

Options:
  -R <owner/repo>  Target repository. Default: the repository the current
                   directory belongs to (gh's usual resolution).
  -h, --help       Show this help and exit. No API calls are made.
EOF
}

REPO_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -R)
      [[ -n "${2:-}" ]] || { echo "error: -R requires an owner/repo argument" >&2; usage >&2; exit 1; }
      REPO_ARGS=(--repo "$2")
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done
command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }
gh api user --jq .login >/dev/null 2>&1 \
  || { echo "error: gh is not authenticated" >&2; echo "  fix: run: gh auth login" >&2; exit 1; }

# ${arr[@]+"${arr[@]}"} guards the empty-array expansion, which is an unbound
# variable under `set -u` on bash 3.2 (macOS /bin/bash); fixed in bash 4.4.
create() { gh label create "$1" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --color "$2" --description "$3" --force; }

create "type:epic"    "5319E7" "Outline item; parent of Task sub-issues (plan-management)"
create "type:task"    "0E8A16" "Self-contained work order for one agent session"
create "ai:ready"     "1D76DB" "Brief meets the planner quality bar; dispatchable when unblocked"
create "needs:human"  "B60205" "Escalation: judgment/trust decision required (AGENTS.md, Ambiguity rule)"
create "needs:replan" "D93F0B" "Escalation: plan/scope must change before work continues"
create "exec:cloud"   "C2E0C6" "Route: Copilot cloud (coding) agent — async, parallel, draft PR"
create "exec:app"     "BFDADC" "Route: Copilot app session — steerable, worktree-isolated"
create "exec:cli"     "FEF2C0" "Route: Copilot CLI — scripted / batch / CI-triggered"
create "exec:ide"     "F9D0C4" "Route: IDE with human in the loop — ambiguous or hardware work"
create "retro:candidate" "EDEDED" "Observed scaffold friction; promote to a retro: PR at the 2nd occurrence"
create "risk:high"    "E11D21" "Exception gate: pause after the plan comment until approved (default is pass-through)"
create "from:adopter" "FBCA04" "Adopter feedback report (ADR-0002 receiving end); triage input, not a work order"

echo "Done. 12 labels ensured."
