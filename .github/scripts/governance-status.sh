#!/usr/bin/env bash
# governance-status.sh — read-only default-branch governance sensor
# (ADR-0004 decisions 1, 2, 4, 5). Compares effective branch rules, Actions
# posture, CODEOWNERS tuning, and merge-queue applicability against an
# explicitly declared solo or team intent (solo = the setup-ruleset.sh
# minimum; stronger observed settings never make solo unhealthy). Aggregates
# every active rule source including parent rulesets, qualifies
# ruleset-derived controls with their bypass actors, and reports missing
# evidence as UNKNOWN or UNCHECKABLE — never as safe. GET-only; nothing is
# mutated and no profile is persisted.
#
# Output: deterministic `key<TAB>state<TAB>detail` lines.
# Exit: 0 healthy with complete evidence; 1 required control OFF;
#       2 usage or dependency error; 3 required evidence missing (beats 1).

set -u

usage() {
  echo "Usage: governance-status.sh -R owner/repo [--profile solo|team]" >&2
  echo "                            [--checks ctx1,ctx2,...]" >&2
  exit 2
}

REPO="" PROFILE=""
CHECKS="quality,task-ritual,scaffold-self-check,copilot-surface"
while [ $# -gt 0 ]; do
  case "$1" in
    -R|--repo) [ -n "${2:-}" ] || usage; REPO="$2"; shift 2 ;;
    --profile)
      case "${2:-}" in solo|team) PROFILE="$2" ;; *) usage ;; esac
      shift 2 ;;
    --checks) [ -n "${2:-}" ] || usage; CHECKS="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$REPO" ] || usage
