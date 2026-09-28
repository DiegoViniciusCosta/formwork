# formwork_core

The engine of [formwork](../formwork), in pure Dart: field catalogs,
validation, visibility rules and missing data. No Flutter dependency.

Flutter apps do not need to add it: `package:formwork/formwork.dart`
re-exports it. Depend on `formwork_core` alone to use the same engine
without Flutter, for example to validate a catalog, or a submitted
payload, in a Dart backend or CLI.

```dart
import 'package:formwork_core/formwork_core.dart';

const engine = FormEngine();
final catalog = FormCatalog.fromJson(catalogJson);
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

See the [formwork README](../formwork/README.md) for the full guide.
