#!/usr/bin/env bash
# test-retro-hygiene.sh — regression tests for the monthly retro hygiene review.
#
# The regression is source-template-only and deterministic: the script must
# compare official checkpoint URLs against a committed baseline without
# trusting any upstream title or page content, and it must keep `unknown`
# when a fetch fails or the repository is not the source template.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/retrohygiene.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fixture_values() {
  python3 - <<'PY2'
import hashlib
values = {
  'app_current': hashlib.sha256(b'app current content\n').hexdigest(),
  'app_changed': hashlib.sha256(b'app changed content\n').hexdigest(),
  'cli_current': hashlib.sha256(b'cli current content\n').hexdigest(),
  'cli_changed': hashlib.sha256(b'cli changed content\n').hexdigest(),
  'docs_current': hashlib.sha256(b'copilot docs current content\n').hexdigest(),
  'docs_changed': hashlib.sha256(b'copilot docs changed content\n').hexdigest(),
  'rss_current': 'https://example.test/copilot/1|Tue, 01 Jan 2024 00:00:00 +0000',
  'rss_changed': 'https://example.test/copilot/2|Wed, 02 Jan 2024 00:00:00 +0000',
}
for key in sorted(values):
  print(f'{key}={values[key]!r}')
PY2
}

write_baseline() {
  local dir="$1"
  local mode="${2:-current}"
  local app_value cli_value docs_value rss_value
  local app_current app_changed cli_current cli_changed docs_current docs_changed rss_current rss_changed

  while IFS='=' read -r key value; do
    value="${value#\'}"
    value="${value%\'}"
    case "$key" in
      app_current) app_current="$value" ;;
      app_changed) app_changed="$value" ;;
      cli_current) cli_current="$value" ;;
      cli_changed) cli_changed="$value" ;;
      docs_current) docs_current="$value" ;;
      docs_changed) docs_changed="$value" ;;
      rss_current) rss_current="$value" ;;
      rss_changed) rss_changed="$value" ;;
    esac
  done < <(fixture_values)

  case "$mode" in
    current)
      app_value="$app_current"
      cli_value="$cli_current"
      docs_value="$docs_current"
      rss_value="$rss_current"
      ;;
    changed_app)
      app_value="$app_changed"
      cli_value="$cli_current"
      docs_value="$docs_current"
      rss_value="$rss_current"
      ;;
    changed_cli)
      app_value="$app_current"
      cli_value="$cli_changed"
      docs_value="$docs_current"
      rss_value="$rss_current"
      ;;
    changed_rss)
      app_value="$app_current"
      cli_value="$cli_current"
      docs_value="$docs_current"
      rss_value="$rss_changed"
      ;;
    changed_docs)
      app_value="$app_current"
      cli_value="$cli_current"
      docs_value="$docs_changed"
      rss_value="$rss_current"
      ;;
    *)
      app_value="$app_current"
      cli_value="$cli_current"
      docs_value="$docs_current"
      rss_value="$rss_current"
      ;;
  esac

  cat > "$dir/.github/scripts/platform-capability-baseline.tsv" <<EOF2
capability	kind	official_url	baseline_value
copilot_app	changelog_sha	https://raw.githubusercontent.com/github/app/main/changelog.md	$app_value
copilot_cli	changelog_sha	https://raw.githubusercontent.com/github/copilot-cli/main/changelog.md	$cli_value
copilot_rss	rss_guid_date	https://github.blog/changelog/label/copilot/feed/	$rss_value
rubber_duck	docs_sha	https://raw.githubusercontent.com/github/docs/main/content/copilot/concepts/agents/copilot-cli/rubber-duck.md	$docs_value
copilot_docs	docs_sha	https://raw.githubusercontent.com/github/docs/main/content/copilot/index.md	$docs_value
EOF2
}

