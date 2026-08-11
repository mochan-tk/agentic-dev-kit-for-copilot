---
mode: agent
description: Elicit project context with the builtin connector's draft-first flow (intake, EARS candidate drafts, bounded questions) and land it under .github/docs/context.
---

Run the builtin connector's `retrieve` flow as specified in
`.github/connectors/builtin.md`; land material per
`.github/skills/context-collection/SKILL.md`. Those two files are
normative — on any conflict with this prompt, they win.

Context topic directory: .github/docs/context/${input:topic}

1. **Intake.** Ask me for whatever exists (file paths, pasted text,
   URLs); land it under the topic directory with provenance headers,
   sensitivity marking, redaction, and English rendering. Provided
   material shrinks the question budget.
2. **Draft first.** Write complete candidate requirements in EARS form,
   each with a stable `REQ-C##` id; mark unknowns
   `[NEEDS CLARIFICATION]` inline and record every defaulted decision
   in an **Assumptions** section — never invent facts silently.
3. **Bounded questions.** At most 3–5 per round, impact-ranked (scope
   and security first), each multiple-choice with a recommended
   option, one at a time; skip what the material already answers.
   Save each round to a dated Q&A file in the topic directory.
4. Repeat 2–3 until no `[NEEDS CLARIFICATION]` markers remain or I say
   stop; keep the draft and Assumptions current in the topic directory.
5. **Stop at the promotion bar.** Do not write to
   `.github/docs/agreements/` — promotion happens through the
   distillation PR gate (`/distill-context`, human review). Finish by
   listing which candidates look promotion-worthy and why.
