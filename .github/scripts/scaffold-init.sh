#!/usr/bin/env bash
# scaffold-init.sh — install the agentic-dev scaffold into a repository.
#
# One-liner (run at the root of a new or existing git repository):
#   curl -fsSL https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.sh | bash
# Windows (PowerShell): use the companion bootstrap scaffold-init.ps1 in this
# directory — it runs this script through Git Bash; logic lives here only.
#
# What it installs — and nothing else; the application owns every other path:
#   always            .github/**  AGENTS.md  SCAFFOLD-CHANGELOG.md
#   seed-if-absent    README.md  .gitignore  .gitattributes
#   never             LICENSE, .vscode/ (license choice and editor setup
#                     belong to the adopting repository)
#
# Safety:
#   - collisions refuse by default: the run lists them and exits 1 with the
#     target untouched; --force overwrites exactly the listed collisions
#     (and reports each one); --dry-run prints the file plan and performs
#     no write at all — it does not even create the target directory.
#   - --upgrade refreshes an adopted instance: colliding scaffold-owned
#     files (scripts, skills, agents, prompts, issue/PR templates,
#     SCAFFOLD-CHANGELOG.md) are overwritten in place, while tuned
#     surfaces (copilot-instructions.md, workflows/, CODEOWNERS,
#     instructions/, AGENTS.md) and instance knowledge (.github/docs/**)
#     are kept and reported; files the instance lacks are installed in
#     every class. Run it on a branch and land the result as one PR —
#     git review is the safety net for the refreshed files.
#   - symlinks are never written through: if an install path, or any
#     directory on the way to it, is a symbolic link, the run refuses —
#     --force does not override this. Writing through links could land
#     files outside the repository.
#   - network fetches are pinned: SCAFFOLD_REF is resolved to a commit SHA
#     first (gh when present, else git ls-remote), the tarball is fetched
#     at that SHA, and that SHA is what the provenance line in the
#     target's SCAFFOLD-CHANGELOG.md records. A machine-readable
#     scaffold-version marker is maintained alongside it (read contract
#     documented at the write site below).
#   - installed files are staged with `git add`, never committed.
#
# Environment:
#   SCAFFOLD_REPO        source template repository (default: mochan-tk/agentic-dev-kit-for-copilot)
#   SCAFFOLD_REF         branch / tag / SHA to fetch (default: main)
#   SCAFFOLD_SOURCE_DIR  local template tree to copy from — no network at all
#
# Usage: scaffold-init.sh [--force|--upgrade] [--dry-run] [--help] [target-dir]
#   target-dir  create the directory (git init if needed) and install there;
#               without it, install into the current directory's repo root.
# Exit codes: 0 ok · 1 collision/symlink/target error · 2 usage · 3 fetch error.

set -euo pipefail

REPO="${SCAFFOLD_REPO:-mochan-tk/agentic-dev-kit-for-copilot}"
REF="${SCAFFOLD_REF:-main}"
SRC_OVERRIDE="${SCAFFOLD_SOURCE_DIR:-}"

