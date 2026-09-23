# formwork

**Surgical rebuilds. Serious validation. Any design system.**

formwork gives your forms structure without imposing their look: bring your
own design system and your own state management, and formwork handles
state, validation and rendering, one field at a time.

## Why formwork

- **Any design system.** Field builders receive a tiny contract (`value`,
  `errorText`, `enabled`, `onChanged`) that any component can satisfy. The
  core ships no visual widgets; a Material kit lives in `formwork_material`.
- **Any state management.** The core is pure Dart, with no Flutter import.
  State is an immutable `FormSnapshot`, so Bloc, Riverpod, Provider or a
  plain `ValueNotifier` all work through a small adapter. No dependency is
  forced on your app.
- **Surgical rebuilds.** Typing in one field rebuilds that field only, not
  the whole form. Validation is incremental. Both are covered by tests.
- **Server-driven ready.** Forms can come from a Map/JSON catalog. Unknown
  field types and validators are skipped and reported, never crash the
  screen.

## Quick start

```dart
final registry = materialFieldRegistry(); // from formwork_material
final validators = ValidatorRegistry();

final catalog = FormConfig.fromMap(json, supportedTypes: registry.types);
final pending = missingFields(catalog, userData, validators: validators);

if (pending.fields.isNotEmpty) {
  final controller = DynamicFormController(
    FormEngine(config: pending, validators: validators),
    initialData: userData,
  );

  // In your widget tree:
  DynamicForm(controller: controller, registry: registry);

  // In your call to action:
  final payload = controller.submit(); // null when invalid
  if (payload != null) await api.updateProfile(payload);
}
```

`initialData` feeds visibility rules and prefills invalid values, but only
the fields of the form end up in the payload, which is ready for a PATCH.

See [`example/`](example/lib/main.dart) for a complete app.

## Recipe: ask only for missing data

`missingFields` narrows a catalog down to the fields that fail validation
for a given user, including fields that are filled but invalid, and
resolves conditional fields against the data you already have:

```dart
final pending = missingFields(catalog, userData);
// catalog: 12 fields. userData: 9 of them valid.
// pending: the 3 fields left to ask for.
```

## Catalog format

```json
{
  "schemaVersion": 1,
  "fields": [
    {
      "key": "spouseName",
      "type": "text",
      "label": "Spouse name",
      "required": true,
      "validators": [{ "type": "minLength", "value": 3 }],
      "visibleWhen": { "field": "maritalStatus", "equals": "married" }
    }
  ]
}
```

| Key            | Type    | Description                                            |
|----------------|---------|--------------------------------------------------------|
| `key`          | String  | Unique id; key in the payload                          |
| `type`         | String  | `text`, `email`, `password`, `number`, `dropdown`, `checkbox` or your own |
| `label`        | String  | Label                                                  |
| `hint`         | String? | Helper text                                            |
| `required`     | bool    | Defaults to `false`                                    |
| `initialValue` | any     | Used when there is no user data                        |
| `options`      | List    | `[{value, label}]` for `dropdown`                      |
| `validators`   | List    | `[{type, value?, message?}]`                           |
| `visibleWhen`  | Map?    | `{field, equals}`                                      |

Any other key is kept in `FieldConfig.extra`, for custom builders.

Built-in validators: `required`, `minLength`, `maxLength`, `pattern`, `email`,
`min`, `max`. Every validator accepts a `message` override, which is also how
you localize messages.

## State management adapters

The engine is pure: it takes a snapshot and returns a new one.

### Bloc / Cubit

```dart
class ProfileFormCubit extends Cubit<FormSnapshot> {
  ProfileFormCubit(this.engine, Map<String, Object?> data)
      : super(engine.initial(data));

  final FormEngine engine;

  void change(String key, Object? value) =>
      emit(engine.change(state, key, value));

  Map<String, Object?>? submit() {
    final result = engine.submit(state);
    emit(result.snapshot);
    return result.payload;
  }
}

BlocBuilder<ProfileFormCubit, FormSnapshot>(
  builder: (context, snapshot) => DynamicFormView(
    engine: context.read<ProfileFormCubit>().engine,
    snapshot: snapshot,
    onChanged: context.read<ProfileFormCubit>().change,
    registry: registry,
  ),
);
```

### Riverpod

```dart
class ProfileForm extends Notifier<FormSnapshot> {
  late final FormEngine engine;

  @override
  FormSnapshot build() {
    engine = FormEngine(config: ref.watch(pendingFieldsProvider));
    return engine.initial(ref.watch(userDataProvider));
  }

  void change(String key, Object? value) =>
      state = engine.change(state, key, value);
}
```

## Custom fields

```dart
registry.register('taxId', (context, field, ctx) => TextControllerBinding(
      initialText: ctx.value?.toString() ?? '',
      builder: (_, controller) => MyDsTextInput(
        controller: controller,
        label: field.label,
        errorText: ctx.errorText,
        enabled: ctx.enabled,
        onChanged: ctx.onChanged,
      ),
    ));
```

Text inputs should use `TextControllerBinding` so the controller survives
rebuilds.

## Stability

The catalog format is a public contract. Breaking changes to it, or to the
public API, bump the major version. Until 1.0.0, breaking changes bump the
minor version.

## License

Apache 2.0. See [LICENSE](LICENSE).
