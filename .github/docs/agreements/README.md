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

> Template-repository note: the scaffold's **own** ADRs (`ADR-0001` and up)
> live in the template repository at root `docs/agreements/adr/` and are
> never installed. This tree in your project holds *your* agreements only;
> your numbering starts fresh at `ADR-0001`.
