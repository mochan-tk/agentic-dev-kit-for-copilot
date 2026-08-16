# ADR-0004: Separate governance sensors from adopter and platform actuators

- **Status:** accepted
- **Date:** 2026-08-16
- **Supersedes:** none

## Context

The external [Human-on-the-Loop review](../../context/hotl-review/review.md)
found that this kit gives a supervising human strong procedural control but
weak operational observability. Some requested controls require authenticated
runtime state: immutable session roles, structured events, heartbeats, budgets,
pause/resume, and a supervision console. This kit is plain repository files,
and its sessions share one GitHub identity, so it cannot implement those
controls truthfully.

Other gaps are observable through repository files and GitHub APIs: effective
branch governance, ownership overlap before parallel dispatch, required-check
source binding, and controls that engine upgrades define but tuned adopter
files do not receive. The [feasibility record](../../context/hotl-review/feasibility.md)
verified those observation paths and identified where the result must remain
unknown or uncheckable.

Reversing the boundary later would alter the kit's security claims, upgrade
contract, and adoption model. The boundary therefore warrants an ADR.

## Decision

The kit will expose repository governance through non-mutating sensors and
will leave enforcement to explicit adopter actions or authoritative platform
capabilities.

1. **Sensors expose and never mutate.** Governance, ownership, and upgrade-drift
   sensors report facts and distinct exit states. They do not change rulesets,
   issue dependencies, workflows, or tuned files. An existing command such as
   `setup-ruleset` is an actuator only when an adopter invokes it explicitly.
   This follows the
   [corrected sensor boundary](../../context/hotl-review/feasibility.md#additional-corrected-boundaries-from-independent-review).
2. **Governance sensors aggregate effective state.** They read all active rules
   applying to the default branch, including parent rulesets, and fetch active
   ruleset details needed to report bypass actors. API or authorization failure
   is `unknown`, never safe or inactive. This follows
   [correction 1](../../context/hotl-review/feasibility.md#1-aggregate-effective-state)
   and [Spike S2](../../context/hotl-review/feasibility.md#spike-s2-actions-workflow-permissions).
3. **Ownership evaluation fails closed.** Dispatchable Tasks use a declared
   `##` or `### File ownership` grammar with one plain or code-span path per
   bullet. A Task outside that grammar is `UNCHECKABLE` with a distinct exit
   state. Literal-prefix overlap remains a documented conservative
   approximation, and shared changelog ownership is not suppressed. This
   follows [correction 3](../../context/hotl-review/feasibility.md#3-fail-closed-on-uncheckable-ownership)
   and [correction 4](../../context/hotl-review/feasibility.md#4-preserve-the-changelog-collision).
4. **Ruleset intent is profile-relative.** The actuator offers a byte-compatible
   `solo` default and an opt-in `team` profile, and persists the declared
   profile so sensors compare effective state with intent. Team intent includes
   stale-review dismissal, latest-push approval, code-owner review, thread
   resolution, and strict required checks. Bypass actors always qualify the
   reported state. This follows the
   [S1 observations](../../context/hotl-review/feasibility.md#observed-results)
   and the corrected profile boundary in the feasibility record.
5. **Team checks are source-bound and observed.** Before applying team intent,
   the actuator proves that every requested required-check context exists and
   derives a common issuing GitHub App ID from current check runs. Discovery
   failure blocks the action rather than installing an unbound or permanently
   pending rule. This follows
   [correction 2](../../context/hotl-review/feasibility.md#2-bind-required-checks-to-their-source).
6. **Control definitions travel as engine-class data.** Upgrades refresh
   anchored control definitions and remediation pointers without overwriting
   tuned adopter files. Sensors expose missing controls; adopters may apply
   them, keep a reasoned waiver, or opt into strict evaluation. Template CI
   verifies the definitions against the template itself. This follows
   [correction 5](../../context/hotl-review/feasibility.md#5-anchor-control-signatures)
   and the [drift spike](../../context/hotl-review/feasibility.md#spike-d-governance-drift-manifest).
7. **Runtime enforcement remains an explicit non-goal.** The kit will not
   imitate authenticated event state, immutable roles, heartbeat, budget,
   circuit-breaker, pause/resume, or console capabilities in prose or local
   files. Those controls require the Copilot platform or a future GitHub App.
   The existing
   [#6 hardening trigger](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6#issuecomment-5305170668)
   makes them prerequisites before external contributors, delegation licenses,
   or auto-merge are enabled, whichever occurs first.

## Consequences

- A supervisor can distinguish installation and tuning from effective
  governance without granting sensors mutation authority.
- Unknown and uncheckable results remain visible and non-successful. Adopters
  cannot mistake missing evidence for a safe state.
- Solo repositories keep their current viable behavior. Team hardening is
  explicit, reversible, and judged against declared intent.
- Bypass actors and check issuers become part of a governance claim rather than
  hidden implementation detail.
- Engine upgrades can deliver new control definitions while preserving adopter
  ownership of tuned files. Anchored signatures, remediation pointers, and
  reasoned waivers add maintenance work.
- Literal-prefix ownership checks can produce conservative false positives and
  cannot solve arbitrary glob intersection. The safer failure is
  serialization, not an unproven parallel dispatch.
- Merge queue is not applicable to personal repositories. Supporting it for an
  eligible organization repository also requires `merge_group` CI coverage.
- No service, secret, daemon, SDK, runtime event store, or additional language
  dependency follows from this decision.
- The ADR proposes a boundary only. Later Tasks must implement and test each
  sensor or actuator change independently.

## References

- [Collected HOTL review](../../context/hotl-review/INDEX.md)
- [Feasibility evidence](../../context/hotl-review/feasibility.md)
- [Task #72](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/72)
- [Approved plan](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/72#issuecomment-5306433328)
- [Issue #6 hardening trigger](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6#issuecomment-5305170668)
