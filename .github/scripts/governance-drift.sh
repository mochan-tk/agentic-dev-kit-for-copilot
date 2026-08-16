#!/usr/bin/env bash
# Report whether engine-defined governance controls remain in tuned files.
# Reads local files only. Exit: 0 report, 1 strict drift, 2 input/schema error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: governance-drift.sh --root DIR [--manifest PATH] [--waivers PATH] [--strict]

Report each manifest control as ACTIVE, MISSING, or WAIVED. Relative manifest
and waiver paths are resolved below DIR. Default reporting never fails for
drift; --strict exits 1 when any unwaived control is MISSING.
EOF
}

die() {
  echo "error: $*" >&2
  exit 2
}

ROOT=""
MANIFEST_ARG=".github/scripts/governance-controls.tsv"
WAIVER_ARG=".github/docs/agreements/governance-control-waivers.tsv"
STRICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root|--manifest|--waivers)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      case "$1" in
        --root) ROOT="$2" ;;
        --manifest) MANIFEST_ARG="$2" ;;
        --waivers) WAIVER_ARG="$2" ;;
      esac
      shift 2
      ;;
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument '$1'" ;;
  esac
done

[ -n "$ROOT" ] || { usage >&2; die "--root is required"; }
[ -d "$ROOT" ] || die "root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
for dep in awk grep; do
  command -v "$dep" >/dev/null 2>&1 || die "'$dep' not found"
done

resolve_below_root() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$ROOT" "$1" ;;
  esac
}
MANIFEST="$(resolve_below_root "$MANIFEST_ARG")"
WAIVERS="$(resolve_below_root "$WAIVER_ARG")"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

awk -F '\t' '
  /^[[:space:]]*($|#)/ { next }
  NF != 5 { printf "error: manifest line %d must have five tab-separated fields\n", NR > "/dev/stderr"; bad=1; next }
  { for (i=1; i<=5; i++) if ($i == "") { printf "error: manifest line %d has an empty field\n", NR > "/dev/stderr"; bad=1 } }
  $1 !~ /^[a-z0-9][a-z0-9-]*$/ { printf "error: invalid control ID on manifest line %d\n", NR > "/dev/stderr"; bad=1 }
  seen[$1]++ { printf "error: duplicate control ID %s\n", $1 > "/dev/stderr"; bad=1 }
  $2 ~ /^\// || $2 ~ /(^|\/)\.\.(\/|$)/ || $2 ~ /\/\// || $2 ~ /[[:space:]]/ {
    printf "error: unsafe target path on manifest line %d\n", NR > "/dev/stderr"; bad=1
  }
  substr($3,1,1) != "^" || substr($3,length($3),1) != "$" {
    printf "error: signature on manifest line %d must start with ^ and end with $\n", NR > "/dev/stderr"; bad=1
  }
  { rows++ }
  END { if (!rows) { print "error: manifest has no controls" > "/dev/stderr"; bad=1 }; exit bad ? 2 : 0 }
' "$MANIFEST" || exit 2

IDS=()
TARGETS=()
SIGNATURES=()
REMEDIATIONS=()
while IFS=$'\t' read -r id target signature _introduced remediation; do
  case "$id" in ""|\#*) continue ;; esac
  if grep -Eq -- "$signature" /dev/null 2>/dev/null; then
    :
  else
    regex_rc=$?
    [ "$regex_rc" -eq 1 ] || die "invalid ERE for control $id"
  fi
  IDS[${#IDS[@]}]="$id"
  TARGETS[${#TARGETS[@]}]="$target"
  SIGNATURES[${#SIGNATURES[@]}]="$signature"
  REMEDIATIONS[${#REMEDIATIONS[@]}]="$remediation"
done < "$MANIFEST"

WAIVER_IDS=()
WAIVER_REASONS=()
if [ -e "$WAIVERS" ]; then
  [ -f "$WAIVERS" ] || die "waiver path is not a file: $WAIVERS"
  awk -F '\t' '
    /^[[:space:]]*($|#)/ { next }
    NF != 2 || $1 == "" || $2 == "" {
      printf "error: waiver line %d requires a control ID and non-empty reason\n", NR > "/dev/stderr"; bad=1
    }
    seen[$1]++ { printf "error: duplicate waiver ID %s\n", $1 > "/dev/stderr"; bad=1 }
    END { exit bad ? 2 : 0 }
  ' "$WAIVERS" || exit 2
  while IFS=$'\t' read -r waiver_id waiver_reason; do
    case "$waiver_id" in ""|\#*) continue ;; esac
    known=0
    for id in "${IDS[@]}"; do [ "$id" != "$waiver_id" ] || known=1; done
    [ "$known" -eq 1 ] || die "waiver names unknown control $waiver_id"
    WAIVER_IDS[${#WAIVER_IDS[@]}]="$waiver_id"
    WAIVER_REASONS[${#WAIVER_REASONS[@]}]="$waiver_reason"
  done < "$WAIVERS"
fi

missing=0
for ((i=0; i<${#IDS[@]}; i++)); do
  id="${IDS[$i]}"
  target="${TARGETS[$i]}"
  if [ -f "$ROOT/$target" ] && grep -Eq -- "${SIGNATURES[$i]}" "$ROOT/$target"; then
    echo "ACTIVE $id target=$target"
    continue
  fi
  reason=""
  for ((j=0; j<${#WAIVER_IDS[@]}; j++)); do
    [ "${WAIVER_IDS[$j]}" != "$id" ] || reason="${WAIVER_REASONS[$j]}"
  done
  if [ -n "$reason" ]; then
    echo "WAIVED $id target=$target reason=$reason"
  else
    echo "MISSING $id target=$target remediation=${REMEDIATIONS[$i]} waiver=$WAIVER_ARG"
    missing=$((missing + 1))
  fi
done

[ "$STRICT" -eq 0 ] || [ "$missing" -eq 0 ] || exit 1