usage() {
  cat <<'EOF'
Usage: scaffold-init.sh [--force|--upgrade] [--dry-run] [--help] [target-dir]

Install the agentic-dev scaffold into a git repository (current directory
by default; pass target-dir to create/init one). Installs .github/**,
AGENTS.md and SCAFFOLD-CHANGELOG.md always; seeds README.md, .gitignore
and .gitattributes only when the target has none; never installs LICENSE
or .vscode/.

Flags:
  --force     overwrite colliding files (default: refuse and exit 1);
              never overrides the symlink refusal
  --upgrade   refresh an adopted scaffold: overwrite colliding
              scaffold-owned files (scripts, skills, agents, prompts,
              issue/PR templates, SCAFFOLD-CHANGELOG.md); keep tuned
              surfaces (copilot-instructions.md, workflows/, CODEOWNERS,
              instructions/, AGENTS.md) and .github/docs/** — every kept
              file is listed; absent files are installed in every class.
              Mutually exclusive with --force. Run on a branch and land
              the result as one PR.
  --dry-run   print the file plan only; performs no write at all
  --help      this text

Environment:
  SCAFFOLD_REPO        source repo, owner/name   (default mochan-tk/agentic-dev-kit-for-copilot)
  SCAFFOLD_REF         branch / tag / SHA        (default main)
  SCAFFOLD_SOURCE_DIR  local template tree — skips all network fetch

The network fetch is pinned: SCAFFOLD_REF is resolved to a commit SHA
before download, and that SHA is recorded in the provenance line.

Examples:
  curl -fsSL https://raw.githubusercontent.com/mochan-tk/agentic-dev-kit-for-copilot/main/.github/scripts/scaffold-init.sh | bash
  SCAFFOLD_REPO=acme/dev-scaffold SCAFFOLD_REF=v1.0.0 bash scaffold-init.sh
  bash /path/to/template/.github/scripts/scaffold-init.sh my-new-repo
EOF
}

FORCE=0
UPGRADE=0
DRY=0
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --upgrade) UPGRADE=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown flag '$1'" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "error: at most one target-dir argument" >&2; exit 2
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

if [ "$FORCE" -eq 1 ] && [ "$UPGRADE" -eq 1 ]; then
  echo "error: --force and --upgrade are mutually exclusive" >&2
  usage >&2
  exit 2
fi

# status <text> — one plain progress line per slow phase, so an install
# over a slow network or filesystem (e.g. Git Bash under corporate AV,
# where the copy alone took minutes in silence) shows what it is doing.
# Plain lines only — no carriage returns or terminal control — so piped
# and logged output stays clean. Dry runs print the file plan and nothing
# else: their output is unchanged.
status() { [ "$DRY" -eq 1 ] || echo "$@"; }

# --- target resolution ---------------------------------------------------
# DEST is where existence checks look. A dry run never writes — not even
# mkdir or git init — so it previews against the path as-is; a real run
# creates/inits the target when asked, then works from the repo root.
DEST="${TARGET:-.}"
CREATE_NOTE=""
if [ "$DRY" -eq 1 ]; then
  if [ -n "$TARGET" ] && [ ! -d "$TARGET" ]; then
    CREATE_NOTE="target '$TARGET' does not exist — a real run would create it and 'git init'."
  fi
else
  if [ -n "$TARGET" ]; then
    mkdir -p "$TARGET"
    cd "$TARGET"
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      git -c init.defaultBranch=main init -q .
      echo "initialized empty git repository in $(pwd)"
    fi
  else
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      echo "error: current directory is not a git repository." >&2
      echo "hint: run 'git init' first, or pass a target-dir argument." >&2
      exit 1
    fi
  fi
  # --show-prefix is empty exactly at the repo root. Comparing pwd to
  # --show-toplevel breaks on Git Bash (MSYS pwd says /c/..., git says
  # C:/...); the prefix is computed inside git, so no spelling meets here.
  if [ -n "$(git rev-parse --show-prefix)" ]; then
    echo "error: run this at the repository root: $(git rev-parse --show-toplevel)" >&2
    exit 1
  fi
  DEST="."
fi

# --- source acquisition ---------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-init.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Consent-gated adopter feedback (ADR-0002): on an unguarded failure in an
# interactive run, offer - default no, full preview, allowlist-only - to
# file the failure upstream. Armed after the cleanup trap above so the lib
# chains it. Lib absent (e.g. curl | bash, which has no BASH_SOURCE and is
# non-interactive anyway) or any gate closed: byte-identical behavior.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" ]; then
  # shellcheck source=/dev/null
  if . "$(dirname "${BASH_SOURCE[0]}")/feedback-lib.sh" 2>/dev/null; then
    feedback_arm scaffold-init || true
  fi
fi

SRC=""
SRC_DESC=""
PROV_SRC=""
PROV_SHA=""
if [ -n "$SRC_OVERRIDE" ]; then
  SRC="$SRC_OVERRIDE"
  status "using local source tree $SRC (no network fetch)"
  if git -C "$SRC" rev-parse --short HEAD >/dev/null 2>&1; then
    SHORT="$(git -C "$SRC" rev-parse --short HEAD)"
    if [ -n "$(git -C "$SRC" status --porcelain 2>/dev/null)" ]; then
      # Uncommitted changes: HEAD does not describe the installed content,
      # so the machine-readable marker must not claim it (sha=unknown).
      SRC_DESC="$REPO@$SHORT-dirty (local tree)"
    else
      SRC_DESC="$REPO@$SHORT (local tree)"
      PROV_SHA="$(git -C "$SRC" rev-parse HEAD)"
    fi
  else
    SRC_DESC="local tree $SRC"
  fi
  PROV_SRC="$SRC_DESC"
else
  # Pin the requested ref to a commit SHA so the fetched content and the
  # recorded provenance are immutable, even when REF is a moving branch.
  # gh is used only when authenticated — gh-present-but-logged-out would
  # fail every API call, while the git/curl path below works for public
  # source repositories; treat that state exactly like gh-absent.
  status "resolving $REPO@$REF to a commit ..."
  GH_AUTHED=0
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    GH_AUTHED=1
  fi
  PIN=""
  if [ "$GH_AUTHED" = 1 ]; then
    PIN="$(gh api "repos/$REPO/commits/$REF" --jq .sha 2>/dev/null || true)"
  fi
  if [ -z "$PIN" ]; then
    PIN="$(git ls-remote "https://github.com/$REPO" "refs/heads/$REF" 2>/dev/null | head -n1 | cut -f1 || true)"
  fi
  if [ -z "$PIN" ]; then
    # Annotated tags: refs/tags/<tag> names the tag object, not the commit —
    # ask for the peeled form first; lightweight tags fall through to the
    # plain lookup, which already is the commit.
    PIN="$(git ls-remote "https://github.com/$REPO" "refs/tags/$REF^{}" 2>/dev/null | head -n1 | cut -f1 || true)"
  fi
  if [ -z "$PIN" ]; then
    PIN="$(git ls-remote "https://github.com/$REPO" "refs/tags/$REF" 2>/dev/null | head -n1 | cut -f1 || true)"
  fi
  if [ -z "$PIN" ]; then
    if printf '%s' "$REF" | grep -Eq '^[0-9a-f]{7,40}$'; then
      PIN="$REF"   # REF already looks like a commit SHA — fetch it directly.
    else
      echo "error: could not resolve '$REF' to a commit in $REPO (tried gh api and git ls-remote)." >&2
      echo "  hint: private source repositories need an authenticated gh — run: gh auth login" >&2
      exit 3
    fi
  fi
  TARBALL="$WORK/scaffold.tar.gz"
  status "downloading and unpacking $REPO@$(printf '%.12s' "$PIN") ..."
  if [ "$GH_AUTHED" = 1 ]; then
    if ! gh api "repos/$REPO/tarball/$PIN" > "$TARBALL" 2>"$WORK/fetch.err"; then
      echo "error: fetching $REPO@$PIN via gh failed:" >&2
      cat "$WORK/fetch.err" >&2
      exit 3
    fi
  else
    if ! curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$PIN" -o "$TARBALL"; then
      echo "error: fetching https://codeload.github.com/$REPO/tar.gz/$PIN failed." >&2
      echo "  hint: private source repositories need an authenticated gh — run: gh auth login" >&2
      exit 3
    fi
  fi
  mkdir "$WORK/src"
  tar -xzf "$TARBALL" -C "$WORK/src"
  SRC="$(find "$WORK/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$SRC" ]; then
    echo "error: unexpected tarball layout from $REPO@$PIN" >&2
    exit 3
  fi
  SRC_DESC="$REPO@$(printf '%.12s' "$PIN")"
  PROV_SRC="$REPO@$PIN (requested ref: $REF)"
  PROV_SHA="$PIN"
fi
if [ ! -d "$SRC/.github" ]; then
  echo "error: source does not look like the scaffold (no .github/): $SRC" >&2
  exit 3
fi

# --- file plan --------------------------------------------------------------
# present <relpath> — something occupies the path (a broken symlink counts:
# writing to it would follow the link).
present() { [ -e "$DEST/$1" ] || [ -L "$DEST/$1" ]; }

# sym_block_at <relpath> — print the first component (the path itself or an
# ancestor directory below the target root) that is a symbolic link.
# Writing through it could land outside the repository, so such paths
# always refuse — even with --force.
sym_block_at() {
  local p="$1"
  while :; do
    if [ -L "$DEST/$p" ]; then printf '%s\n' "$p"; return 0; fi
    case "$p" in */*) p="${p%/*}" ;; *) break ;; esac
  done
  return 1
}

