#!/usr/bin/env bash
# check-task-ritual.sh — CI wall: a PR's linked Task must carry the start
# ritual, in order.
#
# The session-orchestration skill requires, before work starts on a Task:
#   - a claim comment: starts with "Starting in session" or "Resuming in session"
#   - a plan comment:  contains a "## Plan" heading or starts with "Plan:"
# This wall fails any PR whose primary linked issue — the first task link
# ("Closes #N"; close/fix/resolve variants accepted, as GitHub treats them
# alike; "Refs #N" accepted for tasks with post-merge acceptance, AGENTS.md
# §4) — lacks either comment. A PR with no task link at all fails too:
# the tracking graph makes an unlinked PR a defect, not a skip.
#
# Beyond existence, the wall proves chronology — artifacts posted after the
# fact do not count as a ritual:
#   - the earliest claim precedes the earliest plan comment;
#   - the earliest plan comment precedes the PR's earliest commit
#     (AGENTS.md §2: the plan is posted before implementation begins);
#   - claim and plan comments are unedited (updated_at == created_at) —
#     revisions belong in fresh comments, never edits of the record.
# Timestamps are second-resolution ISO-8601 UTC, so lexicographic
# comparison is chronological ordering. Equal stamps cannot prove an
# inversion, so ties pass: the wall fails only on provable violations.
#
# Beyond the start ritual, the wall enforces the execution mode (ADR-0003
# Decision 2) from comment content, order, and edit-state — never
# authorship, since all sessions share one GitHub login:
#   - a worker-dispatch comment starts with "Dispatching worker"; a release
#     comment starts with "Releasing worker" (first-line regexes, exactly
#     like the claim);
#   - any dispatch comment selects the two-tier path: the earliest dispatch
#     must not predate the earliest plan and must not postdate the PR's
#     first commit (committer date, ties pass), every dispatch after the
#     first needs a release comment timestamped between the previous
#     dispatch and the new one, and dispatch/release comments are unedited
#     like claim and plan. Declared exemptions are then ignored — a replan
#     from exemption to worker split is legitimate, and the dispatch trail
#     is the stronger signal of what actually happened;
#   - with no dispatch comment, at least one plan comment must declare the
#     small-task exemption with the phrase "no worker will be spawned",
#     matched case-insensitively (AGENTS.md §4);
#   - neither trail present fails: the task ran in an undeclared mode.
#
# Beyond chronology, the wall proves provenance and routing:
#   - the PR body carries a plan link ("Plan: …#issuecomment-ID") that
#     resolves to a real plan comment on the linked Task in this
#     repository — a dead link, a link to another repository or issue,
#     or a link to a non-plan comment (e.g. the claim) all fail (a dead
#     plan link shipped once and was caught by a human, not CI);
#   - the linked issue carries the 'type:task' label (plan-management:
#     Tasks enter the graph through the ai-task template, which labels
#     them; an unlabeled issue is invisible to frontier label queries).
#
# Usage:
#   check-task-ritual.sh [<pr-number>]     # or set PR_NUMBER
#
# Exemption: only allowlisted dependency bots skip the ritual (default:
# dependabot[bot] renovate[bot] github-actions[bot]; override with
# RITUAL_EXEMPT_BOTS, space-separated logins). Any other bot author —
# cloud coding agents included — holds a session and is held to the
# full ritual.
#
# Requires: GitHub CLI (gh), authenticated. Repo context comes from the
# checkout ({owner}/{repo} placeholders); set GH_REPO to override.

set -euo pipefail

PR="${1:-${PR_NUMBER:-}}"
if [[ -z "$PR" ]]; then
  echo "usage: check-task-ritual.sh <pr-number>  (or set PR_NUMBER)" >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }

# GitHub occasionally answers with a transient HTML 5xx page ("invalid
# character '<'"); a deterministic wall must not flake on that, so every API
# read gets three attempts with a short pause.
api() {
  local attempt out
  for attempt in 1 2 3; do
    if out=$(gh api "$@" 2>&1); then
      printf '%s\n' "$out"
      return 0
    fi
    [[ $attempt -lt 3 ]] && sleep 2
  done
  printf '%s\n' "$out" >&2
  return 1
}

meta=$(api "repos/{owner}/{repo}/pulls/${PR}" --jq '[.user.login, .user.type] | @tsv')
IFS=$'\t' read -r author author_type <<< "$meta"