make_fake_gh() {
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  repo)
    if [ "${2:-}" = "view" ]; then
      echo '{"nameWithOwner":"mochan-tk/agentic-dev-kit-for-copilot"}'
      exit 0
    fi
    ;;
  issue)
    if [ "${2:-}" = "list" ]; then
      if [ "${RETRO_HYGIENE_ISSUE_EXISTS:-0}" = "1" ]; then
        echo '[{"title":"Retro hygiene review 2026-08","url":"https://example.test/issues/999"}]'
      else
        echo '[]'
      fi
      exit 0
    fi
    if [ "${2:-}" = "create" ]; then
      echo 'https://example.test/issues/999'
      exit 0
    fi
    ;;
  *) ;;
esac
exit 0
SHIM
  chmod +x "$1/bin/gh"
  PATH="$1/bin:$PATH"
  export PATH
}

make_fake_curl() {
  mkdir -p "$1/bin"
  cat > "$1/bin/curl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
url=""
out_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -w)
      shift
      ;;
    -o)
      shift
      out_file="${1:-}"
      shift
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

case "${RETRO_HYGIENE_MODE:-current}" in
  current)
    case "$url" in
      *app/main/changelog.md) body='app current content
' ;;
      *copilot-cli/main/changelog.md) body='cli current content
' ;;
      *changelog/label/copilot/feed*) body='<rss><channel><item><guid>https://example.test/copilot/1</guid><pubDate>Tue, 01 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>' ;;
      *rubber-duck.md) body='copilot docs current content
' ;;
      *copilot/index.md) body='copilot docs current content
' ;;
      *) body='fallback
' ;;
    esac
    ;;
  changed_app)
    case "$url" in
      *app/main/changelog.md) body='app changed content
' ;;
      *copilot-cli/main/changelog.md) body='cli current content
' ;;
      *changelog/label/copilot/feed*) body='<rss><channel><item><guid>https://example.test/copilot/1</guid><pubDate>Tue, 01 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>' ;;
      *rubber-duck.md) body='copilot docs current content
' ;;
      *copilot/index.md) body='copilot docs current content
' ;;
      *) body='fallback
' ;;
    esac
    ;;
  changed_cli)
    case "$url" in
      *app/main/changelog.md) body='app current content
' ;;
      *copilot-cli/main/changelog.md) body='cli changed content
' ;;
      *changelog/label/copilot/feed*) body='<rss><channel><item><guid>https://example.test/copilot/1</guid><pubDate>Tue, 01 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>' ;;
      *rubber-duck.md) body='copilot docs current content
' ;;
      *copilot/index.md) body='copilot docs current content
' ;;
      *) body='fallback
' ;;
    esac
    ;;
  changed_rss)
    case "$url" in
      *app/main/changelog.md) body='app current content
' ;;
      *copilot-cli/main/changelog.md) body='cli current content
' ;;
      *changelog/label/copilot/feed*) body='<rss><channel><item><guid>https://example.test/copilot/2</guid><pubDate>Wed, 02 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>' ;;
      *rubber-duck.md) body='copilot docs current content
' ;;
      *copilot/index.md) body='copilot docs current content
' ;;
      *) body='fallback
' ;;
    esac
    ;;
  changed_docs)
    case "$url" in
      *app/main/changelog.md) body='app current content
' ;;
      *copilot-cli/main/changelog.md) body='cli current content
' ;;
      *changelog/label/copilot/feed*) body='<rss><channel><item><guid>https://example.test/copilot/1</guid><pubDate>Tue, 01 Jan 2024 00:00:00 +0000</pubDate></item></channel></rss>' ;;
      *rubber-duck.md) body='copilot docs changed content
' ;;
      *copilot/index.md) body='copilot docs changed content
' ;;
      *) body='fallback
' ;;
    esac
    ;;
  fail)
    echo 'curl: failure forced for retro fixtures' >&2
    exit 22
    ;;
  *)
    echo 'unexpected mode' >&2
    exit 2
    ;;
esac

if [ -n "$out_file" ]; then
  printf '%s' "$body" > "$out_file"