# upgrade_class <relpath> — sets UCLASS to the ownership class consulted
# when --upgrade meets a pre-existing file. No subshell, no process spawn:
# this runs once per template file and per-file forks are ruinously slow
# on MSYS (Git Bash). Classes:
#   engine — scaffold-owned machinery; an upgrade refreshes it in place.
#   tuned  — surfaces onboarding customizes (the tuning-status.sh targets
#            plus AGENTS.md, amendable by retro PRs); kept.
#   docs   — .github/docs/** agreements/context: instance truth; kept.
# Absent files install regardless of class — the class only decides
# collisions.
upgrade_class() {
  case "$1" in
    .github/docs/*) UCLASS=docs ;;
    .github/copilot-instructions.md|.github/workflows/*|.github/CODEOWNERS|.github/instructions/*|AGENTS.md) UCLASS=tuned ;;
    *) UCLASS=engine ;;
  esac
}

ALWAYS=()
status "computing the file plan ..."
while IFS= read -r -d '' f; do
  ALWAYS+=("${f#"$SRC"/}")
done < <(find "$SRC/.github" -type f -print0 | sort -z)
for f in AGENTS.md SCAFFOLD-CHANGELOG.md; do
  [ -f "$SRC/$f" ] && ALWAYS+=("$f")
done

SEED=()
SEED_SKIPPED=()
for f in README.md .gitignore .gitattributes; do
  [ -f "$SRC/$f" ] || continue
  if present "$f"; then
    SEED_SKIPPED+=("$f")
  else
    SEED+=("$f")
  fi
done

CONFLICTS=()
UPGRADES=()
KEPT_TUNED=()
KEPT_DOCS=()
SYMLINKS=()
for f in ${ALWAYS[@]+"${ALWAYS[@]}"}; do
  if b="$(sym_block_at "$f")"; then
    SYMLINKS+=("$b")
  elif present "$f"; then
    if [ "$UPGRADE" -eq 1 ]; then
      upgrade_class "$f"
      case "$UCLASS" in
        engine) UPGRADES+=("$f") ;;
        tuned)  KEPT_TUNED+=("$f") ;;
        docs)   KEPT_DOCS+=("$f") ;;
      esac
    else
      CONFLICTS+=("$f")
    fi
  fi
done

if [ "$DRY" -eq 1 ]; then
  dp="$DEST"
  [ "$dp" = "." ] && dp="$(pwd)"
  echo "dry run — file plan for $dp from $SRC_DESC:"
  [ -n "$CREATE_NOTE" ] && echo "  note: $CREATE_NOTE"
  for f in ${ALWAYS[@]+"${ALWAYS[@]}"}; do
    if b="$(sym_block_at "$f")"; then
      echo "  SYMLINK    $f (blocked by link at $b — refused even with --force)"
    elif present "$f"; then
      if [ "$UPGRADE" -eq 1 ]; then
        upgrade_class "$f"
        case "$UCLASS" in
          engine) echo "  upgrade    $f (scaffold-owned — refreshed)" ;;
          tuned)  echo "  keep       $f (tuned surface — not touched)" ;;
          docs)   echo "  keep       $f (instance docs — not touched)" ;;
        esac
      elif [ "$FORCE" -eq 1 ]; then echo "  overwrite  $f"; else echo "  CONFLICT   $f"; fi
    else
      echo "  install    $f"
    fi
  done
  for f in ${SEED[@]+"${SEED[@]}"}; do echo "  seed       $f"; done
  for f in ${SEED_SKIPPED[@]+"${SEED_SKIPPED[@]}"}; do echo "  keep       $f (exists — template copy not installed)"; done
  if [ "${#SYMLINKS[@]}" -gt 0 ]; then
    echo "note: a real run refuses the SYMLINK paths above regardless of flags."
  fi
  if [ "${#CONFLICTS[@]}" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
    echo "note: a real run would refuse these conflicts (use --force to overwrite)."
  fi
  echo "nothing was changed."
  exit 0
fi

if [ "${#SYMLINKS[@]}" -gt 0 ]; then
  echo "error: refusing to write through symbolic links:" >&2
  printf '%s\n' "${SYMLINKS[@]}" | sort -u | sed 's/^/  /' >&2
  echo "Writing through links could place files outside this repository." >&2
  echo "Replace each link with a real file or directory and re-run." >&2
  echo "--force does not override this refusal. Nothing was installed." >&2
  exit 1
fi

if [ "${#CONFLICTS[@]}" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  echo "error: refusing to overwrite existing files:" >&2
  for f in "${CONFLICTS[@]}"; do echo "  $f" >&2; done
  echo "nothing was installed. If this repo already adopted the scaffold," >&2
  echo "re-run with --upgrade: scaffold-owned files are refreshed while" >&2
  echo "tuned surfaces and .github/docs/** are kept. --force instead" >&2
  echo "overwrites every listed collision. Inspect either plan first by" >&2
  echo "adding --dry-run." >&2
  exit 1
fi

# --- install ----------------------------------------------------------------
# Preserve instance adoption history across the changelog overwrite: the
# template copy replaces SCAFFOLD-CHANGELOG.md wholesale (on --force and
# on --upgrade, where the changelog is engine-class), but the prose
# **Adopted:** lines belong to the instance — a re-install must not erase
# its lineage.
OLD_ADOPTED=()
if [ -f SCAFFOLD-CHANGELOG.md ]; then
  while IFS= read -r _line; do
    OLD_ADOPTED+=("$_line")
  done < <(grep '^\*\*Adopted:\*\* ' SCAFFOLD-CHANGELOG.md 2>/dev/null || true)
fi

# On --upgrade, kept collisions (tuned surfaces, instance docs) drop out
# of the copy set; engine collisions and absent files stay in. The class
# check reuses upgrade_class — still zero process spawns per file.
INSTALLED=()
for f in ${ALWAYS[@]+"${ALWAYS[@]}"} ${SEED[@]+"${SEED[@]}"}; do
  if [ "$UPGRADE" -eq 1 ] && present "$f"; then
    upgrade_class "$f"
    if [ "$UCLASS" != engine ]; then continue; fi
  fi
  INSTALLED+=("$f")
done

# Copy the whole set in two processes: one mkdir -p for every target
# directory, one tar pipe for the files. The previous per-file
# dirname/mkdir/cp loop spawned ~3 processes per file — minutes of
# silence on MSYS (Git Bash), where process creation is slow and
# corporate AV scans every spawn (#165). tar -p preserves the modes and
# mtimes that cp -p preserved; extraction overwrites existing paths just
# as cp did (conflicts were already resolved or --force-approved above).
if [ "${#INSTALLED[@]}" -gt 0 ]; then
  status "installing ${#INSTALLED[@]} file(s) ..."
  DIRS=()
  for f in "${INSTALLED[@]}"; do
    case "$f" in */*) DIRS+=("${f%/*}") ;; esac
  done
  if [ "${#DIRS[@]}" -gt 0 ]; then
    mkdir -p "${DIRS[@]}"
  fi
  # LC_ALL=C: keep tar's behavior and stderr locale-independent (bsdtar
  # warns "Failed to set default locale" in locale-less environments);
  # every scaffold path is ASCII, so the C locale loses nothing.
  LC_ALL=C tar -C "$SRC" -cf - "${INSTALLED[@]}" | LC_ALL=C tar -xpf -
