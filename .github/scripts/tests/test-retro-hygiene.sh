#!/usr/bin/env bash
# test-retro-hygiene.sh — regression tests for the monthly retro hygiene review.
#
# The regression is source-template-only and deterministic: the script must
# compare official checkpoint URLs against the committed baseline without
# trusting any upstream title or page content, and it must keep `unknown`
# when a fetch fails or the repository is not the source template.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/retrohygiene.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

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
     # ignore format output; curl's -w is used by the script and we echo the final URL below
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
     *rubber-duck*) body='<html><head><title>Rubber Duck</title></head></html>' ;;
     *agent-plugins*) body='<html><head><title>Agent plugins 1.0 in VS Code, Copilot CLI, and the Copilot app</title></head></html>' ;;
     *app*) body='<html><head><title>GitHub Copilot app changelog</title></head></html>' ;;
     *copilot-cli*) body='<html><head><title>GitHub Copilot CLI changelog</title></head></html>' ;;
     *) body='<html><head><title>Missing</title></head></html>' ;;
   esac
   ;;
 changed)
   case "$url" in
     *rubber-duck*) body='<html><head><title>Rubber Duck</title></head></html>' ;;
     *agent-plugins*) body='<html><head><title>Agent plugins 1.0 in VS Code, Copilot CLI, and the Copilot app</title></head></html>' ;;
     *app*) body='<html><head><title>GitHub Copilot app changelog (changed)</title></head></html>' ;;
     *copilot-cli*) body='<html><head><title>GitHub Copilot CLI changelog</title></head></html>' ;;
     *) body='<html><head><title>Missing</title></head></html>' ;;
   esac
   ;;
 fail)
   echo 'curl: failure forced for retro fixtures' >&2
   exit 22
   ;;
 non_authoritative)
   case "$url" in
     *rubber-duck*) body='<html><head><title>About the rubber duck agent</title></head></html>'; url='https://example.com/rubber-duck' ;;
     *) body='<html><head><title>Missing</title></head></html>' ;;
   esac
   ;;
 unsafe)
   case "$url" in
     *app*) body='<html><head><title>Bad <script>alert(1)</script> & title</title></head></html>' ;;
     *) body='<html><head><title>Missing</title></head></html>' ;;
   esac
   ;;
 *)
   echo 'unexpected mode' >&2
   exit 2
   ;;
 esac

if [ -n "$out_file" ]; then
 printf '%s' "$body" > "$out_file"
fi
printf '%s\n' "$url"
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

# --- source-template control: official URLs and baseline titles stay unchanged
setup_repo "$WORK/template-ok"
make_fake_gh "$WORK/template-ok"
make_fake_curl "$WORK/template-ok"
out=$(bash "$WORK/template-ok/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'rubber_duck.*unchanged' && printf '%s\n' "$out" | grep -Eq 'copilot_app.*unchanged'; then
  t_ok "source-template report stays unchanged for official checkpoints"
else
  t_fail "source-template report stays unchanged for official checkpoints"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- changed upstream title is rendered as changed without trusting it
setup_repo "$WORK/template-changed"
make_fake_gh "$WORK/template-changed"
export RETRO_HYGIENE_MODE=changed
make_fake_curl "$WORK/template-changed"
out=$(bash "$WORK/template-changed/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'copilot_app.*changed'; then
  t_ok "changed title is reported as changed without executing it"
else
  t_fail "changed title is reported as changed without executing it"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- fetch failure remains unknown and the committed baseline is preserved
setup_repo "$WORK/template-unknown"
make_fake_gh "$WORK/template-unknown"
export RETRO_HYGIENE_MODE=fail
make_fake_curl "$WORK/template-unknown"
out=$(bash "$WORK/template-unknown/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'copilot_app.*unknown'; then
  t_ok "fetch failure is preserved as unknown"
else
  t_fail "fetch failure is preserved as unknown"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- non-authoritative pages stay unknown instead of being reinterpreted as changed
setup_repo "$WORK/template-non-authoritative"
make_fake_gh "$WORK/template-non-authoritative"
export RETRO_HYGIENE_MODE=non_authoritative
make_fake_curl "$WORK/template-non-authoritative"
out=$(bash "$WORK/template-non-authoritative/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'rubber_duck.*unknown'; then
  t_ok "non-authoritative fetches stay unknown"
else
  t_fail "non-authoritative fetches stay unknown"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- unsafe upstream titles are sanitized before being rendered in Markdown
setup_repo "$WORK/template-unsafe"
make_fake_gh "$WORK/template-unsafe"
export RETRO_HYGIENE_MODE=unsafe
make_fake_curl "$WORK/template-unsafe"
out=$(bash "$WORK/template-unsafe/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'Bad.*title' && ! printf '%s\n' "$out" | grep -Eq '<script>|&amp;|<'; then
  t_ok "unsafe titles are rendered as plain text"
else
  t_fail "unsafe titles are rendered as plain text"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- non-source-template repos skip the capability section entirely
setup_repo "$WORK/adopted"
make_fake_gh "$WORK/adopted"
make_fake_curl "$WORK/adopted"
sed -i '' 's/sha=unknown/sha=deadbeef/' "$WORK/adopted/SCAFFOLD-CHANGELOG.md"
out=$(bash "$WORK/adopted/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -Eq '## Platform capability checkpoints'; then
  t_ok "adopted repositories do not render the source-template capability section"
else
  t_fail "adopted repositories do not render the source-template capability section"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

# --- the report contains only official URLs, never untrusted interpolated values
setup_repo "$WORK/template-render"
make_fake_gh "$WORK/template-render"
export RETRO_HYGIENE_MODE=changed
make_fake_curl "$WORK/template-render"
out=$(bash "$WORK/template-render/.github/scripts/retro-hygiene.sh" -R mochan-tk/agentic-dev-kit-for-copilot 2>&1) || rc=$?
rc=${rc:-0}
unset RETRO_HYGIENE_MODE
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'https://docs.github.com/en/copilot/concepts/agents/copilot-cli/rubber-duck' && printf '%s\n' "$out" | grep -Eq 'https://github.blog/changelog/2026-08-12-agent-plugins-1-0-in-vs-code-copilot-cli-and-the-copilot-app/' && printf '%s\n' "$out" | grep -Eq 'https://github.com/github/app/blob/main/changelog.md'; then
  t_ok "official URLs are rendered without untrusted interpolated values"
else
  t_fail "official URLs are rendered without untrusted interpolated values"
  printf '%s\n' "$out" | sed 's/^/    # /'
fi

t_summary