case "$REPO" in */*) ;; *) usage ;; esac
CHECKS="$(printf '%s' "$CHECKS" | tr -d ' ' | tr -s ',' | sed 's/^,//;s/,$//')"
[ -n "$CHECKS" ] || usage
command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/governance-status.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
TAB="$(printf '\t')"

BASE=0 TEAM=0 UNMET=0 MISSING=0
[ -z "$PROFILE" ] || BASE=1
[ "$PROFILE" != team ] || TEAM=1

# fetch <name> <path> [raw] — read-only GET; records ok|404|fail in
# $WORK/<name>.rc. The only gh invocation shape this sensor ever uses.
fetch() {
  local name="$1" path="$2" rc=0
  if [ "${3:-}" = raw ]; then
    gh api -H "Accept: application/vnd.github.raw" "$path" \
      > "$WORK/$name.json" 2> "$WORK/$name.err" || rc=$?
  else
    gh api "$path" > "$WORK/$name.json" 2> "$WORK/$name.err" || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then echo ok
  elif grep -q "HTTP 404" "$WORK/$name.err"; then echo 404
  else echo fail
  fi > "$WORK/$name.rc"
}
st() { cat "$WORK/$1.rc" 2>/dev/null || echo fail; }
jqr() { jq -r "$1" "$WORK/$2.json"; }

# emit <key> <state> <detail> <required-flag> — required OFF counts toward
# exit 1; required UNKNOWN/UNCHECKABLE counts toward exit 3 (which outranks).
emit() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
  [ "${4:-0}" = 1 ] || return 0
  case "$2" in
    OFF) UNMET=$((UNMET + 1)) ;;
    UNKNOWN|UNCHECKABLE) MISSING=$((MISSING + 1)) ;;
  esac
}

fetch repo "repos/$REPO"
DEFB="" OWNER=""
if [ "$(st repo)" = ok ]; then
  DEFB="$(jqr '.default_branch // empty' repo)"
  OWNER="$(jqr '.owner.type // empty' repo)"
fi
if [ -n "$DEFB" ]; then
  fetch rules "repos/$REPO/rules/branches/$DEFB"
  fetch wf "repos/$REPO/actions/permissions/workflow"
  fetch runs "repos/$REPO/commits/$DEFB/check-runs?per_page=100"
  fetch clog "repos/$REPO/contents/SCAFFOLD-CHANGELOG.md?ref=$DEFB" raw
else
  for name in rules wf runs clog; do echo fail > "$WORK/$name.rc"; done
fi
RULES=0
[ "$(st rules)" != ok ] || RULES=1

# Aggregate every effective rule of a type across all active sources: the
# strongest approval threshold, any-source booleans, and the union of
# contributing ruleset ids. One named ruleset is never the answer.
PRN=0 APPR=0 DSM=false LPA=false COR=false RTR=false STRICT=false MQN=0
PRSRC="" RSCSRC="" MQSRC=""
if [ "$RULES" = 1 ]; then
  # shellcheck disable=SC2016  # single-quoted jq program, as in setup-ruleset.sh
  IFS="$TAB" read -r PRN APPR DSM LPA COR RTR STRICT MQN PRSRC RSCSRC MQSRC <<EOF
$(jqr '[.[]|select(.type=="pull_request")] as $p
  | [.[]|select(.type=="required_status_checks")] as $c
  | [.[]|select(.type=="merge_queue")] as $m
  | def srcs(x): ([x[].ruleset_id]|unique|map(tostring)|join(","))
      | if . == "" then "-" else . end;
  [($p|length),
   ([$p[].parameters.required_approving_review_count]|max // 0),
   ([$p[].parameters.dismiss_stale_reviews_on_push]|any),
   ([$p[].parameters.require_last_push_approval]|any),
   ([$p[].parameters.require_code_owner_review]|any),
   ([$p[].parameters.required_review_thread_resolution]|any),
   ([$c[].parameters.strict_required_status_checks_policy]|any),
   ($m|length), srcs($p), srcs($c), srcs($m)] | @tsv' rules)
EOF
  [ -n "$PRN" ] || RULES=0
  for v in PRSRC RSCSRC MQSRC; do
    eval "[ \"\$$v\" != - ] || $v=\"\""
  done
fi

# Fetch every contributing ruleset detail: bypass actors qualify the claim,
# and a failed detail read is UNKNOWN, never an empty bypass list.
if [ "$RULES" = 1 ]; then
  jqr '[.[]|{id:.ruleset_id,t:.ruleset_source_type,s:.ruleset_source}]
    | unique_by(.id)[] | "\(.id)\t\(.t)\t\(.s)"' rules > "$WORK/srcs"
else
  : > "$WORK/srcs"
fi
while IFS="$TAB" read -r rid rtyp rsrc; do
  [ -n "$rid" ] || continue
  case "$rtyp" in
    Repository) fetch "rs$rid" "repos/$rsrc/rulesets/$rid" ;;
    Organization) fetch "rs$rid" "orgs/$rsrc/rulesets/$rid" ;;
    *) echo fail > "$WORK/rs$rid.rc" ;;
  esac
  [ "$(st "rs$rid")" = ok ] || continue
  jqr '.bypass_actors // [] | sort_by(.actor_type, .actor_id)[]
    | "actor_type=\(.actor_type) actor_id=\(.actor_id // "none") bypass_mode=\(.bypass_mode)"' \
    "rs$rid" > "$WORK/actors.$rid"
  jqr '.bypass_actors // [] | sort_by(.actor_type, .actor_id)
    | map("\(.actor_type):\(.actor_id // "none"):\(.bypass_mode)") | join(",")' \
    "rs$rid" > "$WORK/qual.$rid"
done < "$WORK/srcs"

# qual_for <csv-ruleset-ids> — visible bypass qualifier for a ruleset-derived
# control; unknown evidence is surfaced, never dropped.
qual_for() {
  local ids="$1" id q acc=""
  QUAL=""
  [ -n "$ids" ] || return 0
  printf '%s\n' "$ids" | tr ',' '\n' > "$WORK/qids"
  while IFS= read -r id; do
    if [ "$(st "rs$id")" != ok ]; then QUAL=" bypass=unknown"; return 0; fi
    q="$(cat "$WORK/qual.$id")"
    [ -z "$q" ] || acc="$acc,$q"
  done < "$WORK/qids"
  [ -z "$acc" ] || QUAL=" bypass=${acc#,}"
}
qual_for "$PRSRC"; PQ="$QUAL"
qual_for "$RSCSRC"; CQ="$QUAL"
qual_for "$MQSRC"; MQQ="$QUAL"

if [ -n "$DEFB" ]; then emit repository.default_branch ACTIVE "$DEFB" "$BASE"
else emit repository.default_branch UNKNOWN "repository metadata unavailable" "$BASE"; fi
if [ -n "$PROFILE" ]; then emit governance.profile ACTIVE "$PROFILE" 1
else emit governance.profile UNKNOWN "no profile declared; pass --profile solo|team" 1; fi
if [ "$RULES" != 1 ]; then
  emit pull_request.required_approving_review_count UNKNOWN "effective rules unavailable" "$BASE"
elif [ "$PRN" = 0 ] || [ "$APPR" -lt 1 ]; then
  emit pull_request.required_approving_review_count OFF "count=$APPR (no approving-review requirement)" "$BASE"
else
  emit pull_request.required_approving_review_count ACTIVE "count=$APPR$PQ" "$BASE"
fi

# rule_row <key> <rule-count> <bool> <qual> <absent-detail> <required>
rule_row() {
  if [ "$RULES" != 1 ]; then emit "$1" UNKNOWN "effective rules unavailable" "$6"
  elif [ "$2" = 0 ]; then emit "$1" OFF "$5" "$6"
  elif [ "$3" = true ]; then emit "$1" ACTIVE "true$4" "$6"
  else emit "$1" OFF "false$4" "$6"
  fi
}
rule_row pull_request.dismiss_stale_reviews "$PRN" "$DSM" "$PQ" "no pull_request rule in effect" "$TEAM"
rule_row pull_request.require_last_push_approval "$PRN" "$LPA" "$PQ" "no pull_request rule in effect" "$TEAM"
rule_row pull_request.require_code_owner_review "$PRN" "$COR" "$PQ" "no pull_request rule in effect" "$TEAM"
rule_row pull_request.required_review_thread_resolution "$PRN" "$RTR" "$PQ" "no pull_request rule in effect" "$TEAM"
RSCN=0
[ -z "$RSCSRC" ] || RSCN=1
rule_row required_checks.strict_policy "$RSCN" "$STRICT" "$CQ" "no required_status_checks rule in effect" "$TEAM"

# Requested contexts: presence is required for both profiles; source binding
# (configured integration vs the observed issuing GitHub App ID — an App ID,
# not an installation ID) is informational N/A for solo, required for team.
printf '%s\n' "$CHECKS" | tr ',' '\n' > "$WORK/ctxs"
while IFS= read -r ctx; do
  [ -n "$ctx" ] || continue
  pres=unknown cfg=unknown obs=unknown
  if [ "$RULES" = 1 ]; then
    IFS="$TAB" read -r pres cfg <<EOF
$(jq -r --arg c "$ctx" '[.[]|select(.type=="required_status_checks")
  .parameters.required_status_checks[]|select(.context==$c)] as $e
  | [($e|length), ([$e[].integration_id // empty]|unique|map(tostring)
  | join(",") | if . == "" then "none" else . end)] | @tsv' "$WORK/rules.json")
EOF
  fi
  if [ "$(st runs)" = ok ]; then
    obs="$(jq -r --arg c "$ctx" '[.check_runs[]|select(.name==$c)|.app.id // "none"]
      | unique|map(tostring)|join(",") | if . == "" then "none" else . end' "$WORK/runs.json")"
  fi
  if [ "$pres" = unknown ]; then emit "required_checks.context.$ctx" UNKNOWN "effective rules unavailable" "$BASE"
  elif [ "$pres" -gt 0 ]; then emit "required_checks.context.$ctx" ACTIVE "required by effective rules$CQ" "$BASE"
  else emit "required_checks.context.$ctx" OFF "not required by effective rules" "$BASE"; fi
  det="configured=$cfg observed=$obs"
  if [ "$TEAM" != 1 ]; then emit "required_check_source.$ctx" N/A "$det (informational for solo intent)" 0
  elif [ "$cfg" = unknown ]; then emit "required_check_source.$ctx" UNKNOWN "$det; effective rules unavailable" 1
  elif [ "$obs" = unknown ]; then emit "required_check_source.$ctx" UNKNOWN "$det; check-run evidence unavailable" 1
  elif [ "$obs" = none ]; then emit "required_check_source.$ctx" UNCHECKABLE "$det; no check run observed" 1
  elif [ "${obs#*,}" != "$obs" ]; then emit "required_check_source.$ctx" UNCHECKABLE "multiple issuing app ids: $obs" 1
  elif [ "$cfg" != "$obs" ]; then emit "required_check_source.$ctx" OFF "$det" 1
  else emit "required_check_source.$ctx" ACTIVE "$det" 1; fi
done < "$WORK/ctxs"

if [ "$(st wf)" = ok ]; then
  PERM="$(jqr '.default_workflow_permissions // "unknown"' wf)"
  APPROVE="$(jqr '.can_approve_pull_request_reviews' wf)"
  if [ "$PERM" = read ]; then emit actions.default_workflow_permissions ACTIVE read "$BASE"
  else emit actions.default_workflow_permissions OFF "$PERM (expected read)" "$BASE"; fi
  if [ "$APPROVE" = false ]; then emit actions.can_approve_pull_request_reviews ACTIVE false "$BASE"
  else emit actions.can_approve_pull_request_reviews OFF "$APPROVE (expected false)" "$BASE"; fi
else
  emit actions.default_workflow_permissions UNKNOWN "actions permissions unavailable" "$BASE"
  emit actions.can_approve_pull_request_reviews UNKNOWN "actions permissions unavailable" "$BASE"
fi

# CODEOWNERS tuning, read from the default branch. A template tree
# (scaffold marker sha=unknown) legitimately carries CUSTOMIZE guidance.
MARKER=""
if [ "$(st clog)" = ok ]; then
  MARKER="$(sed -n 's/.*scaffold-version:.* sha=\([^ ]*\).*/\1/p' "$WORK/clog.json" | head -n 1)"
