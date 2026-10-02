#!/usr/bin/env bash
# Offline distribution-boundary regressions using disposable real-source trees.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/scaffolddocs.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
INIT="$ROOT/.github/scripts/scaffold-init.sh"
N=0
new_target() {
  N=$((N + 1))
  TARGET="$WORK/target$N"
  init_sandbox_repo "$TARGET"
}
run_init() {
  (cd "$TARGET" && SCAFFOLD_SOURCE_DIR="$SOURCE" bash "$INIT" "$@")
}
check() {
  local name="$1"
  shift
  if "$@"; then t_ok "$name"; else t_fail "$name"; fi
}
not_grep() { ! grep "$@"; }
dir_empty() { [ -z "$(find "$1" -type f -print)" ]; }
snapshot() {
  (cd "$TARGET" && find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort)
  git -C "$TARGET" ls-files --stage
  if [ -f "$TARGET/.git/index" ]; then cksum < "$TARGET/.git/index"; fi
}
cat > "$WORK/expected" <<'EOF'
.github/docs/adopter-feedback.md
.github/docs/agreements/README.md
.github/docs/agreements/adr/ADR-0000-template.md
.github/docs/agreements/glossary.md
.github/docs/agreements/non-goals.md
.github/docs/agreements/requirements.md
.github/docs/agreements/retro-log.md
.github/docs/context/README.md
EOF
docs_set() {
  (cd "$TARGET" && find .github/docs -type f | LC_ALL=C sort)
}
empty_ledgers() {
  local base="$TARGET/.github/docs/agreements" f
  for f in requirements glossary retro-log; do
    [ -f "$base/$f.md" ] || return 1
    [ "$(grep -c '^|' "$base/$f.md")" -eq 2 ] || return 1
  done
  [ -f "$base/non-goals.md" ] && ! grep -Eq '^- .*NG-[0-9]+' "$base/non-goals.md"
}

SOURCE="$ROOT"
new_target
expect_rc 0 "real-source fresh install succeeds" run_init
docs_set > "$WORK/actual"
check "real-source docs tree equals exactly eight bootstrap destinations" cmp -s "$WORK/expected" "$WORK/actual"
git -C "$TARGET" ls-files .github/docs | LC_ALL=C sort > "$WORK/index-docs"
check "real-source staged docs set equals the allowlist" cmp -s "$WORK/expected" "$WORK/index-docs"
check "fresh ledgers have headers but no inherited entries" empty_ledgers
check "payload storage is not installed or staged" test ! -e "$TARGET/.github/templates/adopter-docs"
if [ -f "$ROOT/.github/scripts/scaffold-docs.manifest" ]; then
  while IFS=$'\t' read -r dest src; do
    case "$dest" in ''|\#*) continue ;; esac
    check "bootstrap bytes equal source: $dest" cmp -s "$TARGET/$dest" "$ROOT/$src"
  done < "$ROOT/.github/scripts/scaffold-docs.manifest"
else
  t_fail "real source supplies the documentation manifest"
fi

# Build an offline real-source fixture with future, unknown history and
# populated live ledgers. Test data never changes the source checkout.
SOURCE="$WORK/source"
mkdir -p "$SOURCE"
tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$SOURCE" -xf -
mkdir -p "$SOURCE/.github/docs/context/future" "$SOURCE/.github/templates/adopter-docs/agreements"
echo "future collection" > "$SOURCE/.github/docs/context/future/INDEX.md"
echo "future ADR" > "$SOURCE/.github/docs/agreements/adr/ADR-0005-future.md"
echo "unknown doc" > "$SOURCE/.github/docs/unknown.md"
for f in requirements glossary non-goals retro-log; do
  printf '\n| KIT-ENTRY | inherited data | must not ship |\n' >> "$SOURCE/.github/docs/agreements/$f.md"
done
# Before the production representation lands, fixtures still encode the
# approved contract so invalid-source regressions reach the old installer.
if [ ! -f "$SOURCE/.github/scripts/scaffold-docs.manifest" ]; then
  : > "$SOURCE/.github/scripts/scaffold-docs.manifest"
  while IFS= read -r dest; do
    src="$dest"
    case "$dest" in
      */requirements.md|*/glossary.md|*/non-goals.md|*/retro-log.md)
        src=".github/templates/adopter-docs/agreements/${dest##*/}"
        printf '# Empty fixture ledger\n\n| Column | Meaning |\n|---|---|\n' > "$SOURCE/$src"
        ;;
    esac
    printf '%s\t%s\n' "$dest" "$src" >> "$SOURCE/.github/scripts/scaffold-docs.manifest"
  done < "$WORK/expected"
