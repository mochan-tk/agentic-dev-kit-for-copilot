#!/usr/bin/env bash
# check-agent-tools.sh — fail when the orchestrator's tool allowlist and the
# protocol it is supposed to run have drifted apart.
#
# Why: a custom agent's `tools` property is a strict allowlist. Omit it (or
# write `["*"]`) and the agent gets everything; write a list and it gets
# only what the list names. The scaffold shipped `orchestrator` with
# ["read", "search", "execute", "agent", "github/*"] and a skill telling it
# to create sessions, message children, approve their plans and archive
# them — none of which it could do. The defect survived from the first
# commit because nothing compared the two files (#47).
#
# Unrecognized tool names are ignored by the runtime, which is what makes
# naming app tools in a portable profile safe — and also what makes this
# failure silent: a missing name looks exactly like a name that does not
# apply here. Silence is why this guard exists.
#
# The rule this enforces, in both directions:
#   1. Every app tool the skill's protocol table names must appear in the
#      orchestrator's allowlist. Add a protocol step, grant its tool.
#   2. The allowlist must stay an allowlist, and `edit` must stay out of it
#      (AGENTS.md §4, #43) — including its aliases and the `*` wildcard,
#      so the role cannot be unrestricted by a well-meaning cleanup.
#
# Usage: check-agent-tools.sh [skill_file] [agent_file]
# Output: brief OK summary and exit 0 when the two agree; the specific
# mismatch and exit 1 otherwise.
# Dependencies: bash 3.2+, awk, grep, sed, tr only.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="${1:-$ROOT/.github/skills/session-orchestration/SKILL.md}"
AGENT="${2:-$ROOT/.github/agents/orchestrator.agent.md}"

for f in "$SKILL" "$AGENT"; do
  [ -r "$f" ] || { echo "check-agent-tools: ERROR — cannot read $f" >&2; exit 2; }
done

# Rows of the protocol table whose first cell names an argument rather than a
# tool. `notify_on_idle` is a parameter of create_session; granting it is not
# a thing the runtime can do.
NOT_TOOLS="notify_on_idle"

# Aliases that grant editing, per GitHub's custom-agent tool-alias table.
# Compared case-insensitively, as the runtime does.
EDIT_ALIASES="edit multiedit write notebookedit"

protocol_tools=$(
  awk '
    /App tools that instantiate the protocol/ { intable = 1; next }
    intable && /^\|/ {
      cell = $0
      sub(/^\|[ \t]*/, "", cell)
      sub(/[ \t]*\|.*$/, "", cell)
      if (match(cell, /`[A-Za-z_][A-Za-z0-9_]*`/)) {
        print substr(cell, RSTART + 1, RLENGTH - 2)
        seen = 1
      }
      next
    }
    intable && seen && !/^\|/ { intable = 0 }
  ' "$SKILL"
)

if [ -z "$protocol_tools" ]; then
  echo "check-agent-tools: FAIL — no protocol tool table found in $SKILL" >&2
  echo "  Expected a table under 'App tools that instantiate the protocol'." >&2
  echo "  If that section was renamed, this guard must be renamed with it." >&2
  exit 1
fi

tools_block=$(awk '/^tools:/ { found = 1 } found { print; if (/\]/) exit }' "$AGENT")
if [ -z "$tools_block" ]; then
  echo "check-agent-tools: FAIL — $AGENT declares no 'tools' property." >&2
  echo "  An absent allowlist grants every tool, 'edit' included, which is" >&2
  echo "  the grant AGENTS.md §4 relies on withholding." >&2
  exit 1
fi

# Both documented forms: a YAML flow array (possibly wrapped over several
# lines) and a bare comma-separated string.
if printf '%s' "$tools_block" | grep -q '\['; then
  allowed=$(printf '%s' "$tools_block" \
    | tr "'" '"' \
    | grep -o '"[^"]*"' \
    | tr -d '"' \
    | tr '\n' ' ')
else
  allowed=$(printf '%s' "$tools_block" \
    | sed 's/^tools:[[:space:]]*//' \
    | tr ',' '\n' \
    | tr -d '"'"'" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | tr '\n' ' ')
fi

errors=0
report() { echo "check-agent-tools: FAIL — $1" >&2; errors=$((errors + 1)); }

# Word-splitting the tool lists must not glob: an allowlist of ["*"] would
# otherwise expand to the working directory's filenames and vanish.
set -f

# `*` grants everything, so membership is moot and the wildcard is itself
# the violation: it hands back the one grant this role withholds.
case " $allowed " in
  *" * "*)
    report "the orchestrator's allowlist is '*', which grants 'edit'."
    echo "  The role conducts and verifies; it does not edit files (#43)." >&2
    exit 1
    ;;
esac

for tool in $protocol_tools; do
  case " $NOT_TOOLS " in *" $tool "*) continue ;; esac
  case " $allowed " in
    *" $tool "*) ;;
    *)
      report "the protocol uses '$tool' but the orchestrator cannot."
      echo "  $SKILL names it a protocol step; $AGENT does not grant it." >&2
      echo "  Add \"$tool\" to the tools list, or stop calling it a step." >&2
      ;;
  esac
done

for granted in $allowed; do
  lower=$(printf '%s' "$granted" | tr '[:upper:]' '[:lower:]')
  case " $EDIT_ALIASES " in
    *" $lower "*)
      report "the orchestrator grants '$granted', an alias of 'edit'."
      echo "  Withholding edit is the one runtime boundary this scaffold" >&2
      echo "  actually has (AGENTS.md §4). Conduct, do not implement." >&2
      ;;
  esac
done

if [ "$errors" -gt 0 ]; then
  exit 1
fi

granted_count=$(printf '%s' "$allowed" | wc -w | tr -d ' ')
checked_count=$(printf '%s\n' "$protocol_tools" | grep -c . | tr -d ' ')
echo "check-agent-tools: OK — $checked_count protocol tool row(s) reconciled" \
     "against $granted_count granted tool(s); edit withheld."
