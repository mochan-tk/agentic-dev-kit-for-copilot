---
source: https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/120
retrieved: 2026-09-15
method: ai-summary
collector: Task-120-worker
sensitivity: public
status: raw
---

# Frontier reproduction

**Acceptance correction:** the original worker fixtures augmented nodes with
`repository.nameWithOwner`, absent from the actual CLI export. Historical
red/green executions below remain observations, not proof of nonempty CLI
compatibility. The [supervisor correction](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/120#issuecomment-5673252007)
supersedes the prior accepted Outcome and audit. See the rework section.

Epic #119 reports independent offline reproduction against baseline
`fd265ddef150fab86cd54d0e383c2c25fe297ffb`, frontier blob
`af0905cb90626001c50c2937d35ba7ea5f9d077c`: shared blockers returned 50 rows
with 151 gh calls; dependency-read failure returned one incorrectly ready
row with exit 0 / 3 calls; list failure returned false no-work success with
exit 0 / 1 call. These are ledger-reported observations, not worker runs.

## Worker-observed red phase

Before production edits, `/bin/bash .github/scripts/tests/test-frontier.sh`
ran with `BASH=/bin/bash`, `BASH_VERSION=3.2.57(1)-release`; every frontier
child used that executable. Production still matched the baseline blob.
The suite exited 1: 86 assertions, 69 failed (including strict mock
rejections of baseline misrouted reads). The augmented nodes/count fixture
returned the exact 50 rows, exit 0, 151 total calls, and 50 state reads for
each of blockers 1001 and 1002. Both dependency reads failing returned exit
0 / 3 calls and an incorrectly ready Task. List failure returned exit 0 /
1 call and `No open Task issues labeled ai:ready.`.

The new tests were committed before the production fix. The final PR
records subsequent strengthened fixtures and green verification separately.
The fixture contract is executable without attachments. Counts describe gh
invocations, not HTTP requests, elapsed time, or measured savings.

## Historical worker-observed green phase (augmented fixtures)

The focused harness and direct `/bin/bash` suite each passed 94 assertions.
The direct run identified Bash `3.2.57(1)-release` and used that executable
for all frontier children. The identical 50-row fixture now uses 53 total
calls, with one state read per unique blocker. List/dependency/state errors
exit nonzero without any stdout. Additional cases cover nodes/count
completeness, repository identity, legacy metadata, and invocation freshness.
The PR records full-suite and final-head CI evidence; these local observations
do not imply authenticated scheduling or enforcement.

## Worker-observed exporter-faithful red phase

With production unchanged at `b9d59394885aff29e18c3843e6c7966389dc1534`,
the revised source-derived suite ran directly under `/bin/bash`,
`BASH_VERSION=3.2.57(1)-release`, with all children using that executable:
146 assertions, 20 failed, suite exit 1. Same/cross-repository nonempty
exported nodes without `repository` failed dependency parsing. The 50-Task
fixture returned exit 1, zero rows, two total gh calls, and zero state reads
for each of 1001/1002. The fixture's exact exported keys are asserted.

These are fresh worker observations, not execution of the supplied archive.
They establish the compatibility regression that augmented mocks missed.
URL-negative tests retain fail-closed assertions; state reads must remain
independent of exported node state. This red evidence precedes parser repair.
