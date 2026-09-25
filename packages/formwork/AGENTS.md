# formwork

Root rules in `/AGENTS.md` apply. Additional rules for this package:

- The engine lives in `packages/formwork_core`, not here. `lib/formwork.dart`
  re-exports it, so an app adds one dependency.
- `lib/src/flutter/` only adapts the engine to widgets. No validation or
  visibility logic lives here; if you need it, it belongs in
  `formwork_core`.
- `FormSnapshot` is the only state crossing the core/Flutter boundary.
- Field builders receive only `FieldContext`. Anything a design system
  needs must be added there, never read from elsewhere.
- `test/rebuild_test.dart` is a contract. A failing rebuild count is a
  regression, not a test to update, unless a design doc says otherwise.
