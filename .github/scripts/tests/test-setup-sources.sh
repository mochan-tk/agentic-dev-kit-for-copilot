#!/usr/bin/env bash
# test-setup-sources.sh — regression tests for setup-sources.sh: usage
# errors, every preflight failure (including the Free+private hard
# stop), source selection, registry writes, dry-run, and idempotency.
# Sandboxed: fake git remotes plus the gh PATH shim — no network.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
WIZARD="$HERE/../setup-sources.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export GH_FIXTURES="$WORK/fixtures"
mkdir -p "$GH_FIXTURES"
install_gh_shim "$WORK"

# make_repo <dir> [remote-url] — sandbox git repo with an origin remote.
make_repo() {
  init_sandbox_repo "$1"
  git -C "$1" remote add origin "${2:-https://github.com/acme/widget.git}"
}

# fixtures <private> <owner-type> <user-plan> [org-plan] — (re)write the
# shim fixtures for one scenario. Owner login is always "acme"; user.json
# login "acme" makes user-owned repos self-owned.
fixtures() {
  printf '{"private":%s,"owner":{"login":"acme","type":"%s"}}\n' \
    "$1" "$2" > "$GH_FIXTURES/repo.json"
  printf '{"login":"acme","plan":{"name":"%s"}}\n' "$3" > "$GH_FIXTURES/user.json"
  if [ -n "${4:-}" ]; then
    printf '{"login":"acme","plan":{"name":"%s"}}\n' "$4" > "$GH_FIXTURES/org.json"
  else
    rm -f "$GH_FIXTURES/org.json"
  fi
}

run_wizard() { # run_wizard <repo-dir> <args...> — stdin closed (no TTY)
  local dir="$1"
  shift
  (cd "$dir" && bash "$WIZARD" "$@" < /dev/null)
}

# --- usage ----------------------------------------------------------------

expect_rc_grep 0 'Usage: setup-sources\.sh' "--help prints usage" \
  bash "$WIZARD" --help
expect_rc_grep 2 'unknown argument' "unknown flag is a usage error" \
  bash "$WIZARD" --bogus
expect_rc_grep 2 "unknown source 'kiro'" "unknown --source is a usage error" \
  bash "$WIZARD" --source kiro

# --- preflight ------------------------------------------------------------

NOREPO="$WORK/norepo"
mkdir -p "$NOREPO"
expect_rc_grep 1 'not inside a git repository' "outside a git repo fails" \
  run_wizard "$NOREPO" --source builtin --yes

NOREMOTE="$WORK/noremote"
init_sandbox_repo "$NOREMOTE"
expect_rc_grep 1 "no 'origin' remote" "missing remote fails" \
  run_wizard "$NOREMOTE" --source builtin --yes

ELSEWHERE="$WORK/elsewhere"
make_repo "$ELSEWHERE" "https://gitlab.example.com/acme/widget.git"
expect_rc_grep 1 'not a github\.com repository' "non-GitHub remote fails" \
  run_wizard "$ELSEWHERE" --source builtin --yes

REPO="$WORK/repo"
make_repo "$REPO"

rm -f "$GH_FIXTURES/user.json"   # gh api user 404s -> unauthenticated
expect_rc_grep 1 'gh is not authenticated' "unauthenticated gh fails" \
  run_wizard "$REPO" --source builtin --yes

fixtures true User free
expect_rc_grep 1 'Free plan is unsupported' \
  "private repo on Free plan is a hard stop" \
  run_wizard "$REPO" --source builtin --yes
expect_rc_grep 1 'visibility public|github\.com/pricing' \
  "hard stop lists remediation options" \
  run_wizard "$REPO" --source builtin --yes

fixtures true Organization pro   # org.json missing -> plan unknown
expect_rc_grep 1 'could not be determined' \
  "indeterminable plan on a private repo fails closed" \
  run_wizard "$REPO" --source builtin --yes

# --- selection ------------------------------------------------------------

fixtures false User free
expect_rc_grep 2 'no TTY: pass --source' "no TTY without --source errors" \
  run_wizard "$REPO"

mkdir -p "$REPO/specs"
expect_rc_grep 2 'consider --source speckit' \
  "specs/ detection surfaces in the no-TTY hint" \
  run_wizard "$REPO"
rmdir "$REPO/specs"

# --- writes ---------------------------------------------------------------

REG=".github/docs/context/SOURCES.md"

expect_rc_grep 0 'dry-run: would write' "dry-run prints the entry" \
  run_wizard "$REPO" --source builtin --dry-run
if [ ! -e "$REPO/$REG" ]; then
  t_ok "dry-run writes nothing"
else
  t_fail "dry-run writes nothing (file exists)"
fi

expect_rc_grep 0 "wrote $REG" "public repo on Free plan writes builtin" \
  run_wizard "$REPO" --source builtin --yes
if grep -q '^## builtin$' "$REPO/$REG" \
  && grep -q 'activation PR #<fill in' "$REPO/$REG" \
  && grep -q '^# Context sources registry$' "$REPO/$REG"; then
  t_ok "registry has header, builtin section, and pin placeholder"
else
  t_fail "registry has header, builtin section, and pin placeholder"
fi

expect_rc_grep 0 'already registered' "re-run with same source is a no-op" \
  run_wizard "$REPO" --source builtin --yes
COUNT="$(grep -c '^## builtin$' "$REPO/$REG")"
if [ "$COUNT" = "1" ]; then
  t_ok "idempotent re-run does not duplicate the section"
else
  t_fail "idempotent re-run does not duplicate the section (count=$COUNT)"
fi

expect_rc_grep 0 'CODEOWNERS' "adding speckit appends and prints PR-A steps" \
  run_wizard "$REPO" --source speckit --yes
if grep -q '^## builtin$' "$REPO/$REG" && grep -q '^## speckit$' "$REPO/$REG" \
  && [ "$(grep -c '^# Context sources registry$' "$REPO/$REG")" = "1" ]; then
  t_ok "second source appends without clobbering (single header)"
else
  t_fail "second source appends without clobbering (single header)"
fi
if grep -q 'adoption SHA <record the current' "$REPO/$REG"; then
  t_ok "speckit pin falls back to a placeholder without commits"
else
  t_fail "speckit pin falls back to a placeholder without commits"
fi

PAID="$WORK/paid"
make_repo "$PAID"
mkdir -p "$PAID/specs"
echo spec > "$PAID/specs/feature.md"
git -C "$PAID" add -A
git -C "$PAID" -c user.email=t@t -c user.name=t commit -qm specs
fixtures true User pro
expect_rc_grep 0 "wrote $REG" "private repo on a paid plan passes preflight" \
  run_wizard "$PAID" --source speckit --yes
SHA="$(git -C "$PAID" log -1 --format=%H -- specs/)"
if grep -q "adoption SHA $SHA" "$PAID/$REG"; then
  t_ok "speckit pin records the specs/** commit SHA when resolvable"
else
  t_fail "speckit pin records the specs/** commit SHA when resolvable"
fi

ORG="$WORK/org"
make_repo "$ORG"
fixtures true Organization free team
expect_rc_grep 0 "wrote $REG" "private org repo on a paid org plan passes" \
  run_wizard "$ORG" --source builtin --yes

t_summary
