#!/usr/bin/env bash
# Validate Task ownership bodies and report conservative path overlap.

set -u

usage() {
  echo "Usage: ownership-overlap.sh --validate-body <file>" >&2
  echo "       ownership-overlap.sh -R owner/repo <issue> <issue> [...]" >&2
  exit 2
}

parse_body() {
  local body="$1" output="$2"
  local line item path check headings=0 paths=0 in_section=0 invalid=0
  local ownership_re='^#{2,3}[[:space:]]+File[[:space:]]ownership[[:space:]]*$'
  local heading_re='^#{1,6}[[:space:]]+'
  : > "$output"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ $ownership_re ]]; then
      headings=$((headings + 1))
      in_section=1
      continue
    fi
    if [ "$in_section" -eq 1 ] && [[ "$line" =~ $heading_re ]]; then
      in_section=0
      continue
    fi
    [ "$in_section" -eq 1 ] || continue
    [ -n "$line" ] || continue
    case "$line" in
      "- "*) item="${line#- }" ;;
      *) invalid=1; continue ;;
    esac
    [ -n "$item" ] || { invalid=1; continue; }
    case "$item" in
      \`*\`)
        path="${item#\`}"
        path="${path%\`}"
        case "$path" in ""|*\`*|*$'\t'*) invalid=1; continue ;; esac
        ;;
      *\`*|*[[:space:]]*) invalid=1; continue ;;
      *) path="$item" ;;
    esac
    check="$path"
    case "$check" in ./*) check="${check#./}" ;; esac
    case "$check" in
      ""|/*|[A-Za-z]:[\\/]*|..|../*|*/..|*/../*) invalid=1; continue ;;
    esac
    printf '%s\n' "$path" >> "$output"
    paths=$((paths + 1))
  done < "$body"

  if [ "$headings" -ne 1 ] || [ "$paths" -eq 0 ] || [ "$invalid" -ne 0 ]; then
    : > "$output"
    return 1
  fi
  return 0
}

literal_prefix() {
  local value="$1" char i=0
  case "$value" in ./*) value="${value#./}" ;; esac
  PREFIX="$value"
  while [ "$i" -lt "${#value}" ]; do
    char="${value:$i:1}"
    case "$char" in
      "*"|"?"|"[") PREFIX="${value:0:$i}"; return ;;
    esac
    i=$((i + 1))
  done
}

paths_overlap() {
  local left="$1" right="$2" left_prefix right_prefix
  literal_prefix "$left"; left_prefix="$PREFIX"
  literal_prefix "$right"; right_prefix="$PREFIX"
  [ -z "$left_prefix" ] || [ -z "$right_prefix" ] && return 0
  case "$right_prefix" in "$left_prefix"*) return 0 ;; esac
  case "$left_prefix" in "$right_prefix"*) return 0 ;; esac
  return 1
}

if [ "${1:-}" = "--validate-body" ]; then
  [ "$#" -eq 2 ] || usage
  [ -f "$2" ] || { echo "error: body file not found: $2" >&2; exit 2; }
  parsed="$(mktemp "${TMPDIR:-/tmp}/ownership-parse.XXXXXX")" || exit 2
  trap 'rm -f "$parsed"' EXIT
  if parse_body "$2" "$parsed"; then
    echo "VALID $2 paths=$(wc -l < "$parsed" | tr -d ' ')"
    exit 0
  fi
  echo "UNCHECKABLE $2: File ownership body does not match the required grammar"
  exit 3
fi

[ "${1:-}" = "-R" ] && [ -n "${2:-}" ] || usage
repo="$2"
shift 2
[ "$#" -ge 2 ] || usage
command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || {
  echo "error: gh is not authenticated; run gh auth login" >&2
  exit 2
}

issues=()
for issue in "$@"; do
  case "$issue" in *[!0-9]*|"") echo "error: invalid issue number: $issue" >&2; exit 2 ;; esac
  for prior in ${issues[@]+"${issues[@]}"}; do
    [ "$prior" != "$issue" ] || { echo "error: duplicate issue number: $issue" >&2; exit 2; }
  done
  issues[${#issues[@]}]="$issue"
done

work="$(mktemp -d "${TMPDIR:-/tmp}/ownership-overlap.XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT
uncheckable=0
declarations=0
valid_tasks=0
for issue in ${issues[@]+"${issues[@]}"}; do
  if ! gh issue view "$issue" -R "$repo" --json body --jq .body > "$work/$issue.body"; then
    echo "error: API request failed while reading #$issue" >&2
    exit 2
  fi
  if parse_body "$work/$issue.body" "$work/$issue.paths"; then
    valid_tasks=$((valid_tasks + 1))
    count="$(wc -l < "$work/$issue.paths" | tr -d ' ')"
    declarations=$((declarations + count))
  else
    echo "UNCHECKABLE #$issue: File ownership body does not match the required grammar"
    uncheckable=$((uncheckable + 1))
  fi
done

collisions="$work/collisions"
: > "$collisions"
task_pairs=0
i=0
while [ "$i" -lt "${#issues[@]}" ]; do
  left_issue="${issues[$i]}"
  [ -s "$work/$left_issue.paths" ] || { i=$((i + 1)); continue; }
  j=$((i + 1))
  while [ "$j" -lt "${#issues[@]}" ]; do
    right_issue="${issues[$j]}"
    if [ -s "$work/$right_issue.paths" ]; then
      task_pairs=$((task_pairs + 1))
      while IFS= read -r left; do
        while IFS= read -r right; do
          if paths_overlap "$left" "$right"; then
            printf "OVERLAP #%s \`%s\` <> #%s \`%s\`\n" \
              "$left_issue" "$left" "$right_issue" "$right" >> "$collisions"
          fi
        done < "$work/$right_issue.paths"
      done < "$work/$left_issue.paths"
    fi
    j=$((j + 1))
  done
  i=$((i + 1))
done

overlaps="$(wc -l < "$collisions" | tr -d ' ')"
cat "$collisions"
if [ "$overlaps" -eq 0 ] && [ "$uncheckable" -eq 0 ]; then
  echo "NO_OVERLAP tasks=$valid_tasks declarations=$declarations pairs=$task_pairs"
else
  echo "SUMMARY overlaps=$overlaps tasks=$valid_tasks declarations=$declarations pairs=$task_pairs uncheckable=$uncheckable"
fi
[ "$uncheckable" -eq 0 ] || exit 3
[ "$overlaps" -eq 0 ] || exit 1
exit 0
