# Principles

formwork exists to do three things better than any other form library.
Every feature must reinforce at least one of them and weaken none.

Each principle has a rule, what it forbids, and how it is verified. A
principle that is not verified automatically will erode, so "verified by"
distinguishes what CI enforces today from what is planned.

## 1. Agnostic of design system and state management

**Rule.** Everything a field needs to render arrives through `FieldContext`.
State enters and leaves only as an immutable `FormSnapshot` plus callbacks.
Nothing requires a specific provider, `InheritedWidget` or package.

**Forbids.**
- Flutter or `dart:ui` imports in `lib/src/core`.
- `material.dart` or `cupertino.dart` in `formwork`. Visual kits are
  satellite packages (`formwork_material`, ...).
- Runtime dependencies besides the Flutter SDK.

**Verified by.**
- Enforced: `tool/check_principles.sh` in CI.
- Planned: the behavior suite runs against two adapters (`ValueNotifier` and
  a stream-based one) to prove no single state approach is assumed.

## 2. Surgical rebuilds

**Rule.** A change to field X rebuilds X and only the fields whose
presentable state changed: value, displayed error, enabled, visibility,
validating. Engine work is proportional to the affected fields, never to
the size of the form.

**Forbids.**
- Any feature that rebuilds the whole form for a local change. This applies
  to every future source of change: async validation completing, server
  errors arriving, focus moving (which must cause zero field rebuilds).

**Verified by.**
- Enforced: rebuild-count tests (`test/rebuild_test.dart`). They are a
  contract: every feature that affects rendering adds its own.
- Planned: validator-invocation counts per change, catching O(n) regressions
  in the engine even when the UI still looks fast.

## 3. Serious validation engine

**Rule.** "Serious" means:
- **Deterministic:** the same values always produce the same errors; the
  incremental path always matches a full revalidation.
- **Race-free async:** stale results are discarded, never displayed.
- **Explicit dependencies:** cross-field rules declare what they read.
- **Localizable:** validators return error codes with params, not text.
- **Server-aware:** server-side errors are first-class, not a workaround.
- **Tolerant:** unknown field types, validators or operators are skipped and
  reported, never crash the screen.

**Forbids.**
- Validation state living outside the snapshot.
- Hardcoded message text inside validators.

**Verified by.**
- Enforced: incremental-versus-full equivalence test over a fixed sequence.
- Planned: property test over random change sequences, race tests with
  `fakeAsync`, minimum coverage threshold for `lib/src/core`.

## The feature filter

Before anything enters `formwork`, answer two questions:

1. Which principle does it reinforce?
2. Does it weaken any of them?

If it reinforces none, it does not enter the core. It becomes a satellite
package, a recipe in the docs, or it stays out.

Examples of the filter applied:

| Proposal                         | Outcome                                            |
|----------------------------------|----------------------------------------------------|
| Error codes plus localizer       | Core: reinforces 1 and 3                           |
| Lazy sliver rendering            | Core: reinforces 2                                 |
| Multi-step wizard UI             | Only the primitive "validate a group of fields" enters the core |
| Ready-made grid layouts          | Only a layout builder hook enters the core         |
| Material widgets                 | Satellite package: would violate 1                 |
| Form testing utilities           | Satellite package                                  |
| Show only missing fields         | Recipe built on the engine's public API (`missingKeys`, `missingFields`) |
| Theming, networking, file upload | Out                                                |
