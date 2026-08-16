---
source: GitHub Issue #75, official GitHub documentation, and local client probes
retrieved: 2026-08-16
method: web-research
collector: Task #75 successor session d8976485-9e0e-40f3-a79a-8899b0a07923
sensitivity: public
status: raw
---

# Agent Plugins distribution spike

## Decision

**No-go for replacing repository-local execution assets before v1.0.0.**
Proceed only with an opt-in CLI pilot. The installed client loaded the
prototype after an explicit marketplace registration and install, but did not
activate it from repository settings. Repository-only activation,
deactivation, and automatic update therefore remain unproven.

Keep `scaffold-init` as the sole installer for durable repository governance.
Do not publish a public marketplace before v1.0.0. A private or disposable
marketplace is useful for continued client probes.

## Sources

- Task brief and plan:
  <https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/75>
- Plugin overview:
  <https://docs.github.com/en/copilot/concepts/agents/about-plugins>
- CLI plugin and marketplace reference:
  <https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference>
- CLI settings and precedence:
  <https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference>
- Installation guide:
  <https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing>

The official overview says CLI and cloud agent can consume `enabledPlugins`
and `extraKnownMarketplaces` from `.github/copilot/settings.json`. The local
CLI observation below did not reproduce that behavior. Treat this as an open
client/configuration contradiction, not evidence that the documentation is
wrong.

## Prototype identities

| Artifact | Commit / pin | Purpose |
|---|---|---|
| SHA A plugin content | `06948d66f8ad6b6b780a08a83d4a0c2b074ffd67` | `v1` identity markers |
| SHA A marketplace | `de5006407cd74e70016c14e8982dbf719fdda250` | pins both plugins to SHA A |
| SHA B plugin content | `4fb3007ffac5fdb0a670ab810ee7c8cdd3cbebfd` | `v2` markers with manifest version still `0.0.1` |
| SHA B marketplace | `1ff4fe1746e50b2188392360e133283d8ecd2569` | pins both plugins to SHA B |

`portable-core/` uses the Agent Plugins v1 schema and contains two skills,
including script and reference resources. `github-compat/` uses the current
Copilot compatibility manifest and contains the same two skills, one custom
agent, and one command.

Keeping plugin metadata at `0.0.1` across A and B isolates content-SHA update
behavior from manifest-version behavior.

## Client support matrix

| Surface | Version / availability | Discovery | Invocation | Update / rollback | Result |
|---|---|---|---|---|---|
| Copilot CLI | `1.0.81-0` | imperative install verified; repository declaration not reproduced | skills and namespaced agent verified; command file discovered but slash invocation not verified | explicit A -> B -> A verified | partial |
| Copilot app | local probe session created twice (initial kickoff plus immediate steering) | probe produced no turn or durable report | not exercised | not exercised | unverified; zero-turn probe failure |
| VS Code | `1.129.1` installed | not exercised in Copilot Chat UI | not exercised | not exercised | unverified |
| Cloud agent | `gh agent-task` preview available | not exercised; no dedicated GitHub spike repository carried the owned settings | not exercised | not exercised | unverified |

No surface is counted as successful merely because documentation names it.

## CLI observations

### Repository declaration

The isolated Git repository declared both plugins in
`.github/copilot/settings.json`. Two marketplace source forms were tried:

1. GitHub source pinned to marketplace commit
   `de5006407cd74e70016c14e8982dbf719fdda250`, with the nested marketplace
   path.
2. A local directory snapshot whose directory name contained that exact
   marketplace SHA.

`copilot -p` loaded the repository-local duplicate skill but did not install
or discover either declared plugin. `copilot plugin list` remained unchanged,
and no settings warning was emitted in the captured session events.

Because the marketplace lives under the Task-owned
`spikes/agent-plugin/**` path, the spike did not add a repository-root
`.github/plugin/marketplace.json` outside File ownership merely to make the
probe pass.

### Explicit install

The following explicit flow succeeded against the SHA A marketplace snapshot:

```text
copilot plugin marketplace add <sha-a-marketplace-directory>
copilot plugin install agentic-dev-portable-spike@agentic-dev-spike
copilot plugin install agentic-dev-github-spike@agentic-dev-spike
```

The CLI reported two installed skills for each package. Installed files were
materialized under:

```text
~/.copilot/installed-plugins/agentic-dev-spike/
```

The custom agent was addressable only by its namespaced ID:
`agentic-dev-github-spike:spike-auditor`.

### Precedence

The isolated repository first contained a local `spike-plan` skill with the
distinct marker:

```text
LOCAL_SKILL_OK: spike-repo/v1
```

With both plugins installed, invoking bare `spike-plan` returned that local
marker. After moving the local skill outside the discovery path, the same
invocation returned:

```text
PORTABLE_SKILL_OK: agentic-dev-portable-spike/v1
```

