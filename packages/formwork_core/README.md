# formwork_core

**Validate on your Dart server exactly what your Flutter app validates.**

The engine of [formwork](../formwork), in pure Dart: field catalogs,
validation, visibility rules and missing data, with no Flutter dependency
and no runtime dependency at all.

Flutter apps do not need to add it: `package:formwork/formwork.dart`
re-exports it. Depend on `formwork_core` alone to run the same engine
without Flutter: in a Dart backend (Shelf, Dart Frog, Serverpod), a CLI,
or a layer of your app you keep free of Flutter.

```dart
import 'package:formwork_core/formwork_core.dart';

const engine = FormEngine();
final catalog = FormCatalog.fromJson(catalogJson); // the app's catalog
final form = engine.registerAll(
  engine.initial(initialValues: submittedData),
  catalog.fields,
);
final (:snapshot, :payload) = engine.submit(form);
if (payload == null) {
  for (final def in snapshot.visibleFields) {
    print('${def.path}: ${snapshot.stateOf(def)!.error}'); // code + params
  }
}
```

## Why it matters

- **One source of truth.** The same catalog and the same rules decide
  what is valid in the app and on the server. No second implementation
  to drift.
- **Conditions are respected.** Conditions are evaluated on the
  submitted data, and a field hidden by `visibleWhen` is left out of the
  payload, on the server too.
- **Errors are data.** Each error is a code with parameters, ready to
  return to the app, which shows it on its field.
- **Immutable and pure.** The engine takes a snapshot and returns a new
  one: easy to test, safe to share between requests.

See the [formwork README](../formwork/README.md) for the full guide.
