# formwork

Root rules in `/AGENTS.md` apply. Additional rules for this package:

- `lib/src/core/` is the engine: pure Dart, deterministic, no I/O, no
  timers, no Flutter. It must be usable from a Dart CLI or server.
- `lib/src/flutter/` only adapts the engine to widgets. No validation or
  visibility logic lives here; if you need it, it belongs in the engine.
- `FormSnapshot` is the only state crossing the core/Flutter boundary.
- Field builders receive only `FieldContext`. Anything a design system
  needs must be added there, never read from elsewhere.
- `test/rebuild_test.dart` is a contract. A failing rebuild count is a
  regression, not a test to update, unless a design doc says otherwise.
