#!/usr/bin/env bash
# check-workflow-permissions.sh — fail when a workflow job that declares its
# own `permissions:` block runs `actions/checkout` without granting
# `contents`.
#
# Why this guard exists: a job-level `permissions:` block *replaces* the
# workflow-level grant, it does not merge with it. A job that lists only
# `issues: read` therefore has no `contents` scope, and `actions/checkout`
# fails with "Repository not found" — but only on private repositories,
# because public ones clone without a token. This scaffold's own repository
# is public, so its CI is structurally incapable of catching the mistake;
# adopters on private repositories eat it on every pull request instead.
# Hence a static check rather than trust in a green run.
#
# Scope: `.github/workflows/*.yml`. Jobs without a `permissions:` block are
# skipped — they inherit the workflow-level grant, which is the common and
# correct case.
#
# Output: brief OK summary and exit 0 when every such job grants contents;
# the offending jobs and exit 1 otherwise.
# Dependencies: bash 3.2+, awk only — no YAML parser, no network, so it runs
# identically in CI and on a developer machine.
set -euo pipefail

DIR="${1:-.github/workflows}"
[ -d "$DIR" ] || { echo "error: $DIR not found" >&2; exit 2; }

findings=""
checked=0

for wf in "$DIR"/*.yml "$DIR"/*.yaml; do
  [ -e "$wf" ] || continue
  # One record per job: name, whether it declared permissions, whether that
  # block granted contents, and whether the job checks the repository out.
  report="$(awk '
    # Job keys sit at exactly two spaces of indentation under `jobs:`.
    /^  [a-zA-Z_][a-zA-Z0-9_-]*:[[:space:]]*$/ {
      if (job != "") print job "\t" hasperm "\t" hascontents "\t" hascheckout
      job = $1; sub(/:$/, "", job)
      hasperm = 0; hascontents = 0; hascheckout = 0; inperm = 0
      next
    }
    job == "" { next }
    # `permissions:` on the job (four spaces). An inline empty map
    # (`permissions: {}`) also counts as declared.
    /^    permissions:/ { hasperm = 1; inperm = 1; next }
    # Any other four-space key ends the permissions block.
    /^    [a-zA-Z]/ { inperm = 0 }
    inperm && /^      contents:/ { hascontents = 1 }
    /actions\/checkout/ { hascheckout = 1 }
    END { if (job != "") print job "\t" hasperm "\t" hascontents "\t" hascheckout }
  ' "$wf")"

  while IFS=$'\t' read -r job hasperm hascontents hascheckout; do
    [ -n "$job" ] || continue
    checked=$((checked + 1))
    if [ "$hasperm" = "1" ] && [ "$hascheckout" = "1" ] && [ "$hascontents" = "0" ]; then
      findings="${findings}${wf}: job '${job}' declares permissions and checks out"$'\n'"    the repository, but grants no 'contents' scope — checkout will fail"$'\n'"    on private repositories."$'\n'
    fi
  done <<EOF
$report
EOF
done

if [ -n "$findings" ]; then
  printf 'FAIL: %s' "$findings"
  echo "      A job-level permissions block replaces the workflow-level one."
  echo "      Add 'contents: read' to each job listed above."
  exit 1
fi

echo "check-workflow-permissions: OK — $checked job(s) checked; every job that declares permissions and checks out grants contents."
