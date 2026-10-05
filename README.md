# formwork

**Server-driven forms for Flutter, in your own design system.**

Change a form on your server and every installed app shows the new
version, with no release. formwork renders it with your own components,
under any state management, rebuilds only the fields a change actually
affects, and validates it with the same rules in your Dart backend.

```dart
final controller = FormController(FormCatalog.fromJson(catalogFromServer));

FormView(controller: controller, registry: myDesignSystemFields);

await controller.submitTo(api.updateProfile);
```

## What you get

- **Forms that change without an app release.** Fields, conditions,
  validators, groups, repeatable lists and layout come from a JSON
  catalog. A catalog newer than the app does not crash it: unknown field
  types, validators and operators are skipped and reported.
- **Your components, your state management.** formwork ships no visual
  widgets in its core. Plug in your design system, or start with
  [`formwork_material`](packages/formwork_material). Bloc, Riverpod or a
  plain controller.
- **One keystroke, one rebuild.** Typing rebuilds that field, plus only
  the fields whose state it changes: shown or hidden, required, enabled,
  or a cross-field error.
- **Validation you can trust.** The same engine runs in the app and in a
  Dart backend; server errors are first-class and race-free; errors are
  codes you translate, not hardcoded text.
- **Ask only what is missing.** Given what you know about a user,
  `onlyMissing` narrows the form to the answers still missing.
- **Typed Dart forms, too.** Forms written as Dart classes go through the
  same engine, with conditions checked at compile time.

The [`formwork` README](packages/formwork/README.md) has the full tour,
the catalog format, and an honest list of when *not* to use it.

## Promises kept by CI, not by hope

formwork is built on three principles, and each one is enforced by an
automated check that runs on every change:

| Principle | How it is checked |
|-----------|-------------------|
| **Agnostic** of design system, state management and of how forms are defined | A script fails the build if the core imports Flutter, or the rendering package imports Material or Cupertino, or `formwork_core` or `formwork` adds a runtime dependency |
| **Surgical rebuilds** | Rebuild counts per widget are asserted in the test suite |
| **A serious validation engine** | Randomized tests prove incremental validation equals a full one; race tests cover server answers that arrive after a change |

[PRINCIPLES.md](PRINCIPLES.md) explains each one, and the filter every
new feature goes through.

## Packages

| Package | What it is |
|---------|------------|
| [`formwork`](packages/formwork) | Rendering for Flutter; re-exports the engine |
| [`formwork_core`](packages/formwork_core) | Engine and validation in pure Dart, for apps and Dart backends |
| [`formwork_material`](packages/formwork_material) | Material field and layout builders |

## Try it

The example app is a gallery of scenarios, from profile completion to a
rebuild inspector with a build counter on each of 60 fields, and a
playground where you edit a JSON catalog and see the form change live:

```bash
cd packages/formwork/example
flutter run
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). API decisions are recorded in
[`docs/design`](docs/design), and `bash tool/verify.sh` runs everything CI
runs.

## License

Apache 2.0. See [LICENSE](LICENSE).
