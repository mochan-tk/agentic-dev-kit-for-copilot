#!/usr/bin/env bash
# test-scaffold-init.sh — regression tests for .github/scripts/scaffold-init.sh.
#
# Every case runs the installer against a throwaway target repo. Most point
# SCAFFOLD_SOURCE_DIR at a local fixture template tree; the fetch-path cases
# shim gh/git/curl on PATH instead — so no network is ever touched. Cases
# cover the clean install, seed-only files, collision refusal, --force,
# --upgrade class-split refresh, --dry-run inertness, app-content
# preservation, provenance, argument errors, and unauthenticated-gh fallback.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/scaffoldtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

INIT="$REPO_ROOT/.github/scripts/scaffold-init.sh"

# Fixture template tree — a miniature scaffold with every path class the
# installer treats differently (always / seed-if-absent / never).
FIXTURE="$WORK/template"
mkdir -p "$FIXTURE/.github/scripts" "$FIXTURE/.github/docs" "$FIXTURE/.vscode"
echo "# fixture agents" > "$FIXTURE/AGENTS.md"
cat > "$FIXTURE/SCAFFOLD-CHANGELOG.md" <<'EOF'
# Scaffold Changelog & Lineage

**Scaffold version adopted by this instance:** v9.9.9 *(fixture)*