fi
printf '%s
' "$url"
SHIM
  chmod +x "$1/bin/curl"
  PATH="$1/bin:$PATH"
  export PATH
}

setup_repo() {
  local dir="$1"
  mkdir -p "$dir/.github/scripts"
  cp "$REPO_ROOT/.github/scripts/retro-hygiene.sh" "$dir/.github/scripts/retro-hygiene.sh"
  cp "$REPO_ROOT/.github/scripts/platform-capability-baseline.tsv" "$dir/.github/scripts/platform-capability-baseline.tsv"
  cp "$REPO_ROOT/SCAFFOLD-CHANGELOG.md" "$dir/SCAFFOLD-CHANGELOG.md"
  cp "$REPO_ROOT/AGENTS.md" "$dir/AGENTS.md"
  mkdir -p "$dir/.github"
  cp "$REPO_ROOT/.github/copilot-instructions.md" "$dir/.github/copilot-instructions.md"
}

# --- source-template control: official URLs and deterministic baselines stay unchanged
setup_repo "$WORK/template-ok"
write_baseline "$WORK/template-ok" current
make_fake_gh "$WORK/template-ok"
make_fake_curl "$WORK/template-ok"
out=$(bash "$WORK/template-ok/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'No official Copilot capability changes detected'; then
  t_ok "source-template report stays unchanged for current official checkpoints"
else
  t_fail "source-template report stays unchanged for current official checkpoints"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- app-only change is reported as changed without trusting scraped titles
setup_repo "$WORK/template-app-change"
write_baseline "$WORK/template-app-change" current
make_fake_gh "$WORK/template-app-change"
export RETRO_HYGIENE_MODE=changed_app
make_fake_curl "$WORK/template-app-change"
out=$(bash "$WORK/template-app-change/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'copilot_app.*changed' && printf '%s
' "$out" | grep -Eq 'Does the platform now duplicate a skill'; then
  t_ok "app-only checkpoint change is reported as changed with the review checklist"
else
  t_fail "app-only checkpoint change is reported as changed with the review checklist"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- CLI-only change is reported as changed
setup_repo "$WORK/template-cli-change"
write_baseline "$WORK/template-cli-change" current
make_fake_gh "$WORK/template-cli-change"
export RETRO_HYGIENE_MODE=changed_cli
make_fake_curl "$WORK/template-cli-change"
out=$(bash "$WORK/template-cli-change/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'copilot_cli.*changed'; then
  t_ok "CLI-only checkpoint change is reported as changed"
else
  t_fail "CLI-only checkpoint change is reported as changed"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- RSS change is reported as changed and keeps the official feed URL
setup_repo "$WORK/template-rss-change"
write_baseline "$WORK/template-rss-change" current
make_fake_gh "$WORK/template-rss-change"
export RETRO_HYGIENE_MODE=changed_rss
make_fake_curl "$WORK/template-rss-change"
out=$(bash "$WORK/template-rss-change/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'copilot_rss.*changed' && printf '%s
' "$out" | grep -Eq 'https://github.blog/changelog/label/copilot/feed/'; then
  t_ok "RSS checkpoint change is reported with the official feed URL"
else
  t_fail "RSS checkpoint change is reported with the official feed URL"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- docs SHA change is reported as changed
setup_repo "$WORK/template-docs-change"
write_baseline "$WORK/template-docs-change" current
make_fake_gh "$WORK/template-docs-change"
export RETRO_HYGIENE_MODE=changed_docs
make_fake_curl "$WORK/template-docs-change"
out=$(bash "$WORK/template-docs-change/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'rubber_duck.*changed|copilot_docs.*changed'; then
  t_ok "docs SHA change is reported as changed"
else
  t_fail "docs SHA change is reported as changed"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- fetch failure remains unknown and the baseline remains authoritative
setup_repo "$WORK/template-unknown"
write_baseline "$WORK/template-unknown" current
make_fake_gh "$WORK/template-unknown"
export RETRO_HYGIENE_MODE=fail
make_fake_curl "$WORK/template-unknown"
out=$(bash "$WORK/template-unknown/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'copilot_app.*unknown'; then
  t_ok "fetch failure is preserved as unknown"
else
  t_fail "fetch failure is preserved as unknown"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- non-source-template repos skip the capability section entirely
setup_repo "$WORK/adopted"
write_baseline "$WORK/adopted" current
make_fake_gh "$WORK/adopted"
make_fake_curl "$WORK/adopted"
python3 - "$WORK/adopted/SCAFFOLD-CHANGELOG.md" <<'PY3'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
p.write_text(text.replace('sha=unknown', 'sha=deadbeef', 1))
PY3
out=$(bash "$WORK/adopted/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && ! printf '%s
' "$out" | grep -Eq '## Platform capability checkpoints'; then
  t_ok "adopted repositories do not render the source-template capability section"
else
  t_fail "adopted repositories do not render the source-template capability section"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- monthly issue creation is idempotent
setup_repo "$WORK/issue-idempotent"
write_baseline "$WORK/issue-idempotent" current
make_fake_gh "$WORK/issue-idempotent"
make_fake_curl "$WORK/issue-idempotent"
out=$(RETRO_HYGIENE_ISSUE_EXISTS=0 bash "$WORK/issue-idempotent/.github/scripts/retro-hygiene.sh" --create-issue -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'Filing review issue|Retro hygiene review'; then
  export RETRO_HYGIENE_ISSUE_EXISTS=1
  out2=$(bash "$WORK/issue-idempotent/.github/scripts/retro-hygiene.sh" --create-issue -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc2=$?
  rc2=${rc2:-0}
  if [ "$rc2" -eq 0 ] && printf '%s
' "$out2" | grep -Eq 'Idempotent skip'; then
    t_ok "monthly issue creation is idempotent"
  else
    t_fail "monthly issue creation is idempotent"
    printf '%s
' "$out2" | sed 's/^/    # /'
  fi
else
  t_fail "monthly issue creation is idempotent"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- the report explicitly includes the Rubber Duck/#68 seed and #69 retirement pointer
setup_repo "$WORK/seed-header"
write_baseline "$WORK/seed-header" current
make_fake_gh "$WORK/seed-header"
make_fake_curl "$WORK/seed-header"
out=$(bash "$WORK/seed-header/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq 'Rubber Duck/#68|#69'; then
  t_ok "initial review seed and retirement pointer are present"
else
  t_fail "initial review seed and retirement pointer are present"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- rendered markdown keeps real line breaks instead of literal \n escapes
setup_repo "$WORK/rendered-markdown"
write_baseline "$WORK/rendered-markdown" current
make_fake_gh "$WORK/rendered-markdown"
make_fake_curl "$WORK/rendered-markdown"
out=$(bash "$WORK/rendered-markdown/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && ! printf '%s
' "$out" | grep -F '\\n' >/dev/null && printf '%s
' "$out" | grep -Eq '^\| Issue \| Title \| Occurrences \| Age \(days\) \| Status \|$'; then
  t_ok "report tables render with real Markdown line breaks"
else
  t_fail "report tables render with real Markdown line breaks"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

# --- multiple changed rows render as separate bullets rather than being glued together
setup_repo "$WORK/multi-change"
write_baseline "$WORK/multi-change" current
make_fake_gh "$WORK/multi-change"
export RETRO_HYGIENE_MODE=changed_docs
make_fake_curl "$WORK/multi-change"
out=$(bash "$WORK/multi-change/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s
' "$out" | grep -Eq '^- rubber_duck: changed' && printf '%s
' "$out" | grep -Eq '^- copilot_docs: changed'; then
  t_ok "multiple changed rows render as distinct bullets"
else
  t_fail "multiple changed rows render as distinct bullets"
  printf '%s
' "$out" | sed 's/^/    # /'
fi

t_summary