The portable plugin had been installed before the compatibility plugin, so it
won the duplicate bare skill name. Explicitly invoking the namespaced
compatibility skill returned its own `GITHUB_SKILL_OK` marker. Migration must
therefore remove or rename local skills one at a time before plugin behavior
can be proven. Namespaced plugin agents can coexist with local agent IDs and
must not be generalized from skill precedence.

### Update and rollback

After refreshing the marketplace catalog and running explicit plugin updates,
both packages changed from SHA A markers to SHA B markers even though their
manifest versions remained `0.0.1`. The CLI printed `already at latest` for
the version while also reporting that two skills were updated, and the
installed files contained only `v2` markers.

Restoring the SHA A marketplace catalog, refreshing it, and running the same
explicit updates restored all `v1` markers. This proves explicit content-SHA
update and rollback for the CLI.

Automatic update was not proven. Official documentation states that custom
marketplace auto-update requires a user or managed `autoUpdate: true` entry;
a repository-level opt-in is accepted and ignored. That constraint prevents
the repository alone from guaranteeing automatic updates.

### Repository-only scope and deactivation

The explicitly installed plugin was also callable from a separate empty Git
repository, returning the portable SHA A marker. Imperative installation is
therefore user-scoped, not repository-only.

Repository-only activation/deactivation was not proven because declarative
activation did not load the plugin. Explicit uninstall removed the skills and
agent from both the isolated repository and the separate empty repository,
but that is user-level deactivation and does not satisfy the repository-only
claim.

## Copilot app probe

A dedicated local Copilot app project/session was created from the isolated
repository after SHA A installation. The initial kickoff and one immediate
steering message both requested only marker discovery and prohibited edits.
The probe produced no turn, process, or report. This is a zero-turn probe
failure, not evidence that app plugin loading succeeds or fails. The app
surface remains unverified.

### Command

The compatibility command file was installed with the expected
`GITHUB_COMMAND_OK` marker. Non-interactive `copilot -p` treated the slash
text as a normal prompt and selected a similarly named skill instead.
Automated TTY invocation did not produce a stable command result. Record the
command as packaged and discovered, but not invoked.

## Governance boundary

Plugin installation left the isolated repository worktree clean and created
none of these durable governance surfaces:

- `AGENTS.md` or Copilot instructions/settings beyond the hand-authored probe;
- workflows, CODEOWNERS, issue or pull-request templates;
- agreements or context documents;
- labels, Projects, rulesets, or lineage.

`bash .github/scripts/tests/run-tests.sh scaffold-init` passed all 68 cases.
Those tests continue to prove that `scaffold-init` installs and upgrades the
durable repository set without committing on the adopter's behalf.

## Component boundary

| Plugin candidate | Remains with `scaffold-init` |
|---|---|
| opt-in skills once each client proves invocation | `AGENTS.md` |
| namespaced custom agents on clients that load them | Copilot instructions and repository settings |
| commands/prompts only after interactive invocation is verified | workflows and CODEOWNERS |
| hooks, MCP, or LSP only through separate capability spikes | issue and PR templates |
| no repository mutation during install | agreements, context scaffolding, labels, Projects, rulesets, and lineage |

## Migration order

1. Keep every production repository-local asset in place.
2. Publish only a private, SHA-pinned pilot marketplace.
3. Verify declarative activation and exact identity on each target client.
4. For one skill at a time, observe the local marker, remove or rename the
   local copy, and observe the plugin marker.
5. Verify namespaced agents and interactive commands separately.
6. Verify repository-only deactivation and automatic or explicit update
   behavior on every supported surface.
7. Only then change `scaffold-init` ownership classes and remove migrated
   execution assets.

An additive opt-in plugin setting would be a non-breaking installer
enhancement. Removing repository-local agents, skills, or prompts is a
breaking upgrade because unsupported clients would lose functionality and
local precedence currently masks plugin failures.

## Rollback

1. Re-pin the marketplace/plugin content to the last known-good full SHA.
2. Refresh the marketplace and run an explicit plugin update on clients that
   do not prove automatic update.
3. Restore repository-local execution assets before disabling the plugin.
4. Run `scaffold-init --upgrade` only for files it already owns; do not make
   plugin rollback mutate governance.

The CLI probe demonstrated steps 1 and 2 from SHA B back to SHA A. Production
rollback remains trivial because this spike removes no production files.

## Open questions

- Why did CLI `1.0.81-0` not act on repository `enabledPlugins` and
  `extraKnownMarketplaces` despite the official documentation?
- Can the Copilot app and VS Code invoke the compatibility command and
  namespaced agent from the same package?
- Does cloud agent resolve a SHA-pinned custom marketplace without additional
  organization policy?
- Can a repository-scoped declaration disable a previously user-installed
  plugin without changing user settings?
