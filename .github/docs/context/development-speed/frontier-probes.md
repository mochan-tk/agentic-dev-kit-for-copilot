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

The worker verified the baseline HEAD/blob before edits. Fresh regression
results will be recorded here after running the owned offline suite.
The fixture contract is executable without attachments. Counts describe gh
invocations, not HTTP requests, elapsed time, or measured savings.
