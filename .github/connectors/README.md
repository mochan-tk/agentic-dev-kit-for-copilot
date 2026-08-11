# Context connectors

Connectors make Phase 1–2 of the lifecycle (context collection and
distillation) a **pluggable layer**. A connector is a swappable
implementation of "get this project's requirements and decisions into a
usable state": teams that already run a spec tool plug in its connector;
teams with nothing yet use the builtin one. Phase 3–5 (plan → execute →
verify) never change — they consume only what the Context Contract below
guarantees. Decision record: ADR-0001 (pluggable context connectors),
kept in the scaffold repository at
`docs/agreements/adr/ADR-0001-pluggable-context-connectors.md` — a
development record that is not installed into adopter projects.

## The Context Contract (normative)

A project satisfies the Context Contract when all four conditions hold:

1. **Verifiable requirements with stable IDs.** Requirement-shaped
   statements exist, each individually checkable and carrying an
   identifier that survives edits (`REQ-###` for the builtin connector;
   the source tool's own requirement keys otherwise). "Verifiable" means
   a reviewer can decide pass/fail without interviewing the author.
2. **Immutable decisions.** Design choices that constrain future work are
   recorded append-only (ADRs or the source tool's equivalent), so a
   later session can distinguish "decided" from "assumed".
3. **Reachable from every execution surface.** All content is accessible
   from any surface a task may run on (`exec:cloud`, `exec:app`,
   `exec:cli`, `exec:ide`) — in practice: in the repository, or pinned
   into it. A source only one surface can reach fails the Contract.
4. **Stably referenceable from Task issues.** A Task issue can cite the
   material with a reference that will not silently change meaning — a
   path plus pin (commit SHA) for in-repo sources, an immutable ID
   otherwise.

### The sufficiency test

Contract satisfaction is judged behaviorally, by the
**Epic-decomposition test**:

> The next Epic can be decomposed into Task issues, and every Task's
> acceptance criteria can be written in verifiable form, without going
> back to the humans for missing fundamentals.

Run it by attempting the decomposition and noting where it stalls. The
evidence belongs in the activation or agreements PR (see below).

The Contract is the *only* interface between connectors and the rest of
the scaffold. Nothing in Phase 3–5 may depend on connector specifics.

## Connector model

A connector definition is a markdown procedure (plus optional MCP
configuration where a tool needs it) that an agent can execute. Every
definition specifies four operations:

| Operation | Meaning |
|---|---|
| `discover` | Detect whether this source applies to the repository and what it contains. |
| `retrieve` | Land source material into `.github/docs/context/` (or reference it in place when it already lives in-repo) with provenance. |
| `pin` | Fix the exact source revision the plan will be built against, recorded durably. |
| `verify` | Check the pinned source still matches reality (drift detection); on mismatch, escalate with `needs:replan`. |

And five metadata fields:

| Field | Meaning |
|---|---|
| `name` | Connector identifier, matches the filename. |
| `access` | How the source is reached (conversation, in-repo files, external API…). |
| `reach` | What the source can see (repository, tenant data…). |
| `trust-default` | How much retrieved content can be trusted before re-verification. |
| `status` | One of `core`, `community`, `experimental`. |

### Definition format (machine-checked)

Every file in this directory except `README.md` and
`CONNECTOR-TEMPLATE.md` is a connector definition and must contain:

- a `## Metadata` section with one bullet per field, exactly
  `- name:`, `- access:`, `- reach:`, `- trust-default:`, `- status:`,
  with `status` set to `core`, `community`, or `experimental`;
- the four operation sections as exact-name level-2 headings:
  `## discover`, `## retrieve`, `## pin`, `## verify`.

A conformance script (`.github/scripts/check-connectors.sh`, a CI wall)
validates this structure on every push.

## Activation

Connector *definitions* (this directory) ship with the scaffold;
*activation* is per-project. A project enables a connector by recording
it in a SOURCES.md registry (a machine-written file under
`.github/docs/context/`) listing the enabled connectors and their pins.
The registry is written by the `setup-sources.sh` wizard
(`.github/scripts/`) or by hand in an **activation PR** — a PR
whose merge is the durable decision "this source, at this revision, is
our requirements source", carrying the sufficiency-test evidence in its
body. Chat approval is never the gate; the PR review is.

## Contributing a connector

1. Copy `CONNECTOR-TEMPLATE.md` to `<name>.md` in this directory and
   fill every section; keep the format rules above (the conformance
   wall enforces them).
2. Start with `status: experimental`. Promotion is by PR review:
   `experimental` → `community` when a real project has activated it and
   linked evidence; `community` → `core` when the maintainers adopt it
   into the default support matrix.
3. English only, like every scaffold-owned file (AGENTS.md §8). Keep the
   procedure executable by an agent with no context beyond the file, the
   Contract, and the repository.