fi

# insert_adopted_line <line> — place one **Adopted:** line directly under
# the version paragraph (falls back to EOF if the paragraph is missing);
# exact duplicates are skipped. Repeated calls stack newest-first.
insert_adopted_line() {
  [ -f SCAFFOLD-CHANGELOG.md ] || return 0
  grep -Fqx "$1" SCAFFOLD-CHANGELOG.md && return 0
  awk -v line="$1" '
    { print }
    /^\*\*Scaffold version adopted/ { seen = 1 }
    seen == 1 && /^$/ && done == 0 { print line; print ""; done = 1; seen = 2 }
    END { if (done == 0) printf "\n%s\n", line }
  ' SCAFFOLD-CHANGELOG.md > "$WORK/changelog.new"
  mv "$WORK/changelog.new" SCAFFOLD-CHANGELOG.md
}

# Adoption provenance: restore the preserved history (oldest first, so the
# block ends up newest-first), then record this install on top.
if [ "${#OLD_ADOPTED[@]}" -gt 0 ]; then
  for (( i = ${#OLD_ADOPTED[@]} - 1; i >= 0; i-- )); do
    insert_adopted_line "${OLD_ADOPTED[$i]}"
  done
fi
insert_adopted_line "**Adopted:** from $PROV_SRC on $(date -u +%Y-%m-%d)."

# Machine-readable version marker — the read contract for tooling (e.g. the
# feedback helper, ADR-0002). Exactly one line in SCAFFOLD-CHANGELOG.md,
# directly above the "**Scaffold version adopted" paragraph, fixed field
# order:
#   <!-- scaffold-version: repo=<owner>/<name> sha=<40-hex|unknown> date=<YYYY-MM-DD|unknown> -->
# Replace-or-insert keeps a single current version (prose Adopted: lines
# keep accumulating as history). Fields failing validation are written as
# "unknown", never invented.
if [ -f SCAFFOLD-CHANGELOG.md ]; then
  MARK_REPO="unknown"
  if printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
    MARK_REPO="$REPO"
  fi
  MARK_SHA="unknown"
  if printf '%s' "$PROV_SHA" | grep -Eq '^[0-9a-f]{40}$'; then
    MARK_SHA="$PROV_SHA"
  fi
  MARK_DATE="$(date -u +%Y-%m-%d)"
  printf '%s' "$MARK_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || MARK_DATE="unknown"
  MARKER="<!-- scaffold-version: repo=$MARK_REPO sha=$MARK_SHA date=$MARK_DATE -->"
  awk -v marker="$MARKER" '
    /^<!-- scaffold-version: / { next }
    /^\*\*Scaffold version adopted/ && placed == 0 { print marker; placed = 1 }
    { print }
    END { if (placed == 0) printf "\n%s\n", marker }
  ' SCAFFOLD-CHANGELOG.md > "$WORK/changelog.marker"
  mv "$WORK/changelog.marker" SCAFFOLD-CHANGELOG.md
fi

status "staging installed files with git add ..."
git add -- ${INSTALLED[@]+"${INSTALLED[@]}"}

# --- handoff ----------------------------------------------------------------
# Two shapes: an upgrade that met pre-existing files gets upgrade guidance
# (diff review, changelog port, one PR); everything else — fresh installs,
# and --upgrade pointed at a virgin directory — gets adoption guidance.
UPGRADED_COUNT=$(( ${#UPGRADES[@]} + ${#KEPT_TUNED[@]} + ${#KEPT_DOCS[@]} ))
if [ "$UPGRADE" -eq 1 ] && [ "$UPGRADED_COUNT" -gt 0 ]; then
  echo
  echo "=================================================================="
  echo " Scaffold upgraded from $SRC_DESC"
  echo " ${#INSTALLED[@]} file(s) staged — review with 'git status'; nothing committed."
  for f in ${UPGRADES[@]+"${UPGRADES[@]}"}; do
    echo " refreshed   $f (scaffold-owned)"
  done
  for f in ${KEPT_TUNED[@]+"${KEPT_TUNED[@]}"}; do
    echo " kept        $f (tuned surface — not touched)"
  done
  for f in ${KEPT_DOCS[@]+"${KEPT_DOCS[@]}"}; do
    echo " kept        $f (instance docs — not touched)"
  done
  for f in ${SEED_SKIPPED[@]+"${SEED_SKIPPED[@]}"}; do
    echo " kept your existing $f (template copy not installed)"
  done
  echo
  echo " Next steps:"
  echo "   1. Review the staged diff:   git diff --cached"
  echo "   2. Read SCAFFOLD-CHANGELOG.md for changes since your adopted"
  echo "      version; port anything the kept files above need by hand."
  echo "   3. Re-verify the instance:   bash .github/scripts/tuning-status.sh"
  echo "                                bash .github/scripts/tests/run-tests.sh"
  echo "   4. Land it as one PR:        e.g. 'scaffold: upgrade to $REF'"
  if [ -n "${MSYSTEM:-}" ]; then
    echo
    echo " Windows note: run the 'bash ...' steps above inside Git Bash —"
    echo " plain 'bash' in PowerShell may launch WSL, which lacks your gh login."
  fi
  echo
  echo " AI agent running this upgrade on a human's behalf: relay the diff"
  echo " review and PR steps to the human — do not summarize this handoff away."
  echo "=================================================================="
else
  echo
  echo "=================================================================="
  echo " Scaffold installed from $SRC_DESC"
  echo " ${#INSTALLED[@]} file(s) staged — review with 'git status'; nothing committed."
  for f in ${CONFLICTS[@]+"${CONFLICTS[@]}"}; do
    echo " overwrote   $f (pre-existing — --force)"
  done
  for f in ${SEED_SKIPPED[@]+"${SEED_SKIPPED[@]}"}; do
    echo " kept your existing $f (template copy not installed)"
  done
  [ -e LICENSE ] || echo " no LICENSE installed — the license choice is yours to make."
  echo
  # Name the default branch in the push command so it works from the app
  # session path: a worktree on its own generated branch, with no upstream.
  # Resolved locally only — `origin/HEAD` exists in clones but not after a
  # plain `git init` + `git remote add`, so fall back to a placeholder the
  # adopter substitutes rather than guessing a name.
  DEFAULT_BRANCH="$( { git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true; } | sed 's#^[^/]*/##' )"
  [ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="<default-branch>"
  echo " Next steps:"
  echo "   1. Land it on the default branch:"
  echo "        git commit -m 'Adopt agentic-dev scaffold'"
  echo "        git push origin HEAD:$DEFAULT_BRANCH"
  echo "      Actions only run from the default branch, so the scaffold has"
  echo "      to reach it before onboarding — a push to any other branch"
  echo "      does not count. If that branch is protected, push your own"
  echo "      branch and open a PR instead. Skip all of this and"
  echo "      onboarding offers to do it for you."
  echo "   2. Onboard interactively:    open a GitHub Copilot app session and"
  echo "      run the 'project-onboarding' skill. It"
  echo "      interviews you, bootstraps the canonical labels, then"
  echo "      offers to enable branch protection, verifies commands by"
  echo "      running them, and opens the evidence PR."
  # Git for Windows / MSYS2 shells always export MSYSTEM; WSL, macOS and
  # Linux never do. Warn there: typing plain 'bash' into PowerShell may
  # resolve to the WSL launcher (different filesystem, no gh login) — the
  # very trap scaffold-init.ps1 goes out of its way to avoid.
  if [ -n "${MSYSTEM:-}" ]; then
    echo
    echo " Windows note: run the 'bash ...' steps above inside Git Bash —"
    echo " plain 'bash' in PowerShell may launch WSL, which lacks your gh login."
  fi
  echo
  echo " Until step 2 lands, 'bash .github/scripts/tuning-status.sh' exits"
  echo " non-zero — the untuned state is machine-visible."
  echo
  echo " AI agent running this install on a human's behalf: relay the two"
  echo " next steps above to the human and offer to run the"
  echo " 'project-onboarding' skill now — do not summarize this handoff away."
  echo "=================================================================="
fi