fi
cp "$SOURCE/.github/scripts/scaffold-docs.manifest" "$WORK/valid-manifest"
new_target
expect_rc 0 "populated future-source install succeeds" run_init
docs_set > "$WORK/actual"
check "unknown context, ADR and doc are excluded from real install" cmp -s "$WORK/expected" "$WORK/actual"
check "populated source agreements and multi-row retro still seed empty ledgers" empty_ledgers
new_target
echo "staged sentinel" > "$TARGET/sentinel"
git -C "$TARGET" add sentinel
snapshot > "$WORK/before"
run_init --dry-run > "$WORK/dry" 2>&1
snapshot > "$WORK/after"
check "dry-run preserves direct tree, bytes and index snapshot" cmp -s "$WORK/before" "$WORK/after"
awk '$1 == "install" && $2 ~ /^\.github\/docs\// { print $2 }' "$WORK/dry" | LC_ALL=C sort > "$WORK/dry-docs"
check "dry-run docs plan equals exactly the allowlist" cmp -s "$WORK/expected" "$WORK/dry-docs"
check "dry-run excludes payload storage" not_grep -q '\.github/templates/adopter-docs' "$WORK/dry"

invalid() {
  local name="$1" mode
  for mode in real dry; do
    new_target
    mkdir -p "$TARGET/.github/docs"
    echo "keep existing" > "$TARGET/.github/docs/owned.md"
    echo "staged sentinel" > "$TARGET/sentinel"
    git -C "$TARGET" add sentinel
    snapshot > "$WORK/before"
    if [ "$mode" = dry ]; then
      expect_rc_grep 3 'error:.*(manifest|payload|documentation)' "$name ($mode) fails explicitly before writes" run_init --dry-run
    else
      expect_rc_grep 3 'error:.*(manifest|payload|documentation)' "$name ($mode) fails explicitly before writes" run_init
    fi
    snapshot > "$WORK/after"
    check "$name ($mode) leaves tree, content and index identical" cmp -s "$WORK/before" "$WORK/after"
  done
}
rm "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "missing manifest"
cp "$WORK/valid-manifest" "$SOURCE/.github/scripts/scaffold-docs.manifest"
chmod a-r "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "unreadable manifest"
chmod u+r "$SOURCE/.github/scripts/scaffold-docs.manifest"
printf '# comments only\n\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "comment-only manifest"
for line in \
  '.github/docs/bad.md source.md' \
  $'.github/docs/bad.md\t' \
  $'.github/docs/bad.md\tREADME.md\textra' \
  $'/absolute.md\tREADME.md' \
  $'.github/docs/../escape.md\tREADME.md' \
  $'.github/docs/new/\tREADME.md' \
  $'.github/docs/.\tREADME.md' \
  $'.github/docs/./bad.md\tREADME.md' \
  $'.github/docs//bad.md\tREADME.md' \
  $'./.github/docs/bad.md\tREADME.md' \
  $'.github/docs/bad.md\tREADME.md ' \
  $'README.md\tREADME.md' \
  $'.github/docs/bad.md\t.github/docs/adopter-feedback.md' \
  $'.github/docs/bad.md\tmissing.md'; do
  printf '%s\n' "$line" > "$SOURCE/.github/scripts/scaffold-docs.manifest"
  invalid "invalid manifest entry"
done
cat "$WORK/valid-manifest" "$WORK/valid-manifest" > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "duplicate destination"
printf '.github/docs/new.md\tREADME.md\n.github/docs/new.md/child.md\tREADME.md\n' \
  > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "parent-child destinations"
printf '.github/docs/new.md/child.md\tREADME.md\n.github/docs/new.md\tREADME.md\n' \
  > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "child-parent destinations"
: > "$SOURCE/empty.md"
printf '.github/docs/bad.md\tempty.md\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "empty payload"
ln -s README.md "$SOURCE/linked.md"
printf '.github/docs/bad.md\tlinked.md\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "symlinked payload"
mkdir "$SOURCE/directory"
printf '.github/docs/bad.md\tdirectory\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "non-file payload"
echo "readable bytes" > "$SOURCE/unreadable.md"
chmod a-r "$SOURCE/unreadable.md"
printf '.github/docs/bad.md\tunreadable.md\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "unreadable payload"
chmod u+r "$SOURCE/unreadable.md"
ln -s .github/templates/adopter-docs "$SOURCE/linked-dir"
printf '.github/docs/bad.md\tlinked-dir/agreements/requirements.md\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
invalid "symlinked payload ancestor"
cp "$WORK/valid-manifest" "$SOURCE/.github/scripts/scaffold-docs.manifest"

