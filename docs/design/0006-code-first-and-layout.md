# 0006: Forms as classes, and layout

Status: **draft**

## Problem

**Writing a form in code means writing a `Map` of strings.** Most forms are
written in code, not served as JSON:

```dart
FormConfig.fromMap({'fields': [
  {'key': 'income', 'type': 'number',
   'validators': [{'type': 'minLenght', 'value': 8}]},  // typo
]});
```

- No autocomplete, and no type checks.
- A misspelled validator is silently skipped: the tolerance rule, made for
  catalogs from a newer server, turns a typo into a missing check.
- Reading a value is `snapshot.values['income'] as num?`.

0001 §3 introduces typed definitions (`FieldDef<T>`, `FormDef`), but it
still refers to fields by string. `eq('maritalStatus', 'married')` fails
only at runtime, and it leaves open where a `FieldDef` handle comes from
when reading a value.

**There is no layout.** `DynamicForm` renders a `Column` of every visible
field. None of these are possible:
- two fields side by side;
- a heading between sections;
- a field inside a card.

In `flutter_form_builder` and `reactive_forms`, every field is a widget
the developer places anywhere. This is the biggest blocker for real apps,
and PRINCIPLES.md already reserves a "layout builder hook" for the core.

Server-driven forms need layout too: sections and rows, sent with the
catalog.

## Principles

- **Reinforces 3 (validation).** Mistakes in validators, conditions and
  value types become compile errors on the code path. The tolerance rule
  stays on the JSON path, where it belongs.
- **Reinforces 2 (rebuilds).** A field placed on its own listens only to
  its own state. This is the per-field notification of 0002 stage 3, with
  a natural API on top.