# Only dependency bots are exempt — they do not hold sessions. Cloud coding
# agents also author PRs as bots (user.type == "Bot"), and those *do* run
# sessions, so exemption is an explicit allowlist, never a bot-type check.
if [[ "$author_type" == "Bot" || "$author" == *"[bot]" ]]; then
  case " ${RITUAL_EXEMPT_BOTS:-dependabot[bot] renovate[bot] github-actions[bot]} " in
    *" ${author} "*)
      echo "PASS: PR #${PR} is authored by allowlisted bot ${author}; dependency bots do not hold sessions."
      exit 0
      ;;
    *)
      echo "note: PR #${PR} author ${author} is a bot but not allowlisted; the full start ritual applies."
      ;;
  esac
fi

body=$(api "repos/{owner}/{repo}/pulls/${PR}" --jq '.body // ""')

# The first task link names the primary Task under review.
link=$(printf '%s\n' "$body" \
  | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+' \
  | head -n1 || true)
if [[ -z "$link" ]]; then
  echo "FAIL: PR #${PR} body has no task link (e.g. 'Closes #N', or 'Refs #N' for post-merge acceptance)."
  echo "      Every PR must declare the Task it lands (plan-management, tracking graph)."
  exit 1
fi
issue="${link##*#}"

# One pass over the issue's comments, emitting a TSV marker per ritual
# artifact: TYPE, created_at, updated_at. The API returns ascending
# created_at, but earliest-of is computed with an explicit sort anyway.
markers=$(api "repos/{owner}/{repo}/issues/${issue}/comments" --paginate --jq '
  .[] |
  (if (.body | test("^(Starting|Resuming) in session")) then [ "CLAIM", .created_at, .updated_at ] | @tsv else empty end),
  (if ((.body | test("(^|\\n)## Plan\\b")) or (.body | startswith("Plan:"))) then [ "PLAN", .created_at, .updated_at ] | @tsv else empty end),
  (if (.body | test("^Dispatching worker")) then [ "DISPATCH", .created_at, .updated_at ] | @tsv else empty end),
  (if (.body | test("^Releasing worker")) then [ "RELEASE", .created_at, .updated_at ] | @tsv else empty end),
  (if (((.body | test("(^|\\n)## Plan\\b")) or (.body | startswith("Plan:"))) and (.body | ascii_downcase | contains("no worker will be spawned"))) then [ "EXEMPT", .created_at, .updated_at ] | @tsv else empty end)
')

ok=true
case "$markers" in
  *CLAIM*) ;;
  *) echo "FAIL: issue #${issue} has no start claim comment ('Starting in session …' or 'Resuming in session …')."
     ok=false ;;
esac
case "$markers" in
  *PLAN*) ;;
  *) echo "FAIL: issue #${issue} has no plan comment (a '## Plan' heading, or a body starting 'Plan:')."
     ok=false ;;
esac

if ! $ok; then
  echo "      Post the missing comment(s) on #${issue} — session-orchestration start ritual, steps 4-5 — then re-run this check."
  exit 1
fi

# Immutability — ritual comments are append-only; a revision lives in a
# fresh comment (session-orchestration, work loop). An edited ritual
# comment breaks the audit trail. EXEMPT rows are skipped: an exemption
# marker always doubles a PLAN row for the same comment, which already
# reports any edit.
edited=$(printf '%s\n' "$markers" | awk -F '\t' '$1 != "EXEMPT" && $2 != $3 { print $1 " created " $2 ", updated " $3 }')
if [[ -n "$edited" ]]; then
  echo "FAIL: issue #${issue} has ritual comment(s) edited after posting:"
  printf '%s\n' "$edited" | sed 's/^/        /'
  echo "      Ritual comments (claim, plan, dispatch, release) are immutable; post a fresh comment instead of editing (session-orchestration, work loop)."
  ok=false
fi

earliest_claim=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "CLAIM" { print $2 }' | sort | head -n1)
earliest_plan=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "PLAN" { print $2 }' | sort | head -n1)

# Chronology 1 — claim, then plan (session-orchestration steps 4-5).
if [[ "$earliest_claim" > "$earliest_plan" ]]; then
  echo "FAIL: issue #${issue} ritual is out of order: earliest claim (${earliest_claim}) postdates earliest plan (${earliest_plan})."
  echo "      Claim the task first, then post the plan (session-orchestration, steps 4-5)."
  ok=false