new_target
expect_rc 0 "install before upgrade preservation cases" run_init
while IFS= read -r dest; do echo "ADOPTER MODIFIED $dest" > "$TARGET/$dest"; done < "$WORK/expected"
mkdir -p "$TARGET/.github/docs/context/future"
echo "OLD KIT CONTEXT" > "$TARGET/.github/docs/context/future/INDEX.md"
echo "OLD KIT ADR" > "$TARGET/.github/docs/agreements/adr/ADR-0004-kit.md"
echo "OLD RETRO ROW" >> "$TARGET/.github/docs/agreements/retro-log.md"
echo "APP OWNED ADR" > "$TARGET/.github/docs/agreements/adr/ADR-0001-adopter.md"
(cd "$TARGET" && find .github/docs -type f -exec cksum {} + | LC_ALL=C sort) > "$WORK/docs-before"
expect_rc 0 "upgrade succeeds with adopter docs and previously installed kit records" run_init --upgrade
(cd "$TARGET" && find .github/docs -type f -exec cksum {} + | LC_ALL=C sort) > "$WORK/docs-after"
check "upgrade preserves every allowed doc, old kit record and adopter ADR byte-for-byte" cmp -s "$WORK/docs-before" "$WORK/docs-after"
rm "$TARGET/.github/docs/context/future/INDEX.md" "$TARGET/.github/docs/agreements/adr/ADR-0004-kit.md" "$TARGET/.github/docs/agreements/glossary.md"
expect_rc 0 "upgrade after operator removal succeeds" run_init --upgrade
check "upgrade adds missing bootstrap payload with exact bytes" cmp -s "$TARGET/.github/docs/agreements/glossary.md" "$SOURCE/.github/templates/adopter-docs/agreements/glossary.md"
check "upgrade never re-adds operator-removed kit context" test ! -e "$TARGET/.github/docs/context/future/INDEX.md"
check "upgrade never re-adds kit ADRs" test ! -e "$TARGET/.github/docs/agreements/adr/ADR-0005-future.md"

new_target
mkdir -p "$TARGET/.github/docs/agreements" "$TARGET/.github/docs/context/future"
echo "ADOPTER" > "$TARGET/.github/docs/agreements/requirements.md"
echo "KEEP HISTORY" > "$TARGET/.github/docs/context/future/INDEX.md"
snapshot > "$WORK/before"
expect_rc_grep 1 'refusing to overwrite existing files' "default payload collision refuses" run_init
snapshot > "$WORK/after"
check "default collision preserves tree and index" cmp -s "$WORK/before" "$WORK/after"
expect_rc_grep 0 'overwrote   .github/docs/agreements/requirements.md' "force reports mapped payload overwrite" run_init --force
check "force writes the approved payload bytes" cmp -s "$TARGET/.github/docs/agreements/requirements.md" "$SOURCE/.github/templates/adopter-docs/agreements/requirements.md"
check "force preserves excluded history bytes" grep -qx 'KEEP HISTORY' "$TARGET/.github/docs/context/future/INDEX.md"
run_init --force --dry-run > "$WORK/force-dry" 2>&1
check "force does not plan unknown kit records" not_grep -Eq 'context/future|ADR-0005|unknown.md' "$WORK/force-dry"

# Pin byte preservation for the builtins-only mapped copy under both shells.
printf 'first\r\n\0\0last-without-newline\0' > "$SOURCE/bytes.md"
printf '.github/docs/bytes.md\tbytes.md\n' > "$SOURCE/.github/scripts/scaffold-docs.manifest"
new_target
expect_rc 0 "binary-boundary payload fresh install succeeds" run_init
check "fresh payload preserves CRLF, consecutive/trailing NULs" cmp -s "$SOURCE/bytes.md" "$TARGET/.github/docs/bytes.md"
printf 'no-final-newline' > "$SOURCE/bytes.md"
expect_rc 0 "binary-boundary payload force install succeeds" run_init --force
check "force payload preserves missing final newline" cmp -s "$SOURCE/bytes.md" "$TARGET/.github/docs/bytes.md"
rm "$TARGET/.github/docs/bytes.md"
printf 'no-final-newline\0\0CRLF\r\nend' > "$SOURCE/bytes.md"
expect_rc 0 "binary-boundary missing payload upgrade succeeds" run_init --upgrade
check "upgrade adds byte-identical binary-boundary payload" cmp -s "$SOURCE/bytes.md" "$TARGET/.github/docs/bytes.md"
cp "$WORK/valid-manifest" "$SOURCE/.github/scripts/scaffold-docs.manifest"

for path in .github/docs .github/docs/agreements .github/docs/agreements/requirements.md; do
  new_target
  mkdir -p "$TARGET/${path%/*}" "$WORK/outside$N"
  ln -s "$WORK/outside$N" "$TARGET/$path"
  snapshot > "$WORK/before"
  expect_rc_grep 1 'refusing to write through symbolic links' "force refuses destination symlink: $path" run_init --force
  snapshot > "$WORK/after"
  check "symlink refusal leaves target/index inert: $path" cmp -s "$WORK/before" "$WORK/after"
  check "symlink refusal writes nothing outside target: $path" dir_empty "$WORK/outside$N"
done
t_summary