- **Reinforces 1 (agnostic).**
  - Layout nodes are drawn by builders a design system registers, exactly
    like fields.
  - `FormScope` is an optional convenience: every widget also takes its
    inputs explicitly, as PRINCIPLES.md §1 requires ("nothing requires a
    specific provider, `InheritedWidget` or package").
- **Risk: a bigger API.** There are two ways to lay out a form: widgets in
  code, and a layout tree. Each has one job, and both feed the same
  engine.

## Decision

### 1. A form is a class; fields are members

```dart
enum MaritalStatus { single, married }

class ProfileForm extends FormDef {
  final fullName = TextFieldDef('fullName',
      label: 'Full name', required: true, validators: [minLength(3)]);

  final income = NumberFieldDef('income',
      label: 'Monthly income', validators: [min(1000)]);

  final maritalStatus = ChoiceFieldDef<MaritalStatus>('maritalStatus',
      label: 'Marital status',
      options: [for (final s in MaritalStatus.values) Option(s, s.name)]);

  late final spouseName = TextFieldDef('spouseName',
      label: 'Spouse name', required: true,
      visibleWhen: maritalStatus.equals(MaritalStatus.married));

  final password = TextFieldDef('password', validators: [minLength(8)]);
  late final confirm = TextFieldDef('confirm', validators: [matches(password)]);

  @override
  List<FieldDef> get fields =>
      [fullName, income, maritalStatus, spouseName, password, confirm];
}
```

- **Conditions reference fields, not strings.** `maritalStatus.equals(v)`
  builds the same `Condition` node as 0001 §4's `eq('maritalStatus', v)`,
  so it serializes and feeds the dependency graph the same way.
  - `equals` and `isIn` take a `T`.
  - Number fields add `greaterThan` and the other comparisons.
  - `all`, `any` and `not` combine conditions.
- **Validators are typed.** `TextFieldDef` takes `Validator<String>` and
  `NumberFieldDef` takes `Validator<num>`, so `min(1000)` on a text field
  does not compile. A cross-field validator takes a field:
  `matches(password)`.
- **Values are typed.** `snapshot.valueOf(form.income)` is `num?`.
- **`late final`** lets a member reference an earlier one. This is plain
  Dart, and nothing specific to formwork.
- **`FormDef([...])` still works** for forms built as a list. The class is
  the recommended shape, because `form.` plus autocomplete lists every
  field.
- **The key stays explicit** (`'fullName'`): it is the payload and JSON
  key. In debug mode, a duplicated key throws when the form is built.
- **Order comes from `fields`.** It is the order `FormView` renders
  without a layout, and the order of the payload.

### 2. Custom fields are typed too

```dart
class RatingFieldDef extends FieldDef<int> {
  RatingFieldDef(super.key, {super.label, this.max = 5});
  final int max;
}
```

- A builder for `rating` receives `props.def` as `RatingFieldDef` and
  reads `.max` with its type, instead of today's `extra['max'] as int?`.
- For the JSON path, the type registers a factory that builds a
  `RatingFieldDef` from its map.

### 3. Values that are not JSON: a codec per field

`MaritalStatus.married` is not JSON. Each `FieldDef<T>` has a codec for
the payload and for the JSON catalog:

- **Built-in types need nothing.** `String`, `num` and `bool` are their own
  JSON.
- **Enums.** `ChoiceFieldDef<T extends Enum>` maps a value to and from its
  `name` by default.
- **Other types** (for example `DateTime`) pass `codec:` explicitly.
  Without one, building the form throws in debug mode.

The engine stores `T`. The payload and `FormDef.fromJson` go through the
codec.

### 4. Layout in code: place each field anywhere

`FormView` keeps rendering every visible field in a column. That is the
zero-effort default. For real layouts, each field is placed on its own:

```dart
FormScope(
  controller: controller,   // optional convenience, see below
  registry: registry,
  child: Column(children: [
    Text('Personal data', style: theme.titleLarge),
    FieldView(form.fullName),
    Row(children: [
      Expanded(child: FieldView(form.income)),
      Expanded(child: FieldView(form.maritalStatus)),
    ]),
    Card(child: FieldView(form.spouseName)), // hidden when its rule is false
  ]),
)
```

- **`FieldView(def)`** renders one field through the registry.
  - It rebuilds only when that field's `FieldState` changes (0001 §6),
    through the per-field notification of 0002 stage 3.
  - A hidden field renders nothing.
- **`FormScope` is optional.** Every `FieldView` also accepts `controller:`
  and `registry:` directly.
- **Bloc and Riverpod users** get a presentational variant that takes the
  field's state and a callback:
  `SnapshotFieldView(def, state:, onChanged:, registry:)`. It is fed by
  `BlocSelector`, `select` or equivalent, and mirrors 0004's
  `SnapshotFormView`.
- **Placement is checked in debug mode:**
  - a `FieldView` for a field that is not in the form throws;
  - so does a field placed twice.

  This catches the most likely mistake with classes: forgetting to list a
  member in `fields`.

### 5. Layout from the server: a separate layout tree

A catalog may carry a `layout` next to `fields`:

```json
{
  "fields": [ ... ],
  "layout": [
    { "type": "section", "title": "Personal data", "children": [
        "fullName",
        { "type": "row", "children": ["income", "maritalStatus"] }
    ]},
    "spouseName"
  ]
}
```

- **Separate from `fields`, on purpose.**
  - `fields` stays pure data. A Dart backend validating the same catalog
    ignores `layout`.
  - Layout nodes have no key and no path, and never touch the payload.
  - 0001's `group` stays a *data* structure (the `address.zipCode` path),
    not a visual one.
- **Layout builders**, registered like field builders:

  ```dart
  layouts.register('section', (context, node, children) => MySection(
        title: node['title'] as String?, children: children));
  ```

  - The core ships only a fallback: children in a column.
  - `formwork_material` ships Material builders for `section` and `row`.
- **Visibility.** A layout builder receives only the visible children. A
  node whose children are all hidden is not rendered.
- **Tolerance, for a catalog newer than the app:**
  - an unknown layout type renders its children in a column and is
    reported;
  - a field missing from `layout` is appended at the end, so a new field
    is never lost;
  - a key in `layout` that is not a field is skipped and reported.
- **The same tree from code.** A `FormDef` can override
  `LayoutNode get layout`, built with `Section(...)` and `Row(...)`.
  `FormView` renders it. One model serves both front doors, as 0001
  wants.

## Alternatives considered

- **Code generation** (`build_runner`, annotated classes) to remove the
  repeated key. Lost: a build step for every user, for one repeated
  string. Dart macros, which would have done this without a build step,
  were discontinued.
- **String constants** (`const kIncome = 'income'`). They fix typos, but
  not types: conditions, validators and values stay untyped.
- **A builder DSL** (`form.text('income').min(1000)`). Fluent, but members
  of a class are what autocomplete and "go to definition" understand
  best, and a DSL still returns something you have to name.
- **Registration from inside the class**, to avoid listing `fields`.
  Lost: Dart initializers cannot call instance methods, and `late` members
  initialize on first access, so the order would be accidental. The
  explicit list plus the debug placement check is simpler and
  predictable.
- **Layout nodes mixed into `fields`** (`{"type": "section", ...}` among
  the fields). Lost: it mixes presentation into the data contract, and a
  backend would have to skip them.
- **Layout only in code.** Lost: server-driven forms, the package's main
  use case, need sections and rows too.

## Impact

- **Depends on:**
  - 0001: `FieldDef<T>`, `FormDef`, `Condition`, `FieldState`;
  - 0002 stage 3: per-field notification, needed by `FieldView`, so stage
    3 moves into the 0001 release;
  - 0004: `FieldProps`, `FormView`, `SnapshotFormView`.

  It ships in the same release as 0001.
- **Catalog format:** a new optional top-level `layout`. It is additive,
  and catalogs without it render as today. `schemaVersion` stays 1,
  unless the 0001 changes raise it anyway.
- **Code:**
  - core: condition helpers on `FieldDef`, codecs, the layout model and
    its JSON parsing;
  - widgets: `FormScope`, `FieldView`, `SnapshotFieldView`,
    `LayoutRegistry`;
  - `formwork_material`: section and row builders;
  - the example: a scenario that lays out the profile form, and the
    catalog playground with a layout.
- **Tests, written first:**
  - compile-time checks, as a test file that must not compile: `min(1000)`
    on a text field, and `equals('x')` on an enum field;
  - `equals(...)` builds the same `Condition` as `eq(...)` and serializes
    the same;
  - a codec round trip for an enum, and a debug error when a `DateTime`
    field has no codec;
  - `FieldView` rebuilds only its own field (`rebuild_test.dart`);
  - debug errors for a field not in the form and a field placed twice;
  - layout tolerance: an unknown node, a field missing from `layout`, and
    an unknown key;
  - a section whose children are all hidden is not rendered;
  - the same form, built from JSON and from the class, produces equal
    snapshots.

## Open questions

1. **`fields` or reflection-free discovery.** Is the explicit list plus
   the debug check enough, or do we want a lint (a custom analyzer rule)
   that flags a `FieldDef` member missing from `fields`?
2. **Layout nodes and the dependency graph.** Should a section be able to
   have its own `visibleWhen` (hide the whole section), or is "all
   children hidden" enough?
3. **List items in layout.** 0001 leaves list UI to a later doc. Placing
   `FieldView`s for list items (`form.dependents.item(id).name`) is
   decided there, not here.
4. **Names.** `FieldView` and `SnapshotFieldView` follow 0004's
   `FormView` and `SnapshotFormView`. They should be decided together with
   0004's open question 1 (two widgets or one).