fi
if [ "$(st clog)" != ok ] || [ -z "$MARKER" ]; then
  emit codeowners.tuning UNKNOWN "scaffold marker unavailable on default branch" "$TEAM"
elif [ "$MARKER" = unknown ]; then
  emit codeowners.tuning N/A "template tree (sha=unknown); CUSTOMIZE guidance is expected" "$TEAM"
else
  fetch co "repos/$REPO/contents/.github/CODEOWNERS?ref=$DEFB" raw
  case "$(st co)" in
    ok)
      if grep -q CUSTOMIZE "$WORK/co.json"; then
        emit codeowners.tuning OFF "adopted tree with unresolved CUSTOMIZE ownership" "$TEAM"
      else
        emit codeowners.tuning ACTIVE "tuned CODEOWNERS on default branch (sha=$MARKER)" "$TEAM"
      fi ;;
    404) emit codeowners.tuning OFF "adopted tree without .github/CODEOWNERS" "$TEAM" ;;
    *) emit codeowners.tuning UNKNOWN "CODEOWNERS evidence unreadable" "$TEAM" ;;
  esac
fi

if [ "$(st repo)" != ok ]; then emit merge_queue.applicability UNKNOWN "repository metadata unavailable" 0
elif [ "$OWNER" = User ]; then emit merge_queue.applicability N/A "owner_type=User; merge queue not applicable" 0
elif [ "$RULES" = 1 ] && [ "$MQN" -gt 0 ]; then emit merge_queue.applicability ACTIVE "merge_queue rule active$MQQ" 0
elif [ "$(jqr '.private' repo)" = true ] && [ "$(jqr '.plan.name // empty' repo)" = free ]; then
  emit merge_queue.applicability N/A "private repository on free plan is ineligible" 0
elif [ "$RULES" != 1 ]; then emit merge_queue.applicability UNKNOWN "effective rules unavailable" 0
else emit merge_queue.applicability UNCHECKABLE "organization repository without plan, rule, or merge_group evidence" 0; fi

while IFS="$TAB" read -r rid rtyp rsrc; do
  [ -n "$rid" ] || continue
  if [ "$(st "rs$rid")" = ok ]; then
    n="$(wc -l < "$WORK/actors.$rid" | tr -d ' ')"
    emit "bypass.ruleset.$rid" ACTIVE "source=$rtyp:$rsrc actors=$n" "$BASE"
    i=0
    while IFS= read -r actor; do
      i=$((i + 1))
      emit "bypass.ruleset.$rid.actor.$i" ACTIVE "$actor" 0
    done < "$WORK/actors.$rid"
  else
    emit "bypass.ruleset.$rid" UNKNOWN "ruleset detail unavailable ($rtyp:$rsrc)" "$BASE"
  fi
done < "$WORK/srcs"

[ "$MISSING" -eq 0 ] || exit 3
[ "$UNMET" -eq 0 ] || exit 1
exit 0
