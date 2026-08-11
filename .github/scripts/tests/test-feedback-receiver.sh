#!/usr/bin/env bash
# test-feedback-receiver.sh — static guards for the receiving end of the
# adopter feedback loop (ADR-0002): the feedback.yml issue form, the
# adopter-feedback.yml labeling workflow, and the from:adopter taxonomy
# entry. These assert the shipped files, not sandboxes: the contract is
# "this exact surface stays sound", mirroring check-copilot-surface.
#
# Dependency: python3 with PyYAML — the same requirement
# check-copilot-surface.sh already imposes on every environment that
# runs the gates.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
. "$HERE/lib.sh"

FORM="$REPO_ROOT/.github/ISSUE_TEMPLATE/feedback.yml"
WORKFLOW="$REPO_ROOT/.github/workflows/adopter-feedback.yml"
LABELS_SH="$REPO_ROOT/.github/scripts/setup-labels.sh"
LIB="$REPO_ROOT/.github/scripts/feedback-lib.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/guardtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "not ok - python3 with PyYAML is required (same as check-copilot-surface)"
  echo "# 1 case(s), 1 failed"
  exit 1
fi

# --- the issue form ---------------------------------------------------------

cat > "$WORK/form.py" <<'PYEOF'
import sys, yaml

with open(sys.argv[1]) as fh:
    form = yaml.safe_load(fh)

assert form.get("name"), "form must carry a name"
assert form.get("title", "").startswith("[adopter-feedback] "), \
    "form title prefix must match the helper's"
assert "from:adopter" in form.get("labels", []), \
    "form must self-label from:adopter (web path uses no automation)"

blocks = form.get("body", [])
dropdowns = [b for b in blocks if b.get("type") == "dropdown"]
assert len(dropdowns) == 1, "exactly one affected-script dropdown"
options = dropdowns[0]["attributes"]["options"]
for script in ("scaffold-init", "setup-labels", "setup-project",
               "setup-ruleset", "setup-sources"):
    assert script in options, f"dropdown must list {script}"
assert any("general" in o for o in options), \
    "dropdown needs a non-script escape hatch"
assert dropdowns[0].get("validations", {}).get("required") is True

textareas = [b for b in blocks if b.get("type") == "textarea"]
assert len(textareas) >= 2, "what-happened and what-expected textareas"
assert all(t.get("validations", {}).get("required") is True
           for t in textareas), "both textareas are required"

guidance = " ".join(b.get("attributes", {}).get("value", "")
                    for b in blocks if b.get("type") == "markdown")
for token in ("secrets", "tokens", "paste"):
    assert token in guidance, f"no-secrets guidance must mention '{token}'"

print("form OK")
PYEOF
expect_rc_grep 0 'form OK' "feedback.yml carries labels, enum dropdown, required fields, guidance" \
  python3 "$WORK/form.py" "$FORM"

# --- the labeling workflow --------------------------------------------------

cat > "$WORK/workflow.py" <<'PYEOF'
import re, sys, yaml

with open(sys.argv[1]) as fh:
    text = fh.read()
wf = yaml.safe_load(text)

# PyYAML parses a bare `on:` key as boolean True (YAML 1.1).
trigger = wf.get("on", wf.get(True))
assert set(trigger.keys()) == {"issues"}, "issues must be the only trigger"
assert trigger["issues"].get("types") == ["opened"], \
    "trigger must be exactly issues:opened"

assert wf.get("permissions") == {"issues": "write"}, \
    "top-level permissions must grant issues:write and nothing else"

assert "uses:" not in text, \
    "no uses: steps — nothing to pin, nothing checked out"
assert "actions/checkout" not in text, "the job must not check out code"

jobs = wf.get("jobs", {})
assert len(jobs) == 1, "a single classification job"
for job in jobs.values():
    assert "permissions" not in job, \
        "job-level permissions would widen or shadow the top-level grant"
    for step in job.get("steps", []):
        run = step.get("run", "")
        assert "${{" not in run, \
            "untrusted event fields must reach the script via env:, " \
            "never ${{ }} interpolation inside run:"

# The marker the workflow matches must be byte-identical to the one the
# helper writes into every report body — and the match must be anchored:
# the body must *start with* the marker, so issues that merely quote a
# report are not classified. The form path is keyed on the
# [adopter-feedback] title prefix (fresh copies: GitHub ignores unknown
# labels in form frontmatter, so the workflow must cover it).
with open(sys.argv[2]) as fh:
    lib = fh.read()
markers = set(re.findall(r"<!-- adopter-feedback:v\d+ -->", lib))
assert len(markers) == 1, "helper must define exactly one marker version"
marker = markers.pop()
assert f"'{marker}'*)" in text, \
    f"workflow must anchor-match the helper marker {marker!r} as a body prefix"
assert f"*'{marker}'" not in text, \
    "unanchored substring match would classify issues that quote a report"
assert re.search(r"ISSUE_TITLE:\s*\$\{\{ github\.event\.issue\.title \}\}", text), \
    "the untrusted title must be bound via env:"
assert "'[adopter-feedback]'*)" in text, \
    "form path: title-prefix match (form labels: is ignored on fresh copies)"

assert "from:adopter" in text, "workflow must apply the from:adopter label"

print("workflow OK")
PYEOF
expect_rc_grep 0 'workflow OK' "adopter-feedback.yml is least-privilege and matches the helper marker" \
  python3 "$WORK/workflow.py" "$WORKFLOW" "$LIB"

# --- the taxonomy entry -----------------------------------------------------

check_taxonomy() {
  grep -Eq '^create "from:adopter" +"[0-9A-Fa-f]{6}" "' "$LABELS_SH" || {
    echo "setup-labels.sh must create from:adopter with a color and description"
    return 1
  }
  count=$(grep -c '^create "' "$LABELS_SH")
  grep -q "Done. $count labels ensured." "$LABELS_SH" || {
    echo "final echo out of sync: $count create lines"
    return 1
  }
  grep -q "refresh the $count canonical scaffold labels" "$LABELS_SH" || {
    echo "usage text out of sync: $count create lines"
    return 1
  }
  echo "taxonomy OK"
}
expect_rc_grep 0 'taxonomy OK' "setup-labels.sh defines from:adopter and its counts are consistent" \
  check_taxonomy

t_summary
