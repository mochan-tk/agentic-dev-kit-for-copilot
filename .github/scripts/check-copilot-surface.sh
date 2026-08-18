#!/usr/bin/env bash
# Validate the Copilot execution-plane surface.
#
# Deterministic wall, no auto-fixing:
#   1. Skills:        .github/skills/*/SKILL.md frontmatter has exactly
#                     name + description; name matches the directory.
#   2. Agents:        .github/agents/*.agent.md has name + description.
#   3. Prompts:       .github/prompts/*.prompt.md has description.
#   4. Instructions:  .github/instructions/*.instructions.md has applyTo.
#   5. Ceilings:      SKILL.md <= 500 lines, AGENTS.md <= 200 lines.
#   6. English-only:  alphabetic characters in scaffold-owned text files
#                     (AGENTS.md, SCAFFOLD-CHANGELOG.md, .github/**) are
#                     Latin script; app-owned files are out of scope.
#   7. Agent tools:   delegated to check-agent-tools.sh — the orchestrator's
#                     allowlist must still grant what the protocol uses.
#
# Frontmatter is parsed with PyYAML (yaml.safe_load semantics plus a
# duplicate-key rejection); malformed YAML fails the wall with file:line.
#
# Exit 0 when the surface is clean, 1 on any violation, 2 on missing tools
# (python3 or PyYAML).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

command -v python3 >/dev/null 2>&1 || {
  echo "check-copilot-surface: ERROR — python3 is required" >&2
  exit 2
}

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import pathlib
import subprocess
import sys
import unicodedata

try:
    import yaml
except ImportError:
    print(
        "check-copilot-surface: ERROR — PyYAML is required "
        "(python3 -c 'import yaml' must succeed)",
        file=sys.stderr,
    )
    raise SystemExit(2)

root = pathlib.Path(sys.argv[1]).resolve()
errors: list[str] = []


class StrictFrontmatterLoader(yaml.SafeLoader):
    """SafeLoader that rejects duplicate mapping keys (PyYAML keeps the last
    one silently, which would let a shadowed key slip past the wall)."""

    def construct_mapping(self, node, deep=False):
        seen = []
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=True)
            if key in seen:
                raise yaml.constructor.ConstructorError(
                    None,
                    None,
                    f"duplicate frontmatter key {key!r}",
                    key_node.start_mark,
                )
            seen.append(key)
        return super().construct_mapping(node, deep)


tracked = [
    item
    for item in subprocess.run(
        ["git", "ls-files", "-z"], check=True, stdout=subprocess.PIPE
    ).stdout.decode("utf-8").split("\0")
    if item
]
tracked_set = set(tracked)


def parse_frontmatter(path: pathlib.Path) -> dict | None:
    """Return the frontmatter parsed as a YAML mapping, or None on error.

    The block between the --- fences is handed to PyYAML (SafeLoader plus
    duplicate-key rejection); any parse failure is a violation with the
    parser's line number translated to a file line. The document must be a
    mapping — anything else is a violation.
    """
    relative = path.relative_to(root)
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        errors.append(f"{relative}:1: frontmatter must open with --- on line 1")
        return None
    closing = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            closing = index
            break
    if closing is None:
        errors.append(f"{relative}: frontmatter closing --- is missing")
        return None
    block = "\n".join(lines[1:closing])
    try:
        document = yaml.load(block, Loader=StrictFrontmatterLoader)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None) or getattr(exc, "context_mark", None)
        location = f"{relative}:{mark.line + 2}" if mark is not None else f"{relative}"
        problem = getattr(exc, "problem", None) or str(exc).replace("\n", " ")
        errors.append(f"{location}: frontmatter is not valid YAML ({problem})")
        return None
    if not isinstance(document, dict):
        errors.append(f"{relative}: frontmatter must be a YAML mapping")
        return None
    return document


def require(values: dict, path: pathlib.Path, key: str) -> None:
    relative = path.relative_to(root)
    if key not in values:
        errors.append(f"{relative}: frontmatter is missing {key!r}")
    elif not isinstance(values[key], str) or not values[key].strip():
        errors.append(f"{relative}: frontmatter {key!r} must be a non-empty string")


