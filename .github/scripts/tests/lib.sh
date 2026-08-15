#!/usr/bin/env bash
# lib.sh — shared helpers for the guard regression tests (sourced, not run).
#
# Provides a tiny TAP-ish assertion layer and sandbox builders. Every test
# file sources this, registers cases with expect_rc, and finishes with
# t_summary (which sets the file's exit code). Dependencies: bash 3.2+,
# git, mktemp — nothing else.

TESTS_RUN=0
TESTS_FAILED=0

# Negative ritual fixtures deliberately make API reads fail. Production waits
# two seconds before retrying a transient GitHub error; an offline JSON
# fixture will not recover with time, so tests retain all three attempts and
# remove only the pause. Respect an explicit caller value for retry-contract
# tests.
export RITUAL_API_RETRY_DELAY="${RITUAL_API_RETRY_DELAY:-0}"

t_ok() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "ok - $1"
}

t_fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "not ok - $1"
}

# expect_rc <expected-rc> <case-name> <command...>
# Runs the command, compares its exit code, and dumps the captured output
# as diagnostics when the expectation is missed.
expect_rc() {
  local want="$1" name="$2" rc=0 out
  shift 2
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq "$want" ]; then
    t_ok "$name"
  else
    t_fail "$name (rc=$rc, want $want)"
    printf '%s\n' "$out" | sed 's/^/    # /'
  fi
}

# expect_rc_grep <expected-rc> <ere-pattern> <case-name> <command...>
# Like expect_rc, but the captured output must also match the extended
# regex — pins a rule to its distinct message, not just its exit code.
expect_rc_grep() {
  local want="$1" pat="$2" name="$3" rc=0 out
  shift 3
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" -eq "$want" ] && printf '%s\n' "$out" | grep -Eq "$pat"; then
    t_ok "$name"
  else
    t_fail "$name (rc=$rc, want $want; pattern: $pat)"
    printf '%s\n' "$out" | sed 's/^/    # /'
  fi
}

# t_summary — print the tally; exit code reflects failures.
t_summary() {
  echo "# $TESTS_RUN case(s), $TESTS_FAILED failed"
  [ "$TESTS_FAILED" -eq 0 ]
}

# init_sandbox_repo <dir> — create the directory and an empty git repo in
# it. The guards read the index via git ls-files, so staging (no commit,
# no identity) is enough.
init_sandbox_repo() {
  mkdir -p "$1"
  git -c init.defaultBranch=main init -q "$1"
}

# stage_all <repo-dir> — stage everything for git ls-files to see.
stage_all() {
  git -C "$1" add -A
}

# install_gh_shim <work-dir> — put a fake `gh` first in PATH that serves
# `gh api <path> [--paginate] --jq <expr>` from JSON fixtures in
# $GH_FIXTURES: pull.json (PR endpoint), commits.json (PR commits),
# comments.json (issue comments list), comment.json (single comment by
# id), issue.json (issue metadata), contents.json (repository contents
# endpoint; contents-changelog.json for SCAFFOLD-CHANGELOG.md), repo.json
# (bare repository endpoint), user.json (authenticated user), org.json
# (organization endpoint). jq runs with -r to mirror gh's raw --jq output.
# No network, no auth, no repository state. A missing fixture file exits
# non-zero, which models a 404 to the caller.
install_gh_shim() {
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "api" ] || { echo "gh shim: unsupported invocation: $*" >&2; exit 64; }
shift
path="" jq_expr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jq_expr="$2"; shift 2 ;;
    --paginate) shift ;;
    *) path="$1"; shift ;;
  esac
done
# `*` matches `/` in case patterns; specific mappings must precede the
# generic ones (commits before pulls, comment-by-id and comments-list
# before the bare issue endpoint).
case "$path" in
  user) fixture="$GH_FIXTURES/user.json" ;;
  orgs/*) fixture="$GH_FIXTURES/org.json" ;;
  repos/*/pulls/*/commits) fixture="$GH_FIXTURES/commits.json" ;;
  repos/*/pulls/*/files*) fixture="$GH_FIXTURES/pull-files.json" ;;
  repos/*/pulls/*) fixture="$GH_FIXTURES/pull.json" ;;
  repos/*/contents/SCAFFOLD-CHANGELOG.md*) fixture="$GH_FIXTURES/contents-changelog.json" ;;
  repos/*/contents/AGENTS.md*) fixture="$GH_FIXTURES/contents-agents.json" ;;
  repos/*/contents/*) fixture="$GH_FIXTURES/contents.json" ;;
  repos/*/issues/comments/*) fixture="$GH_FIXTURES/comment.json" ;;
  repos/*/issues/*/comments) fixture="$GH_FIXTURES/comments.json" ;;
  repos/*/issues/*) fixture="$GH_FIXTURES/issue.json" ;;
  # bare repository endpoint — keep last of the repos/* patterns: `*`
  # matches `/`, so this would swallow every deeper path if moved up.
  repos/*) fixture="$GH_FIXTURES/repo.json" ;;
  *) echo "gh shim: no fixture mapped for '$path'" >&2; exit 64 ;;
esac
# An absent fixture stands for a 404. The scaffold reads several paths that
# legitimately do not exist (a base branch without AGENTS.md is the whole
# signal of the adoption exemption), so a missing file must fail the way the
# API does — exit 1 — not as a shim error.
[ -f "$fixture" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
jq -r "$jq_expr" "$fixture"
SHIM
  chmod +x "$1/bin/gh"
  PATH="$1/bin:$PATH"
  export PATH
}
