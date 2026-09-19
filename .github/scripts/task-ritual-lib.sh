#!/usr/bin/env bash
# Shared CI grammar. Keep permissive historical markers distinct from CLI input validation.
# Consumed by scripts sourcing this library.
# shellcheck disable=SC2034
RITUAL_JQ='
  def ritual_claim: test("^(Starting|Resuming) in session");
  def ritual_plan: test("(^|\\n)## Plan\\b") or startswith("Plan:");
  def ritual_dispatch: test("^Dispatching worker");
  def ritual_release: test("^Releasing worker");
  def ritual_markers:
    .[] |
    (if (.body | ritual_claim) then ["CLAIM", .created_at, .updated_at] | @tsv else empty end),
    (if (.body | ritual_plan) then ["PLAN", .created_at, .updated_at] | @tsv else empty end),
    (if (.body | ritual_dispatch) then ["DISPATCH", .created_at, .updated_at, (.body | split("\n")[0])] | @tsv else empty end),
    (if (.body | ritual_release) then ["RELEASE", .created_at, .updated_at] | @tsv else empty end),
    (if ((.body | ritual_plan) and (.body | ascii_downcase | contains("no worker will be spawned"))) then ["EXEMPT", .created_at, .updated_at] | @tsv else empty end);
'

ritual_has_session() {
  printf '%s\n' "$1" | grep -qE 'session[[:space:]]+[0-9a-fA-F-]{8,}'
}

ritual_branch() {
  printf '%s\n' "$1" | sed -n 's/.*branch[[:space:]]\{1,\}\([^ ,)]\{1,\}\).*/\1/p'
}

ritual_branch_matches() {
  [[ "$1" == "$2" || "$2" == *"$1" ]]
}

ritual_task_link() {
  grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?)[[:space:]]+([A-Za-z]+[[:space:]]+)?#[0-9]+' | head -n1 || true
}

ritual_plan_link() {
  grep -oiE 'plan:[[:space:]]*https://github\.com/[^/[:space:]]+/[^/[:space:]]+/issues/[0-9]+#issuecomment-[0-9]+' | head -n1 || true
}

ritual_dispatch_rows() {
  sort -s -t $'\t' -k2,2 | awk -F '\t' '
    $1 == "DISPATCH" { dispatches[++n] = $0; times[n] = $2 }
    $1 == "RELEASE" { releases[++nr] = $2 }
    END {
      for (i = 1; i <= n; i++) {
        superseded = 0
        for (j = i + 1; j <= n && !superseded; j++) {
          for (r = 1; r <= nr; r++) {
            if (releases[r] >= times[i] && releases[r] <= times[j]) {
              superseded = 1
              break
            }
          }
        }
        print dispatches[i] "\t" superseded
      }
    }'
}