# 1. Skills: exactly name + description, name matches the directory.
skills_root = root / ".github/skills"
skill_dirs = sorted(p for p in skills_root.iterdir() if p.is_dir()) if skills_root.is_dir() else []
if not skill_dirs:
    errors.append(".github/skills: no skill directories found")
for directory in skill_dirs:
    skill_path = directory / "SKILL.md"
    relative = skill_path.relative_to(root)
    if not skill_path.is_file():
        errors.append(f"{relative}: missing")
        continue
    values = parse_frontmatter(skill_path)
    if values is None:
        continue
    if sorted(str(key) for key in values) != ["description", "name"]:
        errors.append(
            f"{relative}: frontmatter keys must be exactly name, description "
            f"(found: {', '.join(sorted(str(key) for key in values)) or 'none'})"
        )
    require(values, skill_path, "name")
    require(values, skill_path, "description")
    name_value = values.get("name")
    if isinstance(name_value, str) and name_value and name_value != directory.name:
        errors.append(f"{relative}: name must equal {directory.name!r}")

# 2-4. Agents, prompts, instructions: required keys (extra keys allowed).
surface_specs = [
    (".github/agents", "*.agent.md", ("name", "description")),
    (".github/prompts", "*.prompt.md", ("description",)),
    (".github/instructions", "*.instructions.md", ("applyTo",)),
]
for base, pattern, keys in surface_specs:
    base_path = root / base
    files = sorted(base_path.glob(pattern)) if base_path.is_dir() else []
    if not files:
        errors.append(f"{base}: no {pattern} files found")
    for path in files:
        values = parse_frontmatter(path)
        if values is None:
            continue
        for key in keys:
            require(values, path, key)

# 5. Size ceilings (progressive disclosure).
for directory in skill_dirs:
    skill_path = directory / "SKILL.md"
    if skill_path.is_file():
        count = len(skill_path.read_text(encoding="utf-8").splitlines())
        if count > 500:
            errors.append(
                f"{skill_path.relative_to(root)}: {count} lines exceeds the 500-line ceiling"
            )
agents_md = root / "AGENTS.md"
if not agents_md.is_file():
    errors.append("AGENTS.md: missing")
else:
    count = len(agents_md.read_text(encoding="utf-8").splitlines())
    if count > 200:
        errors.append(f"AGENTS.md: {count} lines exceeds the 200-line ceiling")

# 6. English-only: alphabetic characters in scaffold-owned text files must be
#    Latin script. Scope: AGENTS.md, SCAFFOLD-CHANGELOG.md, and everything
#    under .github/. App-owned files (any other path) follow the project's
#    own language policy and are never scanned.
SCAFFOLD_OWNED = ("AGENTS.md", "SCAFFOLD-CHANGELOG.md")
scanned_english = 0
for item in tracked:
    if item not in SCAFFOLD_OWNED and not item.startswith(".github/"):
        continue
    scanned_english += 1
    raw = (root / item).read_bytes()
    if b"\0" in raw:
        continue
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        errors.append(f"{item}: tracked text is not valid UTF-8")
        continue
    for number, line in enumerate(text.splitlines(), start=1):
        for character in line:
            if not character.isalpha():
                continue
            if "LATIN" not in unicodedata.name(character, ""):
                errors.append(
                    f"{item}:{number}: non-Latin alphabetic character "
                    f"{character!r} — persistent content must be English-only"
                )
                break

if errors:
    print(f"check-copilot-surface: FAIL — {len(errors)} violation(s)", file=sys.stderr)
    for error in errors:
        print(f"  {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "check-copilot-surface: OK — "
    f"{len(skill_dirs)} skills, agents/prompts/instructions frontmatter, "
    "size ceilings validated; English-only rule scanned "
    f"{scanned_english} scaffold-owned file(s) "
    f"(of {len(tracked_set)} tracked)."
)
PY

# The frontmatter above is validated as YAML; whether the tools it grants
# match the protocol the agent is told to run is a separate question, and
# one nothing asked until an adopter's Project session could not create a
# session (#47). Delegated so the check stays testable on its own inputs.
bash "$ROOT/.github/scripts/check-agent-tools.sh"
