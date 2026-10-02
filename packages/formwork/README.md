# formwork

**Surgical rebuilds. Serious validation. Any design system.**

formwork gives your forms structure without imposing their look: bring your
own design system and your own state management, and formwork handles
state, validation and rendering, one field at a time.

## Why formwork

- **Any design system.** Field builders receive a tiny contract,
  `FieldProps` (`def`, `value`, `errorText`, `enabled`, `onChanged` and the
  raw `error`), that any component can satisfy. The
  core ships no visual widgets; a Material kit lives in `formwork_material`.
- **Any state management.** The core is pure Dart, in its own package
  (`formwork_core`), with no Flutter dependency.
  State is an immutable `FormSnapshot`, so Bloc, Riverpod, Provider or a
  plain `ValueNotifier` all work through a small adapter. No dependency is
  forced on your app.
- **Surgical rebuilds.** Typing in one field rebuilds that field only, not
  the whole form. Validation is incremental. Both are covered by tests.
- **Server-driven ready.** Forms can come from a JSON catalog, or be
  written as typed Dart classes. Unknown field types, validators and
  operators are skipped and reported, never crash the screen.

## Quick start

```dart
final registry = materialFieldRegistry(); // from formwork_material

final catalog = FormCatalog.fromJson(json); // or a FormDef written in Dart
final controller = FormController(
  catalog,
  initialValues: userData, // what you already know, prefilled
);

// In your widget tree:
FormView(controller: controller, registry: registry);

// In your call to action: validates, sends, records the server's answer,
// and focuses the first field with an error.
final outcome = await controller.submitTo(api.updateProfile);

// A button that follows the send:
FormStatusBuilder(
  controller: controller,
  select: (s) => s.submitting,
  builder: (context, submitting) => FilledButton(
    onPressed: submitting ? null : () => controller.submitTo(api.updateProfile),
    child: Text(submitting ? 'Sending…' : 'Send'),
  ),
);
```

`api.updateProfile` returns `ServerErrors?`: `null` when the server
accepted, or errors for fields and for the whole form. `controller.submit()`
validates without sending.

`initialValues` prefills the form and feeds visibility rules, but only the
visible fields of the form end up in the payload, which is ready for a
PATCH. `catalog.issues` lists what the catalog had that this app version
does not know.

### Forms written in Dart

```dart
enum MaritalStatus { single, married }

class ProfileForm extends FormDef {
  final fullName = TextFieldDef('fullName',
      label: 'Full name', required: true, validators: [minLength(3)]);
  final maritalStatus = ChoiceFieldDef<MaritalStatus>('maritalStatus',
      label: 'Marital status',
      options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
  late final spouseName = TextFieldDef('spouseName',
      label: 'Spouse name', required: true,
      visibleWhen: maritalStatus.equals(MaritalStatus.married));

  @override
  List<FieldDef<Object?>> get fields => [fullName, maritalStatus, spouseName];
}

final form = ProfileForm();
final controller = FormController(form);
controller.value.valueOf(form.maritalStatus); // MaritalStatus?
```

Validators and conditions are typed: `min(1000)` on a text field, or a
string condition on an enum field, does not compile.

### Place each field anywhere

`FormView` renders every visible field in a column. For your own layout,
place each field with a `FieldView`; each one rebuilds only when its own
field changes:

```dart
FormScope(
  controller: controller,
  registry: registry,
  child: Column(children: [
    Text('Personal data', style: theme.titleLarge),
    FieldView(form.fullName),
    FieldView(form.spouseName, wrap: (context, field) => Card(child: field)),
  ]),
)
```

`wrap` builds the surroundings only while the field is visible.

See [`example/`](example/lib/main.dart) for a complete app.

## Recipes: missing data

Two optional recipes for users you already know something about. Both are
built on the catalog's public API; the engine works the same either way.
A field is *missing* when its stored value fails the catalog's own rules:
required and empty, filled but invalid, or not decodable.

### Ask only what is missing

`onlyMissing` narrows the catalog to the missing fields:

```dart
final form = catalog.onlyMissing(userData);
if (form.fields.isNotEmpty) {
  final controller = FormController(
    form,
    initialValues: userData, // keep passing it: see below
  );
}
```

Conditional fields are resolved against the data you already have. When a
known field sits between two missing ones in a `visibleWhen` chain, it is
kept, so hiding the top of the chain still hides the bottom. It shows its
stored value because you pass the same `userData` to the controller.

### Highlight what is missing

`missingKeys` returns the same selection as paths and hides nothing. Show
the whole form and let your builders mark what is missing:

```dart
final missing = catalog.missingKeys(userData);
registry.register('text', (context, field) =>
    MyTextField(field, highlighted: missing.contains(field.def.path)));
```

The set describes the stored data, so it is fixed for the session.

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
      "visibleWhen": { "eq": ["maritalStatus", "married"] }
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
| `visibleWhen`  | Map?    | A condition: when the field is shown                   |
| `enabledWhen`  | Map?    | A condition: when it can be edited                     |
| `requiredWhen` | Map?    | A condition: when it is required                       |

A condition is an object with one operator: `eq`, `ne`, `in`, `gt`, `gte`,
`lt`, `lte` and `empty` read a path; `all`, `any` and `not` combine
conditions:

```json
{ "all": [ { "eq": ["maritalStatus", "married"] }, { "gte": ["age", 18] } ] }
```

Any other key is kept in `FieldDef.extra`, for custom builders.

A `group` puts fields under one key, and the payload nests them:

```json
{ "key": "address", "type": "group", "fields": [
  { "key": "zipCode", "type": "text", "required": true } ] }
```