fi

# Chronology 2 — the plan precedes the code (AGENTS.md §2). Committer date
# is primary: rebases rewrite it forward, which only widens the margin,
# while amends preserve the author date — an author date may predate the
# plan even when the code followed it. Author date is only a fallback for
# commit objects lacking a committer date.
first_commit=$(api "repos/{owner}/{repo}/pulls/${PR}/commits" --paginate \
  --jq '.[].commit | ((.committer.date // .author.date) // empty)' | sort | head -n1)
if [[ -n "$first_commit" && "$earliest_plan" > "$first_commit" ]]; then
  echo "FAIL: PR #${PR}'s first commit (${first_commit}, committer date) predates the plan comment on issue #${issue} (${earliest_plan})."
  echo "      The plan of record is posted before implementation begins (AGENTS.md §2)."
  ok=false
fi

# Execution mode (ADR-0003 Decision 2) — every task shows either a
# worker-dispatch trail or a declared small-task exemption; an undeclared
# mode fails. Any dispatch comment selects the two-tier path and declared
# exemptions are then ignored: a replan from exemption to worker split is
# legitimate, and the dispatch trail is the stronger signal of what
# actually happened. The exemption marker is the exact phrase quoted in
# AGENTS.md §4, matched case-sensitively inside a plan comment.
mode_desc=""
if [[ "$markers" == *DISPATCH* ]]; then
  earliest_dispatch=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "DISPATCH" { print $2 }' | sort | head -n1)
  mode_desc="two-tier (dispatch ${earliest_dispatch})"

  # Chronology 3 — the dispatch follows the plan of record: the supervisor
  # dispatches a worker to execute an already-posted plan (ADR-0003).
  if [[ "$earliest_plan" > "$earliest_dispatch" ]]; then
    echo "FAIL: issue #${issue} ritual is out of order: earliest worker dispatch (${earliest_dispatch}) predates earliest plan (${earliest_plan})."
    echo "      Post the plan first, then the worker-dispatch comment (session-orchestration skill; ADR-0003)."
    ok=false
  fi

  # Chronology 4 — workers only start after dispatch, so the earliest
  # dispatch precedes the PR's first commit. Committer-date semantics as
  # above: rebases move committer dates forward, which only widens the
  # margin; equal stamps prove nothing, so ties pass.
  if [[ -n "$first_commit" && "$earliest_dispatch" > "$first_commit" ]]; then
    echo "FAIL: PR #${PR}'s first commit (${first_commit}, committer date) predates the worker-dispatch comment on issue #${issue} (${earliest_dispatch})."
    echo "      The supervisor dispatches the worker before implementation begins (ADR-0003; session-orchestration skill)."
    ok=false
  fi

  # One active worker per PR — every dispatch after the first must be
  # preceded by a release comment timestamped between the previous
  # dispatch and the new one, inclusive on both ends: a release stamped
  # in the same second as either dispatch cannot prove a violation.
  releases=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "RELEASE" { print $2 }' | sort)
  dispatches=$(printf '%s\n' "$markers" | awk -F '\t' '$1 == "DISPATCH" { print $2 }' | sort)
  prev_dispatch=""
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    if [[ -n "$prev_dispatch" ]]; then
      released=false
      while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        if [[ ! "$r" < "$prev_dispatch" && ! "$r" > "$d" ]]; then
          released=true
          break
        fi
      done <<< "$releases"
      if ! $released; then
        echo "FAIL: issue #${issue} dispatches a replacement worker (${d}) with no release comment between it and the previous dispatch (${prev_dispatch})."
        echo "      Release the active worker first ('Releasing worker …'), then dispatch the successor (session-orchestration skill; ADR-0003)."
        ok=false
      fi
    fi
    prev_dispatch="$d"
  done <<< "$dispatches"
elif [[ "$markers" == *EXEMPT* ]]; then
  mode_desc="declared small-task exemption"
else
  echo "FAIL: issue #${issue} declares no execution mode: no worker-dispatch comment ('Dispatching worker …' first line) and no plan comment containing 'no worker will be spawned'."
  echo "      Dispatch a worker or declare the small-task exemption in the plan comment (AGENTS.md §4; session-orchestration skill)."
  ok=false
fi

