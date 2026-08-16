# Agent Plugin distribution spike

Temporary prototype for Task #75. It compares:

- `portable-core/`: Agent Plugins v1 portable schema with skills and bundled
  resources only.
- `github-compat/`: current Copilot compatibility manifest with skills, one
  custom agent, and one command.

Nothing under this directory is production distribution. The spike must prove
client behavior, repository scoping, precedence, update, rollback, and the
installer boundary before any repository-local execution asset is removed.
