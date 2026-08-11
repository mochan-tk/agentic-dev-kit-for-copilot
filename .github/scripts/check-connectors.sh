#!/usr/bin/env bash
# check-connectors.sh — fail when a connector definition under
# .github/connectors/ drifts from the structure the directory README
# declares in "Definition format (machine-checked)".
#
# Checks:
#   - framework integrity: README.md and CONNECTOR-TEMPLATE.md exist and
#     at least one connector definition is present;
#   - every other *.md file in the directory is a connector definition
#     and must contain a "## Metadata" section holding exactly the five
#     bullets (- name:, - access:, - reach:, - trust-default:,
#     - status:) once each and nothing else ("one bullet per field,
#     exactly"), a name equal to the filename stem, a status value of
#     core|community|experimental, and the four operation sections as
#     exact-name level-2 headings: ## discover, ## retrieve, ## pin,
#     ## verify. Bullets outside the Metadata section do not count.
#
# Output: one-line OK summary naming the validated connectors and
# exit 0; itemized ERROR lines on stderr and exit 1. Dependencies:
# bash 3.2+, grep, sed, awk only — runs identically in CI
# (.github/workflows/ci.yml, scaffold-self-check job) and on dev
# machines.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DIR=".github/connectors"
FAIL=0
FOUND=0
NAMES=""

err() {
  echo "check-connectors: ERROR — $1" >&2
  FAIL=1
}

if [ ! -d "$DIR" ]; then
  err "missing directory: $DIR"
  echo "check-connectors: FAIL — connector conformance problems (see above)." >&2
  exit 1
fi

for f in "$DIR/README.md" "$DIR/CONNECTOR-TEMPLATE.md"; do
  if [ ! -f "$f" ]; then
    err "missing framework file: $f"
  fi
done

# check_connector <file> — validate one definition; report via err().
check_connector() {
  local file="$1" base stem section field count extras extra_line
  local name_val status_line status_val sec
  base="$(basename "$file")"
  stem="$(basename "$file" .md)"

  if ! grep -qE '^## Metadata[[:space:]]*$' "$file"; then
    err "$base: missing '## Metadata' section"
  else
    # Only lines inside the Metadata section (up to the next level-2
    # heading) count as metadata; indented continuation lines are fine.
    section="$(awk '/^## Metadata[[:space:]]*$/{f=1; next} /^## /{f=0} f' "$file")"

    for field in name access reach trust-default status; do
      count="$(printf '%s\n' "$section" | grep -cE "^- ${field}:" || true)"
      if [ "$count" -eq 0 ]; then
        err "$base: missing metadata field '- ${field}:' in '## Metadata'"
      elif [ "$count" -gt 1 ]; then
        err "$base: metadata field '- ${field}:' appears $count times (want exactly one)"
      fi
    done

    # "One bullet per field, exactly" — any other bullet is undeclared.
    extras="$(printf '%s\n' "$section" | grep -E '^- ' \
      | grep -vE '^- (name|access|reach|trust-default|status):' || true)"
    if [ -n "$extras" ]; then
      while IFS= read -r extra_line; do
        err "$base: undeclared bullet in '## Metadata': '$extra_line'"
      done <<EOF_EXTRAS
$extras
EOF_EXTRAS
    fi

    # The README's field table: name matches the filename.
    name_val="$(printf '%s\n' "$section" \
      | sed -n 's/^- name:[[:space:]]*//p' | head -n 1 \
      | sed 's/[[:space:]]*$//')"
    if [ -n "$name_val" ] && [ "$name_val" != "$stem" ]; then
      err "$base: name '$name_val' does not match filename stem '$stem'"
    fi

    # Value check only when the bullet exists (absence and duplication
    # are already itemized above).
    status_line="$(printf '%s\n' "$section" | grep -E '^- status:' | head -n 1 || true)"
    if [ -n "$status_line" ]; then
      status_val="$(printf '%s\n' "$status_line" \
        | sed -e 's/^- status:[[:space:]]*//' -e 's/[[:space:]]*$//')"
      case "$status_val" in
        core|community|experimental) : ;;
        *) err "$base: invalid status value '$status_val' (want core, community, or experimental)" ;;
      esac
    fi
  fi

  for sec in discover retrieve pin verify; do
    if ! grep -qE "^## ${sec}[[:space:]]*$" "$file"; then
      err "$base: missing operation section '## ${sec}'"
    fi
  done
}

for file in "$DIR"/*.md; do
  # An unmatched glob stays literal; skip it.
  [ -f "$file" ] || continue
  case "$(basename "$file")" in
    README.md|CONNECTOR-TEMPLATE.md) continue ;;
  esac
  FOUND=$((FOUND + 1))
  NAMES="${NAMES:+$NAMES, }$(basename "$file" .md)"
  check_connector "$file"
done

if [ "$FOUND" -eq 0 ]; then
  err "no connector definitions found in $DIR (README and CONNECTOR-TEMPLATE excluded)"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "check-connectors: FAIL — connector conformance problems (see above)." >&2
  exit 1
fi
echo "check-connectors: OK — $FOUND connector definition(s) conform: $NAMES."
