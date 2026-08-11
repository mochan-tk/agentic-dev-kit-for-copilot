#!/usr/bin/env bash
# check-escalation-wording.sh — fail when an escalation failure count is
# restated outside the normative skills.
#
# The escalation ladder (tiers and failure budgets) is defined once, in
# .github/skills/session-orchestration/SKILL.md; the verification skill's
# budget line and the retro skill's lesson-capture trigger mirror it by
# design. Every other Copilot surface must defer to the ladder without
# restating its counts: duplicated numbers drift from the design authority.
#
# A violation is a line in a scanned surface that pairs a count word with an
# escalation word. Scanned surfaces: AGENTS.md, .github/copilot-instructions.md,
# .github/agents/, .github/prompts/, .github/instructions/, and every
# .github/skills/*/SKILL.md except the three normative files above.
#
# Output: brief OK summary and exit 0 when clean; file:line:content listing
# and exit 1 on violation. Dependencies: bash 3.2+, grep, git only — runs
# identically in CI (.github/workflows/ci.yml, quality job) and on dev
# machines.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Both patterns must hit on the same line to count as a violation. Word
# boundaries (-w) keep "twofold" or "attempting" from matching partial words.
COUNT_RE='two|twice|three|third|second|consecutive'
ESCALATION_RE='fail|fails|failed|failing|failure|failures|death|deaths|strike|strikes|escalate|escalates|escalated|escalating|escalation|attempt|attempts|attempted|retry|retries'

# The only files allowed to state failure counts (normative sources).
is_allowlisted() {
  case "$1" in
    .github/skills/session-orchestration/SKILL.md) return 0 ;;
    .github/skills/verification/SKILL.md) return 0 ;;
    .github/skills/retro/SKILL.md) return 0 ;;
    *) return 1 ;;
  esac
}

violations=0
scanned=0
while IFS= read -r f; do
  if is_allowlisted "$f"; then
    continue
  fi
  scanned=$((scanned + 1))
  hits="$(grep -inwE "$COUNT_RE" "$f" | grep -iwE "$ESCALATION_RE" || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      printf '%s:%s\n' "$f" "$hit"
      violations=$((violations + 1))
    done <<EOF
$hits
EOF
  fi
done <<EOF
$(git ls-files 'AGENTS.md' '.github/copilot-instructions.md' \
  '.github/agents/*.md' '.github/prompts/*.md' \
  '.github/instructions/*.md' '.github/skills/*/SKILL.md')
EOF

if [ "$violations" -gt 0 ]; then
  echo "FAIL — $violations escalation-count line(s) outside the normative" \
    "skills. Defer to .github/skills/session-orchestration/SKILL.md instead" \
    "of restating its numbers."
  exit 1
fi

echo "OK — no escalation counts outside the normative skills" \
  "($scanned surfaces scanned)."
