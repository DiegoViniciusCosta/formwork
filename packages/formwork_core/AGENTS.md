# formwork_core

Root rules in `/AGENTS.md` apply. Additional rules for this package:

- Pure Dart, and it must stay usable from a Dart CLI or server: no
  Flutter or `dart:ui` in imports, tests or `pubspec.yaml`. Tests use
  `package:test` and run with `dart test`.
- Deterministic: no I/O, no timers, no global state.
- No runtime dependency at all. Dev dependencies are fine.
- `lib/src/engine/` is the engine. It imports nothing from
  `lib/src/catalog/`, so JSON stays one front door among several
  (design doc 0007).
- `lib/src/catalog/` holds what only JSON catalogs need, such as missing
  data. It may import the engine.
- `FormSnapshot` is the only state crossing into `formwork`.
