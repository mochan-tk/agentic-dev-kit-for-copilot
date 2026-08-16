---
name: spike-plan
description: "Plugin spike skill. Use only when asked to report the portable plugin identity and read its bundled resource."
---

# Portable plugin spike plan

When explicitly invoked:

1. Read `./references/identity.txt`.
2. Return exactly `PORTABLE_SKILL_OK: <contents>`.
3. Do not modify files or invoke network tools.
