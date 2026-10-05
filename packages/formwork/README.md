# formwork

**Server-driven forms for Flutter, in your own design system.**

Change a form on your server and every installed app shows the new
version, with no release. formwork renders it with your own components,
rebuilds only the fields a change actually affects, and validates it with
the same rules in your Dart backend.

```json
{
  "fields": [
    { "key": "fullName", "type": "text", "label": "Full name", "required": true },
    { "key": "maritalStatus", "type": "dropdown", "label": "Marital status",
      "options": [ { "value": "single", "label": "Single" },
                   { "value": "married", "label": "Married" } ] },
    { "key": "spouseName", "type": "text", "label": "Spouse name", "required": true,
      "visibleWhen": { "eq": ["maritalStatus", "married"] } }
  ]
}
```

```dart
final controller = FormController(FormCatalog.fromJson(json));

FormView(controller: controller, registry: materialFieldRegistry());

await controller.submitTo(api.updateProfile);
```

That is a complete form. The spouse field shows up only for married
users. Required fields block the send, and focus jumps to the first error.
The payload carries only the visible fields, and errors the server returns
appear on their fields.

## Why formwork

### Change forms without an app release

The server sends a JSON catalog: fields, conditions (`visibleWhen`,
`requiredWhen`, `enabledWhen`), validators, groups, repeatable lists and
a layout of sections and rows. A catalog newer than the app does not
crash it: unknown field types, validators and operators are skipped and
listed in `catalog.issues`, and an unknown layout node renders its fields
in a column.

### Your design system, your state management

formwork ships no visual widgets. A field builder receives `FieldProps`
and returns any widget: your design system's input, a Material one from
`formwork_material`, or both side by side. State is an immutable
`FormSnapshot` from a pure-Dart engine, so Bloc, Riverpod and a plain
controller all drive it the same way.

### One keystroke, one rebuild

Typing in a field rebuilds that field, plus only the fields whose state
it changes: shown or hidden, required, enabled, or a cross-field error such
as a password confirmation. In a 60-field form where nothing depends on
the field being typed in, the other 59 stay as they are.
This is not a benchmark claim: rebuild counts are asserted in the test
suite, and CI checks them on every change.

### Validation you can trust

- **The same rules in the app and on the server.** The engine is pure
  Dart (`formwork_core`), so a Dart backend validates the same catalog
  with the same code.
- **Incremental equals full.** Randomized tests check that every change,
  including adding, removing and moving list items, leaves the form
  exactly as validating it from scratch would.
- **Server errors are first-class, and race-free.** An error for a field
  the user changed while the request was in flight is discarded, not
  shown on the new value.
- **Errors are data.** Validators return codes and parameters; your
  `ErrorLocalizer` turns them into text, in any language.

### Ask users only what is missing

Given what you already know about a user, `onlyMissing` narrows the form
to the answers still missing, and keeps conditional chains intact.
Profile completion and onboarding flows stop asking twice.

### Typed forms in Dart, too

Not every form comes from a server. A `FormDef` written in Dart runs
through the same engine, with typed values and typed conditions:
`min(1000)` on a text field does not compile.

## Is formwork for you?

**A good fit when:**

- forms change more often than you ship the app, or differ by user,
  tenant or country;
- your app has its own design system;
- forms are large enough that rebuilds and correct validation matter;
- a Dart backend must accept exactly what the app accepts.

**Probably not when:**

- **You want many ready-made inputs and no builders to write.**
  `formwork_material` covers text, e-mail, password, number, dropdown
  and checkbox; anything else is a builder you register.
  `flutter_form_builder`, for example, ships a dozen Material fields
  (date and range pickers, sliders, chips, radio groups...).
- **You need asynchronous validation while the user types**, such as
  "is this username taken?". formwork does not have it yet; errors the
  server returns after a submit are supported. `reactive_forms` has async
  validators with debounce.
- **Your backend is not in Dart and must enforce the same rules** without
  porting them: see [Validating on the backend](#validating-on-the-backend).
- **You need a list widget.** Lists (`ListFieldDef`) are in the engine,
  with add, remove and move, but the buttons and cards around the items
  are a builder you write.
- **Your forms are few, small and written by hand.** Flutter's `Form`
  and `TextFormField` may be all you need.

## See it running

The [example app](example/lib/main.dart) is a gallery of scenarios:
profile completion, conditional fields, groups and lists, custom
validators and field types, a rebuild inspector with a build counter on
each of 60 fields, undo over external state, and a catalog playground
where you edit JSON and see the form change live.

```bash
git clone https://github.com/DiegoViniciusCosta/formwork
cd formwork/packages/formwork/example
flutter run
```

## Install

```yaml
dependencies:
  formwork: ^0.1.0
  formwork_material: ^0.1.0 # optional: Material field builders
```

## Guide

### Render and submit

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

The engine is pure: it takes a snapshot and returns a new one. The
example app runs both adapters below, with a build counter on each field
and errors from a fake server:
[Cubit](example/lib/scenarios/cubit_form.dart) and
[Riverpod](example/lib/scenarios/riverpod_form.dart).

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

## Validating on the backend

**A Dart backend** (Shelf, Dart Frog, Serverpod, a CLI) depends on
`formwork_core` alone and runs the same engine on the same catalog:

```dart
final catalog = FormCatalog.fromJson(catalogJson);
const engine = FormEngine();
final form = engine.registerAll(
    engine.initial(initialValues: requestBody), catalog.fields);
final (:snapshot, :payload) = engine.submit(form);
if (payload == null) {
  // Invalid: each field's error is data, in snapshot.stateOf(def)!.error,
  // list item fields included (snapshot.visibleFields lists them all).
}
```

Hidden fields are left out of the payload, conditions are evaluated on the
submitted data, and custom field types and validators work once they are
registered on the server too.

**Any other backend** (Spring Boot, Node, Django...) gets the catalog
format, which is a documented contract, but not the engine: conditions and
validators must be ported to that language, or the Dart engine called as a
service. Until then, the server validates on its own, and formwork shows
what it rejects through `ServerErrors`.

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