The field's path is `address.zipCode` (in code, `TextFieldDef('address.zipCode')`),
and the payload holds `{"address": {"zipCode": "..."}}`. Initial values
take the same shape. Rules read fields, never a whole group:
`{"empty": ["address.zipCode"]}`, not `{"empty": ["address"]}`.

A `list` repeats its `itemFields`, with optional `minItems` and
`maxItems`; the payload holds an array of objects:

```json
{ "key": "dependents", "type": "list", "minItems": 1, "maxItems": 3,
  "itemFields": [ { "key": "name", "type": "text", "required": true } ] }
```

In code: `ListFieldDef('dependents', itemFields: (item) =>
[TextFieldDef('$item.name', required: true)])`. Items change through
`controller.addItem`, `removeItem` and `moveItem`. formwork ships no list
widget: register a `"list"` builder that shows the add and remove
buttons; `FormView` places each item's fields right after it.

A catalog may carry a `layout` next to `fields`: sections and rows that
arrange the fields, and never touch the payload. Children are keys (a
group's key places all its fields) or nodes:

```json
"layout": [
  { "type": "section", "title": "Personal data", "children": [
      "fullName",
      { "type": "row", "children": ["income", "maritalStatus"] } ] },
  "spouseName"
]
```

`FormView(layouts: materialLayoutRegistry())` renders it with
`formwork_material`; any other node type is yours to register in a
`LayoutRegistry`, and renders as a column until you do. A field the
layout does not place renders at the end, and what the reader skipped is
in `catalog.layoutIssues`. In code, override `FormDef.layout` with
`SectionNode` and `RowNode`.

Built-in validators: `required`, `minLength`, `maxLength`, `pattern`,
`email`, `min`, `max` and `matches` (`{"type": "matches", "field":
"password"}`). Validators return error codes, never text: an
`ErrorLocalizer` turns them into text, English by default, and a
validator's `message` overrides the text of its code on that field.

## State management adapters

The engine is pure: it takes a snapshot and returns a new one.

### Bloc / Cubit

```dart
class ProfileFormCubit extends Cubit<FormSnapshot> {
  ProfileFormCubit(FormDef form, Map<String, Object?> data)
      : super(engine.registerAll(
            engine.initial(initialValues: data), form.fields));

  static const engine = FormEngine();

  void change(FieldPath path, Object? value) =>
      emit(engine.change(state, path, value));

  Map<String, Object?>? submit() {
    final result = engine.submit(state);
    emit(result.snapshot);
    return result.payload;
  }
}

BlocBuilder<ProfileFormCubit, FormSnapshot>(
  builder: (context, snapshot) => SnapshotFormView(
    snapshot: snapshot,
    onChanged: context.read<ProfileFormCubit>().change,
    registry: registry,
  ),
);
```

Each snapshot lists the fields whose state changed in `changedPaths`, and
keeps every other field's `FieldState` identical, so a `BlocSelector` per
field, feeding a `SnapshotFieldView`, rebuilds only that field.

### Riverpod

```dart
class ProfileForm extends Notifier<FormSnapshot> {
  static const engine = FormEngine();

  @override
  FormSnapshot build() => engine.registerAll(
        engine.initial(initialValues: ref.watch(userDataProvider)),
        ref.watch(pendingFieldsProvider).fields,
      );

  void change(FieldPath path, Object? value) =>
      state = engine.change(state, path, value);
}
```

### The engine without widgets

`package:formwork/formwork.dart` brings in Flutter's widgets layer. To
keep a layer of your app free of Flutter (a cubit, a notifier, a
repository), import the engine from its own package, and list it in your
`pubspec.yaml`, since you import it directly:

```yaml
dependencies:
  formwork: ^0.1.0
  formwork_core: ^0.1.0 # same version as formwork
```

```dart
import 'package:formwork_core/formwork_core.dart';
```

A Dart backend or CLI depends on `formwork_core` alone, and validates the
same catalogs as the app.

## Custom fields

```dart
registry.register('taxId', (context, field) => TextControllerBinding<Object>(
      value: field.value,
      onChanged: field.onChanged,
      builder: (_, controller, onTextChanged) => MyDsTextInput(
        controller: controller,
        label: field.def.label,
        errorText: field.errorText,
        enabled: field.enabled,
        onChanged: onTextChanged,
      ),
    ));
```

A field type of your own is a `FieldDef` subclass, rendered with its
definition typed:

```dart
class RatingFieldDef extends FieldDef<int> {
  RatingFieldDef(super.key, {super.label, this.max = 5});

  @override
  String get type => 'rating'; // the JSON "type"

  final int max;
}

registry.registerDef<RatingFieldDef, int>(
    (context, field, def) => MyRating(max: def.max, value: field.value));
```

For catalogs, register a factory that builds it from its entry:
`FieldTypeRegistry()..register('rating', (f) => RatingFieldDef(f.key,
label: f.label, max: f.json['max'] as int? ?? 5))`, and pass it to
`FormCatalog.fromJson(json, types: ...)`.

Text inputs should use `TextControllerBinding`. It keeps one controller
for the life of the field, so the cursor survives rebuilds, and it keeps
the text in step with the value: undo, reset and state restored by Bloc
or Riverpod show up in the field. For non-text values, pass `parse` and
`format`, for example `parse: (t) => num.tryParse(t)`.

## Stability

The catalog format is a public contract. Breaking changes to it, or to the
public API, bump the major version. Until 1.0.0, breaking changes bump the
minor version.

## License

Apache 2.0. See [LICENSE](LICENSE).