## Versions
EOF
echo "# fixture readme" > "$FIXTURE/README.md"
echo "fixture-ignore" > "$FIXTURE/.gitignore"
# Mirrors the real template's rule set so the autocrlf regression case
# below proves the seeded pin silences every staged path.
cat > "$FIXTURE/.gitattributes" <<'EOF'
.github/** text eol=lf
.gitattributes text eol=lf
.gitignore text eol=lf
AGENTS.md text eol=lf
README.md text eol=lf
SCAFFOLD-CHANGELOG.md text eol=lf
EOF
echo "FIXTURE LICENSE TEXT" > "$FIXTURE/LICENSE"
echo '{"servers":{}}' > "$FIXTURE/.vscode/mcp.json"
echo "echo guard" > "$FIXTURE/.github/scripts/some-guard.sh"
echo "# fixture doc" > "$FIXTURE/.github/docs/thing.md"
# Tuned-class representatives (kept on --upgrade collisions): the Sync
# Triangle file and a workflow.
mkdir -p "$FIXTURE/.github/workflows"
echo "PRISTINE INSTRUCTIONS" > "$FIXTURE/.github/copilot-instructions.md"
echo "ci: v1" > "$FIXTURE/.github/workflows/ci.yml"

# run_init <target-dir> [flags...] — invoke the installer inside the target
# with the fixture as source. A wrapper function keeps expect_rc call sites
# one line each.
run_init() {
  local dir="$1"
  shift
  (cd "$dir" && SCAFFOLD_SOURCE_DIR="$FIXTURE" bash "$INIT" "$@")
}

SANDBOX_N=0
new_target() {
  SANDBOX_N=$((SANDBOX_N + 1))
  TARGET="$WORK/target$SANDBOX_N"
  init_sandbox_repo "$TARGET"
}

# --- clean install: rc 0, scaffold set staged, seeds included -------------
new_target
expect_rc_grep 0 "Scaffold installed from" "clean install succeeds with handoff banner" run_init "$TARGET"
staged=$(git -C "$TARGET" diff --cached --name-only | sort | tr '\n' ' ')
case "$staged" in
  *".github/docs/thing.md"*".github/scripts/some-guard.sh"*"AGENTS.md"*"README.md"*"SCAFFOLD-CHANGELOG.md"*)
    t_ok "clean install stages the scaffold set (incl. seeded README)" ;;
  *)
    t_fail "clean install stages the scaffold set (staged: $staged)" ;;
esac
if [ -f "$TARGET/.gitignore" ]; then
  t_ok "clean install seeds .gitignore when absent"
else
  t_fail "clean install seeds .gitignore when absent"
fi
if [ -f "$TARGET/.gitattributes" ] && git -C "$TARGET" diff --cached --name-only | grep -qx ".gitattributes"; then
  t_ok "clean install seeds and stages .gitattributes when absent"
else
  t_fail "clean install seeds and stages .gitattributes when absent"
fi
if [ ! -e "$TARGET/LICENSE" ] && [ ! -e "$TARGET/.vscode" ]; then
  t_ok "LICENSE and .vscode are never installed"
else
  t_fail "LICENSE and .vscode are never installed"
fi
if grep -q "^\*\*Adopted:\*\* from .*local tree" "$TARGET/SCAFFOLD-CHANGELOG.md"; then
  t_ok "provenance line appended to the target changelog"
else
  t_fail "provenance line appended to the target changelog"
fi
if git -C "$TARGET" log -1 >/dev/null 2>&1; then
  t_fail "installer must stage, never commit"
else
  t_ok "installer must stage, never commit"
fi

# --- progress: a real run narrates its phases (#165) ------------------------
# One plain line per slow phase — no \r or terminal control, so the piped
# output captured here contains them verbatim.
new_target
OUT_PROG="$WORK/progress-out.txt"
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$FIXTURE" bash "$INIT") > "$OUT_PROG" 2>&1
if grep -q "^using local source tree " "$OUT_PROG" \
   && grep -q "^computing the file plan" "$OUT_PROG" \
   && grep -Eq "^installing [0-9]+ file\(s\)" "$OUT_PROG" \
   && grep -q "^staging installed files" "$OUT_PROG"; then
  t_ok "real run prints one status line per phase"
else
  t_fail "real run prints one status line per phase"
  sed 's/^/    # /' "$OUT_PROG"
fi
if ! grep -q $'\r' "$OUT_PROG"; then
  t_ok "status lines carry no carriage returns or control sequences"
else
  t_fail "status lines carry no carriage returns or control sequences"
fi
OUT_DRYP="$WORK/progress-dry-out.txt"
new_target
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$FIXTURE" bash "$INIT" --dry-run) > "$OUT_DRYP" 2>&1
if ! grep -Eq "^(using local source tree|computing the file plan|installing [0-9]+|staging installed files)" "$OUT_DRYP"; then
  t_ok "--dry-run output carries no status lines"
else
  t_fail "--dry-run output carries no status lines"
  sed 's/^/    # /' "$OUT_DRYP"
fi

# --- banner: Windows note is MSYS-shell-gated (#169) ------------------------
# Git for Windows exports MSYSTEM; with it set the banner must point the
# 'bash ...' next steps at Git Bash. The negative case forces MSYSTEM
# empty so the suite stays green when run on a real Git Bash.
new_target
OUT_MSYS="$WORK/banner-msys-out.txt"
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$FIXTURE" MSYSTEM=MINGW64 bash "$INIT") > "$OUT_MSYS" 2>&1
if grep -q "Windows note: run the 'bash ...' steps above inside Git Bash" "$OUT_MSYS"; then
  t_ok "banner shows the Git Bash note when MSYSTEM is set"
else
  t_fail "banner shows the Git Bash note when MSYSTEM is set"
  sed 's/^/    # /' "$OUT_MSYS"
fi
new_target
OUT_POSIX="$WORK/banner-posix-out.txt"
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$FIXTURE" MSYSTEM='' bash "$INIT") > "$OUT_POSIX" 2>&1
if ! grep -q "Windows note" "$OUT_POSIX"; then
  t_ok "banner stays note-free when MSYSTEM is empty"
else
  t_fail "banner stays note-free when MSYSTEM is empty"
fi

# --- collision: default run refuses and leaves the target pristine --------
new_target
echo "app-owned agents file" > "$TARGET/AGENTS.md"
expect_rc_grep 1 "refusing to overwrite existing files" "collision without --force exits 1 and names the file" run_init "$TARGET"
if [ "$(cat "$TARGET/AGENTS.md")" = "app-owned agents file" ] && [ ! -e "$TARGET/.github" ]; then
  t_ok "refused run changes nothing in the target"
else
  t_fail "refused run changes nothing in the target"
fi

# --- collision + --force overwrites the colliding file --------------------
new_target
echo "app-owned agents file" > "$TARGET/AGENTS.md"
expect_rc_grep 0 "overwrote   AGENTS.md" "--force run succeeds and reports the overwrite" run_init "$TARGET" --force
if [ "$(cat "$TARGET/AGENTS.md")" = "# fixture agents" ]; then
  t_ok "--force overwrites the colliding file"
else
  t_fail "--force overwrites the colliding file"
fi

# --- dry run prints the plan and is bit-inert ------------------------------
new_target
echo "pre-existing" > "$TARGET/AGENTS.md"
expect_rc_grep 0 "CONFLICT   AGENTS.md" "--dry-run reports conflicts in the plan" run_init "$TARGET" --dry-run
if ! git -C "$TARGET" status --porcelain | grep -qv '^?? AGENTS.md$' && [ ! -e "$TARGET/.github" ]; then
  t_ok "--dry-run leaves the target untouched"
else
  t_fail "--dry-run leaves the target untouched"
fi

# --- app content preserved: own README + docs/ survive a clean install ----
new_target
echo "the app's real readme" > "$TARGET/README.md"
mkdir -p "$TARGET/docs"
echo "app doc" > "$TARGET/docs/index.md"
expect_rc_grep 0 "kept your existing README.md" "install into an app repo reports the kept README" run_init "$TARGET"
if [ "$(cat "$TARGET/README.md")" = "the app's real readme" ] && [ "$(cat "$TARGET/docs/index.md")" = "app doc" ]; then
  t_ok "app README.md and docs/ are preserved verbatim"
else
  t_fail "app README.md and docs/ are preserved verbatim"
fi

# --- existing .gitattributes: kept byte-identical, reported ----------------
new_target
echo "*.bin binary" > "$TARGET/.gitattributes"
expect_rc_grep 0 "kept your existing .gitattributes" "install reports the kept .gitattributes" run_init "$TARGET"
if [ "$(cat "$TARGET/.gitattributes")" = "*.bin binary" ]; then
  t_ok "existing .gitattributes is preserved verbatim"
else
  t_fail "existing .gitattributes is preserved verbatim"
fi

# --- CRLF regression (#166): autocrlf=true install stages warning-free -----
# The seeded .gitattributes is copied before the git add phase, so the LF
# pin is already active when files are staged. Reproduces on every
# platform: core.autocrlf=true makes git add warn about LF files anywhere.
new_target
git -C "$TARGET" config core.autocrlf true
out=$(run_init "$TARGET" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q "LF will be replaced by CRLF"; then
  t_ok "autocrlf=true install emits no CRLF conversion warnings"
else
  t_fail "autocrlf=true install emits no CRLF conversion warnings (rc=$rc)"
fi

# --- drift guard: the real template ships the .github/** LF pin ------------
if grep -qx '\.github/\*\* text eol=lf' "$REPO_ROOT/.gitattributes"; then
  t_ok "template .gitattributes pins .github/** to LF"
else
  t_fail "template .gitattributes pins .github/** to LF"
fi

# --- outside a git repo: refuse with a hint --------------------------------
NOREPO="$WORK/norepo"
mkdir -p "$NOREPO"
expect_rc_grep 1 "not a git repository" "running outside a git repo fails with guidance" run_init "$NOREPO"

# --- inside a repo but below the root: refuse, write nothing ----------------
# Guard regression (#162): the root check must not compare shell pwd to git
# toplevel — on Git Bash the spellings differ (/c/... vs C:/...) and the
# comparison false-positives at the real root. --show-prefix has no such
# split: empty at the root, non-empty below it.
new_target
mkdir -p "$TARGET/sub/dir"
expect_rc_grep 1 "run this at the repository root" "running from a subdirectory refuses with the root path" run_init "$TARGET/sub/dir"
if [ ! -e "$TARGET/AGENTS.md" ] && [ -z "$(git -C "$TARGET" diff --cached --name-only)" ]; then
  t_ok "subdirectory refusal writes and stages nothing"
else
  t_fail "subdirectory refusal writes and stages nothing"
fi

# --- dry-run with a new target dir performs no write at all -----------------
dry_new_dir() {
  (cd "$WORK" && SCAFFOLD_SOURCE_DIR="$FIXTURE" bash "$INIT" --dry-run ghost-dir)
}
expect_rc_grep 0 "a real run would create it" "--dry-run with a new target dir previews without creating" dry_new_dir
if [ ! -e "$WORK/ghost-dir" ]; then
  t_ok "--dry-run creates neither the directory nor .git"
else
  t_fail "--dry-run creates neither the directory nor .git"
fi

# --- symlinked .github: refuse, nothing escapes the repository --------------
new_target
EXT="$WORK/external$SANDBOX_N"
mkdir -p "$EXT"
ln -s "$EXT" "$TARGET/.github"
expect_rc_grep 1 "refusing to write through symbolic links" "symlinked .github refuses by default" run_init "$TARGET"
expect_rc_grep 1 "does not override this refusal" "--force does not override the symlink refusal" run_init "$TARGET" --force
if [ -z "$(find "$EXT" -mindepth 1 -print -quit)" ]; then
  t_ok "no file escaped through the .github symlink"
else
  t_fail "no file escaped through the .github symlink"
fi

# --- broken symlink at an install path counts as a symlink blocker ----------
new_target
ln -s /nonexistent-scaffold-target "$TARGET/AGENTS.md"
expect_rc_grep 1 "refusing to write through symbolic links" "broken symlink at an install path refuses" run_init "$TARGET"

# --- unknown flag is a usage error -----------------------------------------
new_target
expect_rc_grep 2 "unknown flag" "unknown flag exits 2 with usage" run_init "$TARGET" --bogus

# --- --help exits 0 and documents the env overrides ------------------------
new_target
expect_rc_grep 0 "SCAFFOLD_SOURCE_DIR" "--help documents the env overrides" run_init "$TARGET" --help

# --- version marker: fresh install inserts exactly one, above the paragraph -
MARKER_RE='^<!-- scaffold-version: repo=[A-Za-z0-9._-]+/[A-Za-z0-9._-]+ sha=([0-9a-f]{40}|unknown) date=([0-9]{4}-[0-9]{2}-[0-9]{2}|unknown) -->$'
new_target
run_init "$TARGET" >/dev/null 2>&1
if [ "$(grep -Ec "$MARKER_RE" "$TARGET/SCAFFOLD-CHANGELOG.md")" = "1" ]; then
  t_ok "fresh install writes exactly one schema-valid version marker"
else
  t_fail "fresh install writes exactly one schema-valid version marker"
fi
if grep -Eq '^<!-- scaffold-version: repo=mochan-tk/agentic-dev-kit-for-copilot sha=unknown date=[0-9]{4}-[0-9]{2}-[0-9]{2} -->$' "$TARGET/SCAFFOLD-CHANGELOG.md"; then
  t_ok "non-git source tree degrades to sha=unknown (never invented)"
else
  t_fail "non-git source tree degrades to sha=unknown (never invented)"
fi
if awk 'prev ~ /^<!-- scaffold-version: / && /^\*\*Scaffold version adopted/ { found = 1 } { prev = $0 } END { exit found ? 0 : 1 }' "$TARGET/SCAFFOLD-CHANGELOG.md"; then
  t_ok "marker sits directly above the version paragraph"
else
  t_fail "marker sits directly above the version paragraph"
fi

# --- version marker: git-backed re-install replaces with the 40-hex sha ----
GITFIX="$WORK/gitfixture"
cp -R "$FIXTURE" "$GITFIX"
git -C "$GITFIX" init -q
git -C "$GITFIX" -c user.email=t@t -c user.name=t add -A
git -C "$GITFIX" -c user.email=t@t -c user.name=t commit -qm fixture
GITFIX_SHA="$(git -C "$GITFIX" rev-parse HEAD)"
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$GITFIX" bash "$INIT" --force) >/dev/null 2>&1
if [ "$(grep -c '^<!-- scaffold-version: ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = "1" ]; then
  t_ok "re-install replaces the marker — still exactly one line"
else
  t_fail "re-install replaces the marker — still exactly one line"
fi
if grep -Fq "sha=$GITFIX_SHA" "$TARGET/SCAFFOLD-CHANGELOG.md"; then
  t_ok "git-backed source records its full 40-hex commit sha"
else
  t_fail "git-backed source records its full 40-hex commit sha"
fi

# --- adoption history survives a --force re-install (newest first) ---------
if [ "$(grep -c '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = "2" ]; then
  t_ok "--force re-install preserves the prior Adopted: line (2 total)"
else
  t_fail "--force re-install preserves the prior Adopted: line (2 total: $(grep -c '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md"))"
fi
if grep -m1 '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md" | grep -q "@"; then
  t_ok "Adopted: lines stack newest-first after re-install"
else
  t_fail "Adopted: lines stack newest-first after re-install"
fi

# --- dirty source tree: HEAD sha must not be claimed -----------------------
echo "uncommitted" >> "$GITFIX/AGENTS.md"
(cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$GITFIX" bash "$INIT" --force) >/dev/null 2>&1
if grep -Eq '^<!-- scaffold-version: repo=mochan-tk/agentic-dev-kit-for-copilot sha=unknown date=[0-9]{4}-[0-9]{2}-[0-9]{2} -->$' "$TARGET/SCAFFOLD-CHANGELOG.md"; then
  t_ok "dirty source tree degrades the marker to sha=unknown"
else
  t_fail "dirty source tree degrades the marker to sha=unknown"
fi
if grep -m1 '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md" | grep -q -- "-dirty (local tree)"; then
  t_ok "dirty source tree is named -dirty in the prose provenance"
else
  t_fail "dirty source tree is named -dirty in the prose provenance"
fi
if [ "$(grep -c '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = "3" ] && [ "$(grep -c '^<!-- scaffold-version: ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = "1" ]; then
  t_ok "third install: history at 3 lines, marker still exactly one"
else
  t_fail "third install: history at 3 lines, marker still exactly one"
fi

# --- version marker: the template's own placeholder is schema-valid --------
if [ "$(grep -Ec "$MARKER_RE" "$REPO_ROOT/SCAFFOLD-CHANGELOG.md")" = "1" ]; then
  t_ok "template repo carries exactly one schema-valid placeholder marker"
else
  t_fail "template repo carries exactly one schema-valid placeholder marker"
fi

# --- fetch path: present-but-unauthenticated gh behaves like gh-absent ----
# gh/git/curl are PATH shims: gh logs argv and reports "not logged in",
# git intercepts ls-remote (fake pinned SHA) and passes everything else
# through, curl serves a tarball built from the fixture. No network.
SHIM="$WORK/shims"
mkdir -p "$SHIM"
GH_LOG="$WORK/gh-shim.log"
: > "$GH_LOG"
FAKE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
REAL_GIT="$(command -v git)"
cat > "$SHIM/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$GH_LOG"
if [ "\$1" = "auth" ]; then exit 1; fi
exit 1
EOF
cat > "$SHIM/git" <<EOF
#!/bin/sh
if [ "\$1" = "ls-remote" ]; then
  printf '%s\trefs/heads/main\n' "$FAKE_SHA"
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
mkdir -p "$WORK/tarsrc/acme-scaffold-$FAKE_SHA"
cp -R "$FIXTURE/." "$WORK/tarsrc/acme-scaffold-$FAKE_SHA/"
tar -czf "$WORK/served.tar.gz" -C "$WORK/tarsrc" "acme-scaffold-$FAKE_SHA"
cat > "$SHIM/curl" <<EOF
#!/bin/sh
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then out="\$2"; shift; fi
  shift
done
[ -n "\$out" ] && cp "$WORK/served.tar.gz" "\$out"
EOF
chmod +x "$SHIM/gh" "$SHIM/git" "$SHIM/curl"

run_init_fetch() {
  local dir="$1"
  shift
  (cd "$dir" && PATH="$SHIM:$PATH" SCAFFOLD_REPO=acme/scaffold bash "$INIT" "$@")
}

new_target
expect_rc_grep 0 "Scaffold installed from acme/scaffold@" \
  "unauthenticated gh: install succeeds via ls-remote + curl fallback" \
  run_init_fetch "$TARGET"
if grep -q "^auth status" "$GH_LOG" && ! grep -q "^api " "$GH_LOG"; then
  t_ok "unauthenticated gh: probed once, no gh api call ever issued"
else
  t_fail "unauthenticated gh: probed once, no gh api call ever issued (log: $(tr '\n' ';' < "$GH_LOG"))"
fi

# --- source-dir path: never reaches the gh probe --------------------------
: > "$GH_LOG"
new_target
OUT145="$WORK/handoff-out.txt"
(cd "$TARGET" && PATH="$SHIM:$PATH" SCAFFOLD_SOURCE_DIR="$FIXTURE" bash "$INIT") > "$OUT145" 2>&1
if [ ! -s "$GH_LOG" ]; then
  t_ok "SCAFFOLD_SOURCE_DIR install never invokes gh"
else
  t_fail "SCAFFOLD_SOURCE_DIR install never invokes gh (log: $(tr '\n' ';' < "$GH_LOG"))"
fi

# --- handoff banner: agent-relay instruction survives to stdout ------------
# Agent-mediated installs (#144) drop the handoff unless the banner tells
# the installing agent to relay it — assert that instruction is printed.
if grep -q "AI agent running this install" "$OUT145" \
   && grep -q "offer to run /onboard-project" "$OUT145"; then
  t_ok "handoff banner carries the agent-relay instruction"
else
  t_fail "handoff banner carries the agent-relay instruction"
fi

# --- handoff banner: two steps, labels+ruleset folded into onboarding ------
# The manual "Bootstrap labels" (#175) and "Branch ruleset" (#187) steps
# moved inside /onboard-project; the banner must show commit -> onboard,
# mention the consent-gated protection offer, and say "two next steps".
if ! grep -q "Bootstrap labels:" "$OUT145" \
   && ! grep -q "Branch ruleset:" "$OUT145" \
   && grep -q "bootstraps the canonical labels" "$OUT145" \
   && grep -q "offers to enable branch" "$OUT145" \
   && ! grep -q "3\. " "$OUT145" \
   && grep -q "relay the two" "$OUT145"; then
  t_ok "handoff banner is two steps with labels and ruleset inside onboarding"
else
  t_fail "handoff banner is two steps with labels and ruleset inside onboarding"
fi

# --- upgrade (#190): class-split refresh of an adopted instance -------------
# FIXTURE2 is a mutated copy playing "newer template": one engine file
# changed, one engine file and one tuned-class file added. The shared
# FIXTURE stays pristine for the cases above.
FIXTURE2="$WORK/template2"
cp -R "$FIXTURE" "$FIXTURE2"
echo "echo guard v2" > "$FIXTURE2/.github/scripts/some-guard.sh"
mkdir -p "$FIXTURE2/.github/prompts" "$FIXTURE2/.github/instructions"
echo "# new prompt" > "$FIXTURE2/.github/prompts/new.prompt.md"
echo "# new rules" > "$FIXTURE2/.github/instructions/new.instructions.md"

run_upgrade() {
  local dir="$1"
  shift
  (cd "$dir" && SCAFFOLD_SOURCE_DIR="$FIXTURE2" bash "$INIT" "$@")
}

# tune_target — fresh install from FIXTURE committed away, then one file
# of every kept class customized, simulating an onboarded instance with a
# clean index (so post-upgrade staging assertions see only upgrade output).
tune_target() {
  new_target
  run_init "$TARGET" >/dev/null 2>&1
  git -C "$TARGET" -c user.email=t@example.com -c user.name=t commit -qm "adopt scaffold"
  echo "TUNED INSTRUCTIONS" > "$TARGET/.github/copilot-instructions.md"
  echo "TUNED CI" > "$TARGET/.github/workflows/ci.yml"
  echo "AMENDED AGENTS" > "$TARGET/AGENTS.md"
  echo "PROJECT DOC" > "$TARGET/.github/docs/thing.md"
}

# --- upgrade + --force is a usage error -------------------------------------
new_target
expect_rc_grep 2 "mutually exclusive" "--upgrade --force is a usage error (rc 2)" run_init "$TARGET" --upgrade --force

# --- upgrade refreshes engine, keeps tuned + docs, installs absent ----------
tune_target
OUT_UPG="$WORK/upgrade-out.txt"
run_upgrade "$TARGET" --upgrade > "$OUT_UPG" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -q "Scaffold upgraded from" "$OUT_UPG"; then
  t_ok "--upgrade succeeds with the upgrade banner"
else
  t_fail "--upgrade succeeds with the upgrade banner (rc=$rc)"
  sed 's/^/    # /' "$OUT_UPG"
fi
if [ "$(cat "$TARGET/.github/scripts/some-guard.sh")" = "echo guard v2" ]; then
  t_ok "engine collision is refreshed to the template copy"
else
  t_fail "engine collision is refreshed to the template copy"
fi
if [ "$(cat "$TARGET/.github/copilot-instructions.md")" = "TUNED INSTRUCTIONS" ] \
   && [ "$(cat "$TARGET/.github/workflows/ci.yml")" = "TUNED CI" ] \
   && [ "$(cat "$TARGET/AGENTS.md")" = "AMENDED AGENTS" ]; then
  t_ok "tuned surfaces survive the upgrade byte-identical"
else
  t_fail "tuned surfaces survive the upgrade byte-identical"
fi
if [ "$(cat "$TARGET/.github/docs/thing.md")" = "PROJECT DOC" ]; then
  t_ok "instance docs survive the upgrade byte-identical"
else
  t_fail "instance docs survive the upgrade byte-identical"
fi
if [ "$(cat "$TARGET/.github/prompts/new.prompt.md" 2>/dev/null)" = "# new prompt" ] \
   && [ "$(cat "$TARGET/.github/instructions/new.instructions.md" 2>/dev/null)" = "# new rules" ]; then
  t_ok "absent files are installed in engine and tuned classes alike"
else
  t_fail "absent files are installed in engine and tuned classes alike"
fi
if grep -q "refreshed   .github/scripts/some-guard.sh" "$OUT_UPG" \
   && grep -q "kept        AGENTS.md (tuned surface" "$OUT_UPG" \
   && grep -q "kept        .github/docs/thing.md (instance docs" "$OUT_UPG"; then
  t_ok "upgrade banner reports refreshed and kept files by class"
else
  t_fail "upgrade banner reports refreshed and kept files by class"
fi
if ! grep -q "offer to run /onboard-project" "$OUT_UPG" \
   && grep -q "AI agent running this upgrade" "$OUT_UPG" \
   && grep -q "git diff --cached" "$OUT_UPG"; then
  t_ok "upgrade banner replaces onboarding handoff with diff-review handoff"
else
  t_fail "upgrade banner replaces onboarding handoff with diff-review handoff"
fi
if [ "$(grep -c '^\*\*Adopted:\*\* ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = 2 ] \
   && [ "$(grep -c '^<!-- scaffold-version: ' "$TARGET/SCAFFOLD-CHANGELOG.md")" = 1 ]; then
  t_ok "upgrade stacks a second Adopted: line and keeps a single marker"
else
  t_fail "upgrade stacks a second Adopted: line and keeps a single marker"
fi

# --- upgrade --dry-run: class labels, bit-inert ------------------------------
tune_target
OUT_UDRY="$WORK/upgrade-dry-out.txt"
run_upgrade "$TARGET" --upgrade --dry-run > "$OUT_UDRY" 2>&1
if grep -q "upgrade    .github/scripts/some-guard.sh (scaffold-owned" "$OUT_UDRY" \
   && grep -q "keep       AGENTS.md (tuned surface" "$OUT_UDRY" \
   && grep -q "keep       .github/docs/thing.md (instance docs" "$OUT_UDRY" \
   && grep -q "install    .github/prompts/new.prompt.md" "$OUT_UDRY"; then
  t_ok "--upgrade --dry-run labels the plan by ownership class"
else
  t_fail "--upgrade --dry-run labels the plan by ownership class"
  sed 's/^/    # /' "$OUT_UDRY"
fi
if [ "$(cat "$TARGET/.github/scripts/some-guard.sh")" = "echo guard" ] \
   && ! git -C "$TARGET" diff --cached --name-only | grep -q .; then
  t_ok "--upgrade --dry-run writes and stages nothing"
else
  t_fail "--upgrade --dry-run writes and stages nothing"
fi

# --- plain collision refusal now points at --upgrade -------------------------
new_target
echo "app-owned agents file" > "$TARGET/AGENTS.md"
expect_rc_grep 1 "re-run with --upgrade" "collision refusal recommends --upgrade first" run_init "$TARGET"

# --- upgrade on a virgin directory falls back to the install banner ---------
new_target
expect_rc_grep 0 "Scaffold installed from" "--upgrade on a fresh target behaves as a clean install" run_upgrade "$TARGET" --upgrade

# --- --help documents --upgrade ----------------------------------------------
expect_rc_grep 0 "refresh an adopted scaffold" "--help documents the --upgrade flag" bash "$INIT" --help

t_summary