# Routing — the linked issue must be a Task in the tracking graph. The
# ai-task template applies 'type:task'; without it the issue is invisible
# to label-driven frontier queries, so a PR closing it lands untracked work.
if labels=$(api "repos/{owner}/{repo}/issues/${issue}" --jq '[.labels[].name] | join(" ")'); then
  case " ${labels} " in
    *" type:task "*) ;;
    *)
      echo "FAIL: issue #${issue} lacks the 'type:task' label (has: ${labels:-none})."
      echo "      Apply it with: gh issue edit ${issue} --add-label type:task (labels: .github/scripts/setup-labels.sh)."
      ok=false
      ;;
  esac
else
  echo "FAIL: could not read issue #${issue} metadata for the label check."
  ok=false
fi

# Provenance — the PR's plan link must resolve to the plan of record on the
# linked Task in this repository. The link is load-bearing for reviewers and
# future sessions; a dead link once passed CI and needed a human to catch.
plan_link=$(printf '%s\n' "$body" \
  | grep -oiE 'plan:[[:space:]]*https://github\.com/[^/[:space:]]+/[^/[:space:]]+/issues/[0-9]+#issuecomment-[0-9]+' \
  | head -n1 || true)
if [[ -z "$plan_link" ]]; then
  echo "FAIL: PR #${PR} body has no plan link ('Plan: https://github.com/<owner>/<repo>/issues/N#issuecomment-ID')."
  echo "      Link the plan comment posted on the Task (session-orchestration step 5; the PR template's Plan line)."
  ok=false
else
  # Parse a lowercased copy: GitHub treats owner/repo case-insensitively,
  # and the numeric fields are unaffected.
  plan_link_lc=$(printf '%s' "$plan_link" | tr '[:upper:]' '[:lower:]')
  link_repo=$(printf '%s\n' "$plan_link_lc" | sed -E 's|.*github\.com/([^/]+/[^/]+)/issues/.*|\1|')
  link_issue=$(printf '%s\n' "$plan_link_lc" | sed -E 's|.*/issues/([0-9]+)#issuecomment-[0-9]+.*|\1|')
  comment_id=$(printf '%s\n' "$plan_link_lc" | sed -E 's|.*#issuecomment-([0-9]+).*|\1|')
  # The comment-id lookup below is repository-scoped, so a link naming a
  # foreign repository could otherwise resolve to an unrelated local
  # comment that happens to share the id — reject it outright.
  if ! repo_full=$(api "repos/{owner}/{repo}" --jq '.full_name'); then
    echo "FAIL: could not resolve this repository's full name for the plan-link check."
    ok=false
  elif [[ "$link_repo" != "$(printf '%s' "$repo_full" | tr '[:upper:]' '[:lower:]')" ]]; then
    echo "FAIL: PR #${PR}'s plan link points at repository ${link_repo}, but the linked task lives in ${repo_full}."
    echo "      Link the plan comment on the linked Task in this repository."
    ok=false
  elif [[ "$link_issue" != "$issue" ]]; then
    echo "FAIL: PR #${PR}'s plan link points at issue #${link_issue}, but the PR's task link is #${issue}."
    ok=false
  elif resolved=$(api "repos/{owner}/{repo}/issues/comments/${comment_id}" --jq '
      [ (.issue_url | sub(".*/"; "")),
        (if ((.body | test("(^|\\n)## Plan\\b")) or (.body | startswith("Plan:"))) then "plan" else "other" end)
      ] | @tsv' 2>/dev/null); then
    IFS=$'\t' read -r comment_issue comment_kind <<< "$resolved"
    if [[ "$comment_issue" != "$issue" ]]; then
      echo "FAIL: PR #${PR}'s plan link resolves to issue #${comment_issue}, not the linked task #${issue}."
      ok=false
    elif [[ "$comment_kind" != "plan" ]]; then
      echo "FAIL: PR #${PR}'s plan link resolves to a comment that is not a plan comment (no '## Plan' heading or 'Plan:' prefix)."
      echo "      Link the plan of record itself — not the claim comment or a status update."
      ok=false
    fi
  else
    echo "FAIL: PR #${PR}'s plan link does not resolve: comment ${comment_id} not found on this repository."
    ok=false
  fi
fi

$ok || exit 1

echo "PASS: PR #${PR} → issue #${issue} ritual in order: claim ${earliest_claim} → plan ${earliest_plan} → first commit ${first_commit:-none}; mode: ${mode_desc}; plan link and type:task verified."
