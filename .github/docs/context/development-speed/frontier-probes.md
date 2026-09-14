---
source: https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/120
retrieved: 2026-09-15
method: ai-summary
collector: Task-120-worker
sensitivity: public
status: raw
---

# Frontier reproduction

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
rejections of baseline misrouted reads). The supported nodes/count fixture
returned the exact 50 rows, exit 0, 151 total calls, and 50 state reads for
each of blockers 1001 and 1002. Both dependency reads failing returned exit
0 / 3 calls and an incorrectly ready Task. List failure returned exit 0 /
1 call and `No open Task issues labeled ai:ready.`.

The new tests were committed before the production fix. The final PR
records subsequent strengthened fixtures and green verification separately.
The fixture contract is executable without attachments. Counts describe gh
invocations, not HTTP requests, elapsed time, or measured savings.

## Worker-observed green phase

The focused harness and direct `/bin/bash` suite each passed 94 assertions.
The direct run identified Bash `3.2.57(1)-release` and used that executable
for all frontier children. The identical 50-row fixture now uses 53 total
calls, with one state read per unique blocker. List/dependency/state errors
exit nonzero without any stdout. Additional cases cover nodes/count
completeness, repository identity, legacy metadata, and invocation freshness.
The PR records full-suite and final-head CI evidence; these local observations
do not imply authenticated scheduling or enforcement.
