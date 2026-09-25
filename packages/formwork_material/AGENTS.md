# formwork_material

Root rules in `/AGENTS.md` apply. Additional rules for this package:

- Builders only translate `FieldContext` into Material widgets. No
  validation, visibility or state logic here: that belongs to the engine
  in `formwork_core`.
- This package is also the reference for people writing builders for
  their own design system. Keep each builder short and obvious.
- Text inputs use `TextControllerBinding`.
