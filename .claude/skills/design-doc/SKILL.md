---
name: design-doc
description: Write a design document in docs/design/ for a decision that affects the catalog format, the public API or the architecture of formwork. Use before implementing any contract change.
---

# Writing a design doc

1. List `docs/design/` and read the existing docs. Reuse their decisions
   and vocabulary; do not contradict an approved doc silently.
2. Copy `docs/design/TEMPLATE.md` to `docs/design/NNNN-short-slug.md`,
   where `NNNN` is the next number.
3. Fill every section. The "Principles" section is mandatory: say which
   principle the decision reinforces and how it could weaken the others.
4. For each decision, include at least one real alternative and why it
   lost. A decision with no alternative considered is not a decision.
5. Put genuinely open questions under "Open questions" instead of guessing.
6. Set `Status: draft`. Only a human changes it to `accepted`.

Keep it short: a reviewer should finish it in ten minutes. Code sketches
show the API shape, not the implementation.
