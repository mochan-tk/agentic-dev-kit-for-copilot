---
source: originating HOTL design, review, prototype artifacts, and spike session
retrieved: 2026-08-16
method: ai-summary
collector: Task #72 worker session
sensitivity: public
status: raw
---

# HOTL governance sensor feasibility

## Scope and evidence calibration

This note preserves the feasibility work performed before Task #72. It
summarizes the originating `hotl-response-design.md`, the corrected standalone
`adr-0004-hotl-governance-sensors-draft.md`, and these executable artifacts:

- `ownership_overlap_prototype.py`
- `ownership_overlap_bash_prototype.sh`
- `governance_status_prototype.sh`
- `governance-controls-prototype.tsv`
- `governance_drift_prototype.sh`

The observations below are verified only to the extent stated. The prototype
files are evidence, not supported product code. Commands are recorded in
reproducible form with sensitive values omitted.

## Platform documentation consulted

- [REST API endpoints for repository rules](https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28)
  documents that `GET /repos/{owner}/{repo}/rules/branches/{branch}` returns
  every active rule applying to a branch, including organization-level rules.
- [REST API endpoints for GitHub Actions permissions](https://docs.github.com/en/rest/actions/permissions?apiVersion=2022-11-28)
  documents repository workflow-permission endpoints and their token
  requirements. Reading repository workflow permissions requires Actions read
  access.
- [REST API endpoints for check runs](https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28)
  documents check-run retrieval and the GitHub App association exposed on check
  runs.
- [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
  documents availability constraints and requires GitHub Actions workflows to
  handle the `merge_group` event before required checks can support a queue.
- [REST API endpoints for organization rules](https://docs.github.com/en/rest/orgs/rules?apiVersion=2022-11-28)
  documents organization-level rulesets and bypass actors.

The live documentation examples used API version `2026-03-10` when retrieved.

## Spike S1: effective governance and team payload

### Method and commands

The spike read repository metadata, effective default-branch rules, repository
rulesets and their details, and current check runs:

```bash
gh api repos/mochan-tk/agentic-dev-kit-for-copilot
gh api repos/mochan-tk/agentic-dev-kit-for-copilot/rules/branches/main
gh api repos/mochan-tk/agentic-dev-kit-for-copilot/rulesets
gh api repos/mochan-tk/agentic-dev-kit-for-copilot/rulesets/<ruleset-id>
gh api repos/mochan-tk/agentic-dev-kit-for-copilot/commits/main/check-runs
```

Because GitHub exposes no validation-only endpoint for a repository ruleset,
the payload probe used `POST /repos/{owner}/{repo}/rulesets` with
`enforcement=disabled` and a nonexistent branch target, inspected the returned
payload, then used `DELETE /repos/{owner}/{repo}/rulesets/{ruleset-id}`. This
was a reversible mutation, not read-only validation. Two such probes were
deleted immediately, and the spike verified that no probe ruleset remained.

### Observed results

- The effective-rules endpoint returned controls from all active rulesets that
  applied to `main`; a named repository ruleset alone was therefore not a
  complete source of truth.
- The current repository had approving review, the expected required-check set,
  and read-only workflow token permissions active. Dismiss-stale review,
  latest-push approval, code-owner review, review-thread resolution, strict
  required checks, and required-check source binding were off.
- Active ruleset detail had to be read separately to qualify controls with
  bypass actors.
- Five observed GitHub Actions check runs were issued by GitHub App ID `15368`.
  The ID is an App ID, not an installation ID.
- A disabled team-profile payload containing stale-review dismissal,
  latest-push approval, code-owner review, thread resolution, strict status
  checks, and `integration_id: 15368` was accepted and returned by the live
  API, then deleted.
- The repository owner type was `User`; merge queue was therefore not
  applicable, not merely off.

### Verification boundary

The schema and disabled payload were verified. Active team enforcement was not
enabled. Named team reviewers were not tested and remain outside the proposed
profile. The live API probe did not establish that every future repository has
the same token scopes, check names, or App ID.

## Spike S2: Actions workflow permissions

### Method and command

```bash
gh api repos/mochan-tk/agentic-dev-kit-for-copilot/actions/permissions/workflow
```

### Observed result

The authenticated request returned:

```text
default_workflow_permissions=read
can_approve_pull_request_reviews=false
```

This proved readability with the spike identity. It does not prove readability
for every adopter token; an API or authorization failure must remain
`unknown`, distinct from an inactive control.

## Spikes S3 and S4: ownership parsing and overlap

### Method and commands

The originating session exported 36 real `type:task` issues to JSON and ran
both the Python analysis prototype and the Bash 3.2-oriented prototype:

```bash
python3 ownership_overlap_prototype.py issues.json
bash ownership_overlap_bash_prototype.sh issues.json <issue-number>...
```

The prototypes located a `## File ownership` section, extracted path bullets,
reduced glob-like paths to conservative literal prefixes, and compared every
pair. The first parser deliberately accepted only code-span bullets so that it
would not guess paths from prose.

### Observed results

```text
issues=36
parsed=11
unparseable=25
SCAFFOLD-CHANGELOG.md owners among parsed Tasks=9/11
```

The Bash prototype detected expected exact and broad-prefix intersections.
The low parse rate disproved the assumption that historical Task bodies were
uniform. The shared changelog result exposed a real single-writer constraint.

### Verification boundary

Literal-prefix comparison is conservative. It can over-report broad prefixes
and cannot prove that every pair of complex glob expressions is disjoint.
Malformed or legacy ownership cannot be treated as safe. The corrected grammar
accepts `##` or `### File ownership` and one plain or code-span path per bullet;
the producer-side Task ritual must validate that grammar before `ai:ready`.

## Spike D: governance drift manifest

### Method and commands

The prototype manifest named five known controls and the Bash prototype checked
their signatures against the current tree and a tree based on commit
`822fdda`, which predates the #51 Windows launcher control:

```bash
bash governance_drift_prototype.sh <current-tree> governance-controls-prototype.tsv
bash governance_drift_prototype.sh <822fdda-tree> governance-controls-prototype.tsv
```

### Observed results

- Current `main`: five of five prototype controls reported `ACTIVE`; exit 0.
- `822fdda` tree: only `ci-windows-launcher` reported `MISSING`; exit 1.

The prototype used fixed-string signatures. Independent review found that
production definitions must use line-anchored patterns so comments or unrelated
text cannot satisfy a control. Each definition also needs a remediation
pointer, and adopter-owned reasoned waivers are needed to prevent permanent,
non-actionable warnings.

## Six corrections to the initial design

### 1. Aggregate effective state

Governance status must read the effective rules for the default branch rather
than trust one named ruleset. It must also fetch active ruleset details for
bypass actors. This follows directly from S1 and the effective-rules API.

### 2. Bind required checks to their source

A team profile must bind every required context to the observed GitHub App ID
and prove that every requested context was observed. Discovery failure blocks
the profile rather than creating a permanently pending or unbound rule. S1
verified App ID `15368` only for the current checks.

### 3. Fail closed on uncheckable ownership

An `ai:ready` Task outside the declared ownership grammar is `UNCHECKABLE`, not
silently disjoint. S3 found 25 of 36 sampled Tasks unparseable. Independent
review reserved exit 2 for usage/environment errors and assigned
`UNCHECKABLE` a distinct exit 3.

### 4. Preserve the changelog collision

The detector must not allowlist `SCAFFOLD-CHANGELOG.md`. Its presence in 9 of
11 parseable Tasks is the process truth. Parallel work must serialize that
writer or move changelog composition into a separately designed integration
mechanism.

### 5. Anchor control signatures

Control definitions must match anchored implementation signatures, not
substrings. Template CI must prove every definition matches the template's own
files so detector drift fails upstream. The manifest must include remediation
and support reasoned adopter waivers.

### 6. Treat template CODEOWNERS as not applicable

The source template legitimately contains `CUSTOMIZE` guidance while already
owning its paths. A template tree identified by `sha=unknown` is `n/a`; only an
installed adopter tree with unresolved ownership customization is off.

## Additional corrected boundaries from independent review

- Sensors expose facts and never mutate. The existing `setup-ruleset` command
  is an explicit adopter-invoked actuator, so saying the kit "never enforces"
  would be inaccurate.
- Every active control must be qualified by applicable bypass actors; a
  bypassable control is not unqualified green.
- Governance status evaluates controls relative to a persisted `solo` or
  `team` declaration. An undeclared profile is unknown rather than guessed.
- Merge queue is `n/a` for a personal repository. An eligible organization
  repository is not ready until CI handles `merge_group`.
- Runtime controls requiring authenticated actors or session telemetry remain
  platform or future-GitHub-App capabilities. Issue
  [#6](https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/6#issuecomment-5305170668)
  makes them mandatory before external contributors, delegation licenses, or
  auto-merge are enabled, whichever occurs first.

## Feasibility conclusion

Repository governance sensors are feasible with existing Bash 3.2, `gh`, `jq`,
`sed`, and `awk` dependencies. Their safe boundary is observation with explicit
unknown and uncheckable states. Applying rules remains a deliberate,
adopter-invoked action. Authenticated runtime state, role enforcement,
heartbeats, budgets, pause/resume, and a supervision console are not feasible
as trustworthy plain-file controls.
