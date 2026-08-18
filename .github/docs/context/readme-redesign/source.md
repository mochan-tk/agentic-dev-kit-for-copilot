---
source: Task #116 owner-supplied README and overview image attachment set
retrieved: 2026-08-19
method: verbatim
collector: mochan-tk-task-116-readme-overview
sensitivity: internal
status: raw
---

# README redesign source capture

## Attachment metadata

- README draft
  - `display_name`: `README-revised-copy-paste-install.md`
  - `method`: `verbatim`
  - `size_bytes`: `13401`
  - `sha256`: `5c4c2da300ae32d41d4e827bd819b69209571a23c53468817009941861a1e2f5`
- README post-correction artifact
  - `method`: `ai-summary`
  - `size_bytes`: `13569`
  - `sha256`: `72bea18c4fcbfc4cda925d9bbfa05390d2aac2eea00aa7da591afe58be32d6a6`
  - `approval_url`: `https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/116#issuecomment-5332593329`
  - `note`: `Owner-approved exact paragraph inserted after the prerequisites paragraph. All other bytes remain identical to the supplied README source.`
  - `exact_inserted_paragraph`:
    ```markdown
    Public repositories work on any GitHub plan; private repositories require a
    paid plan because `setup-sources.sh` fails closed for private repositories on
    GitHub Free.
    ```
- Overview image
  - `display_name`: `a_clean_flat_infographic_diagram_poster_style_i.png`
  - `method`: `verbatim`
  - `size_bytes`: `1490062`
  - `sha256`: `95840911fbdc8765e9c6106efe66a88afad0959fb6cc36103aefc92b86a55ded`
  - `width_px`: `1536`
  - `height_px`: `1024`
  - `mode`: `RGB`

## Editorial decision

- `method: ai-summary`
- The repository's README replacement is intentionally the owner-supplied Human-on-the-Loop overview draft. The supplied draft and the infographic image satisfy the issue's deterministic validation checks, and the owner approved one factual caveat for current repository behavior at `https://github.com/mochan-tk/agentic-dev-kit-for-copilot/issues/116#issuecomment-5332593329`: public repositories work on any GitHub plan, but private repositories require a paid plan because `setup-sources.sh` fails closed for private repositories on GitHub Free.
- This collection records the canonical source material, the approved exact paragraph, and the derived README artifact hash after that exact insertion, without private paths or private chat data.
