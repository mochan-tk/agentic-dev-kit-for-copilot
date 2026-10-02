# `.github/docs/agreements/` — Reviewed Truth (Phase 2)

The distilled, human-approved knowledge every agent designs against.
Produced from `.github/docs/context/` by
`.github/skills/context-distillation/SKILL.md`; change control by
`.github/instructions/docs.instructions.md` (**PR + human approval only** —
merge is what makes something an agreement).

| File | Holds |
|---|---|
| `requirements.md` | Verifiable requirements, one `REQ-###` each |
| `non-goals.md` | Explicit "we will not" list |
| `glossary.md` | Project vocabulary |
| `adr/ADR-####-<slug>.md` | One architectural decision per record |
| `retro-log.md` | Ledger of system improvements (`retro:` PRs) |

Task issues cite these by ID (`REQ-###`, `ADR-####`) when a relevant
agreement exists — most tasks cite none, and the promotion bar in
`.github/skills/context-distillation/SKILL.md` ("When an agreement is
warranted") decides what belongs here at all. If work reveals an agreement
is wrong, follow `.github/instructions/docs.instructions.md` ("Changing an
agreement"): substantive changes get a dedicated agreements PR; declared
wording riders may ride the implementation PR.

> Template-repository note: kit history stays at its source paths: root
> `docs/agreements/adr/`, kit ADR-0004 in the [kit ADR directory](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/tree/main/.github/docs/agreements/adr),
> and populated kit `retro-log.md`. None is installed as adopter truth.
> This tier receives only its README, ADR-0000 template and empty bootstrap
> ledgers; this tree in your project holds *your* agreements, and your ADR
> numbering starts fresh at `ADR-0001`. Root `docs/` is not a required destination.
