#!/usr/bin/env bash
# test-agent-tools.sh — regression tests for
# .github/scripts/check-agent-tools.sh.
#
# The guard exists because a custom agent's `tools` property is a strict
# allowlist and unrecognized names are silently ignored: an orchestrator
# missing `create_session` looks exactly like one running somewhere that
# has no sessions. The scaffold shipped that defect from its first commit
# (#47). Each case writes a throwaway skill/agent pair and asserts the exit
# code and message.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

GUARD="$REPO_ROOT/.github/scripts/check-agent-tools.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agenttools.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

write_skill() {
  cat > "$WORK/$1" <<'EOF'
Prose before the table that must not be scanned for `tool_names`.

App tools that instantiate the protocol:

| Tool | Protocol step |
|---|---|
| `create_session` (kickoff prompt, mode, model) | Dispatch a supervisor or worker |
| `send_session_message` | Steering and the report hop |
| `notify_on_idle` | Wake the parent when a child stops |

Prose after the table mentioning `archive_session`, which is not a row.
EOF
}

write_agent() {
  printf -- '---\nname: orchestrator\ndescription: Conductor session.\ntools: %s\n---\n\nBody.\n' \
    "$2" > "$WORK/$1"
}

# --- a synced pair passes --------------------------------------------------
write_skill skill-ok.md
write_agent agent-ok.md '["read", "execute", "create_session", "send_session_message"]'
expect_rc_grep 0 "check-agent-tools: OK" \
  "allowlist covering every protocol row passes" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-ok.md"

# --- the shipped defect: a protocol tool absent from the allowlist ---------
write_agent agent-missing.md '["read", "search", "execute", "agent", "github/*"]'
expect_rc_grep 1 "the protocol uses 'create_session' but the orchestrator cannot" \
  "a protocol tool missing from the allowlist fails" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-missing.md"

# --- notify_on_idle is an argument, not a grantable tool ------------------
expect_rc_grep 1 "create_session" \
  "the argument row is not reported as a missing tool" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-missing.md"
if bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-missing.md" 2>&1 \
   | grep -q "notify_on_idle"; then
  t_fail "notify_on_idle must not be demanded as a tool"
else
  t_ok "notify_on_idle is excluded as an argument"
fi

# --- edit must stay withheld, under any alias ------------------------------
write_agent agent-edit.md '["read", "edit", "create_session", "send_session_message"]'
expect_rc_grep 1 "an alias of 'edit'" \
  "granting edit fails" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-edit.md"

write_agent agent-write.md '["read", "Write", "create_session", "send_session_message"]'
expect_rc_grep 1 "an alias of 'edit'" \
  "granting an edit alias under another name fails" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-write.md"

# --- an unrestricted allowlist is not a fix -------------------------------
write_agent agent-star.md '["*"]'
expect_rc_grep 1 "allowlist is '\*'" \
  "the wildcard allowlist fails" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-star.md"

# --- no tools property at all grants everything ---------------------------
printf -- '---\nname: orchestrator\ndescription: Conductor session.\n---\n\nBody.\n' \
  > "$WORK/agent-none.md"
expect_rc_grep 1 "declares no 'tools' property" \
  "an absent allowlist fails" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-none.md"

# --- the flow array may wrap over several lines ---------------------------
cat > "$WORK/agent-wrapped.md" <<'EOF'
---
name: orchestrator
description: Conductor session.
tools: ["read", "execute",
        "create_session",
        "send_session_message"]
---

Body.
EOF
expect_rc_grep 0 "check-agent-tools: OK" \
  "a wrapped flow array is parsed whole" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-wrapped.md"

# --- the comma-separated string form is also documented -------------------
write_agent agent-csv.md 'read, execute, create_session, send_session_message'
expect_rc_grep 0 "check-agent-tools: OK" \
  "the comma-separated string form is parsed" \
  bash "$GUARD" "$WORK/skill-ok.md" "$WORK/agent-csv.md"

# --- a renamed section must not silently disable the guard ----------------
printf 'No protocol table here.\n' > "$WORK/skill-empty.md"
expect_rc_grep 1 "no protocol tool table found" \
  "losing the table fails loudly instead of passing vacuously" \
  bash "$GUARD" "$WORK/skill-empty.md" "$WORK/agent-ok.md"

# --- the real files must agree --------------------------------------------
expect_rc_grep 0 "check-agent-tools: OK" \
  "the shipped orchestrator can run the shipped protocol" \
  bash "$GUARD"

t_summary
