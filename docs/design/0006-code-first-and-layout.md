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
  its own state, through the keyed notification designed in §6.
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
  so it feeds the dependency graph the same way.
  - `equals` and `isIn` take a `T`.
  - Number fields add `greaterThan` and the other comparisons.
  - `all`, `any` and `not` combine conditions.
  - A condition on a key **outside the form** (user data that feeds
    visibility, as `missingFields` relies on) has no member, so the string
    form `eq('key', value)` stays for it.
- **Validators are typed.** `TextFieldDef` takes `Validator<String>` and
  `NumberFieldDef` takes `Validator<num>`, so `min(1000)` on a text field
  does not compile. A cross-field validator takes a field:
  `matches(password)`.
- **Values are typed.** `snapshot.valueOf(form.income)` is `num?`. The
  engine still stores `Object?` (0001 §3). What it holds are decoded `T`
  values, so the typed read is a safe cast.
- **`late final`** lets a member reference any other member. This is plain
  Dart, and nothing specific to formwork.
- **Cycles in code fail before the engine runs.** With typed members, two
  fields whose `visibleWhen` read each other throw a `StackOverflowError`
  when the form is built. Without explicit types, the analyzer reports
  "circularity found during type inference". 0001 §5's clear cycle error
  is therefore for the JSON path; the code path cannot even build a cycle.
- **`FormDef([...])` still works** for forms built as a list. The class is
  the recommended shape, because `form.` plus autocomplete lists every
  field.
- **The key stays explicit** (`'fullName'`): it is the payload and JSON
  key. A duplicated key always throws when the form is built. Nothing
  checks that the key matches the member name (`income` vs `'incme'`):
  that would need code generation (see Alternatives).
- **Order comes from `fields`.** It is the order `FormView` renders
  without a layout, and the order of the payload.

### 2. Custom fields are typed too

```dart
class RatingFieldDef extends FieldDef<int> {
  RatingFieldDef(super.key, {super.label, this.max = 5});

  @override
  String get type => 'rating'; // the registry key, and the JSON "type"

  final int max;
}

registry.registerDef<RatingFieldDef, int>(
  (context, props, def) => MyRating(max: def.max, value: props.value));
```

- A subclass declares its registry key by overriding `type`.
- `FieldBuilder` stays untyped per registry, because one registry holds
  every type. `registerDef<D, T>` does the one cast inside the library, so
  the builder receives `def` as `RatingFieldDef` and `props` as
  `FieldProps<int>`. Plain `register` still works and casts by hand.
- For the JSON path, the type also registers a factory that builds a
  `RatingFieldDef` from its map.

### 3. Values that are not JSON: a codec per field

`MaritalStatus.married` is not JSON. Each `FieldDef<T>` has a codec
between `T` and its JSON value.

**Where the codec applies.** At every boundary where JSON meets the form:
- `FormDef.fromJson`: `initialValue`, options, and the operands of
  conditions on that field. `{"eq": ["maritalStatus", "married"]}` decodes
  `"married"` through the field's codec, so it equals
  `maritalStatus.equals(MaritalStatus.married)`. Condition parsing
  therefore needs the field definitions, which `fromJson` already has.
- `initialValues`: data from the server arrives as JSON (`"married"`) and
  is decoded when the snapshot is created.
- The payload: encoded on submit.

**Defaults.**
- **`String`, `num` and `bool`** are their own JSON.
- **`ChoiceFieldDef<T>`** encodes each option by its declared value, and
  decodes by looking the JSON value up among its options. For an enum,
  the default JSON value of an option is the enum's `name`. A type
  parameter cannot list an enum's values, so decoding only knows the
  values present in `options`. That is exactly the set a choice field
  accepts. This keeps 0001's `ChoiceFieldDef<String>` working unchanged.
- **Any other `T`** (for example `DateTime`) must pass `codec:`.
  Otherwise building the form **always throws**, in release too. A
  missing codec is a programmer error on the code path, and a release
  build would otherwise fail later, inside `jsonEncode`.

### 4. Layout in code: place each field anywhere

`FormView` keeps rendering every visible field in a column, or the form's
layout tree (§5). That is the zero-effort default. For custom layouts,
each field is placed on its own:

```dart
FormScope(
  controller: controller,   // optional convenience, see below
  registry: registry,
  child: Column(children: [
    Text('Personal data', style: theme.titleLarge),
    FieldView(form.fullName),
    Row(children: [
      Expanded(child: FieldView(form.income)),
      FieldView(form.maritalStatus,
          wrap: (context, field) => Expanded(child: field)),
    ]),
    FieldView(form.spouseName,
        wrap: (context, field) => Card(child: field)),
  ]),
)
```

- **`FieldView(def)`** renders one field through the registry. A hidden
  field renders nothing.
- **`wrap`** builds the field's surroundings (a `Card`, an `Expanded`)
  **only while the field is visible**. Without it, the `Card` of a hidden
  field would stay on screen empty, and an `Expanded` would keep its
  share of the `Row`. The first `Expanded` above is written plainly on
  purpose: it is correct only for a field that never hides.
- **Rebuilds.** A `FieldView` rebuilds only when its own field's state
  changes (§6), keyed by the field's path, so text controllers and focus
  survive when a sibling appears or disappears.
- **Explicit inputs.** Everything `FormScope` provides can also be passed
  to `FieldView` directly:
  - `controller:`;
  - `registry:`;
  - `localizer:` (0001 §2);
  - `enabled:` (the view-level flag of 0004, for example `false` while
    submitting).

  These are what a `FieldView` needs to build a `FieldProps`.
- **`FormScope` carries only stable references**: the controller,
  registries, localizer and `enabled`. It never carries the snapshot, and
  `updateShouldNotify` compares by identity. Otherwise every change would
  rebuild every `FieldView` below it.
- **Bloc and Riverpod users** get a presentational variant that takes the
  field's state and a callback:
  `SnapshotFieldView(def, state:, onChanged:, registry:)`. It is fed by
  `BlocSelector`, `select` or equivalent, and mirrors 0004's
  `SnapshotFormView`.
- **Debug checks, reported and not thrown.**
  - A `FieldView` for a field that is not in the form is reported.
  - A field placed twice under the same controller is reported, not
    thrown: animated switchers, hero transitions, kept-alive pages and
    phone-and-tablet trees legitimately mount a field twice for a moment.
  - After the first frame, visible fields that no `FieldView` shows are
    reported. Otherwise such a field is still validated and blocks submit
    with an error nobody can see.

  A member that is neither listed in `fields` nor placed is just unused
  code: nothing can detect it without code generation.

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
- **Contract vocabulary.** The catalog format defines two node types:
  `section` (optional `title`, `children`) and `row` (`children`). Other
  node types are custom and follow the tolerance rule. Children are field
  paths (strings) or nodes (objects).
- **Groups.** A path to a group (`"address"`) places all the group's
  fields, in order. A path into a group (`"address.zipCode"`) places that
  field.
- **Layout builders**, registered like field builders:

  ```dart
  layouts.register('section', (context, node, children) => MySection(
        title: node['title'] as String?, children: children));
  ```

  - The core ships only a fallback: children in a column.
  - `formwork_material` ships Material builders for `section` and `row`.
- **Visibility.** A layout builder receives only the visible children. A
  node whose children are all hidden is not rendered.
- **Tolerance, for a catalog newer than the app.** Every rule renders
  something sensible and reports; none crashes.

  | Case | Behaviour |
  |---|---|
  | Unknown node type | children rendered in a column, reported |
  | Malformed node (no `children`, or not a list; an entry that is neither string nor object) | node skipped, reported; its fields fall to the end |
  | Field missing from `layout` | appended at the end, so a new field is never lost |
  | Key repeated in `layout` | rendered at its first place, reported |
  | Key not in the catalog | skipped, reported |
  | Key in the catalog but absent from this form on purpose (removed by `onlyMissing`, or dropped as an unsupported type, already reported) | skipped silently |

- **Both views render it.** `FormView` and `SnapshotFormView` both render
  the layout tree when there is one.
- **The same tree from code.** A `FormDef` can override
  `LayoutNode? get layout`, built with `SectionNode(...)` and
  `RowNode(...)`. These names avoid clashing with Flutter's `Row`. One
  model serves both front doors, as 0001 wants.

### 6. Keyed notification: what `FieldView` listens to

0002 stage 3 left this undesigned (its open question 4). A plain
`ValueNotifier` calls every listener on every change, so n `FieldView`s
would mean n calls per keystroke. That is the O(n) visit 0002 exists to
remove. So:

- **Per-field listenables.** The controller exposes
  `ValueListenable<FieldState> fieldState(FieldDef def)`, created lazily
  per field and cached.
- **Notified from `changedPaths`.** On each change, the controller
  notifies only the listenables of the fields whose `FieldState` changed
  (0001 §6).
- **Cost per keystroke:** O(changed fields), whatever the size of the
  form.
- **A form-level listenable remains** for whole-form UI: validity, the
  submit button, the helper of the backlog's UI-state doc.
- **The same fields also have form-level consumers.** The same
  `changedPaths` drives `BlocSelector` or `select` for Bloc and Riverpod
  users, as 0002 already says.

This amends 0002. Stage 3 is designed here and ships in the 0001
release, after stage 2 and measured separately, instead of shipping
alone.

## Alternatives considered

- **Code generation** (`build_runner`, annotated classes). It would remove
  more than the repeated key:
  - it would generate `fields`, so no member could be forgotten;
  - it would catch a key that does not match its member name.

  Lost on cost: a build step for every user, and generated files to keep
  in sync. The debug checks in §4 catch most of the same mistakes at run
  time. Dart macros, which would have done this without a build step,
  were discontinued in 2025.
- **String constants** (`const kIncome = 'income'`). They fix typos, but
  not types: conditions, validators and values stay untyped.
- **A builder DSL** (`form.text('income').min(1000)`). Fluent, but members
  of a class are what autocomplete and "go to definition" understand
  best, and a DSL still returns something you have to name.
- **Registration from inside the class**, to avoid listing `fields`.
  Lost: non-`late` initializers cannot call instance methods, and `late`
  members initialize on first access, so the order would be accidental.
- **Layout nodes mixed into `fields`** (`{"type": "section", ...}` among
  the fields). Lost: it mixes presentation into the data contract, and a
  backend would have to skip them.
- **Layout only in code.** Lost: server-driven forms, the package's main
  use case, need sections and rows too.

## Impact

- **Ships in the 0001 release.** It depends on:
  - 0001: `FieldDef<T>`, `FormDef`, `Condition`, `FieldState`;
  - 0002 stage 2: `changedPaths`;
  - 0004: `FieldProps`, `FormView`, `SnapshotFormView`.
- **Amends 0002.** Stage 3 is designed in §6 and ships with 0001, after
  stage 2 and measured separately.
- **Catalog format:** a new optional top-level `layout`.
  - It is additive: `FormConfig.fromMap` reads only `fields` and
    `schemaVersion`, so older apps ignore it.
  - Catalogs without it render as today.
  - `schemaVersion` stays 1, unless the 0001 changes raise it anyway.
- **Code:**
  - core:
    - condition helpers on `FieldDef`;
    - codecs, including decoding condition operands and `initialValues`;
    - the layout model (`LayoutNode`, `SectionNode`, `RowNode`) and its
      JSON parsing with the tolerance table.
  - widgets:
    - `FormScope`, `FieldView` (with `wrap`), `SnapshotFieldView`;
    - `LayoutRegistry`, and `registerDef`;
    - the controller's `fieldState` listenables.
  - `formwork_material`: section and row builders.
  - example: a scenario that lays out the profile form, and the catalog
    playground with a layout.
- **Tests, written first:**
  - **Compile-time checks:** fixtures under `test/compile_errors/`, which
    `analysis_options.yaml` excludes so `verify.sh` stays green. A test
    runs `dart analyze` on them and expects specific diagnostic codes:
    - `min(1000)` on a text field;
    - `equals('x')` on an enum field.
  - **Conditions:**
    - `equals(...)` builds the same `Condition` as `eq(...)`;
    - a JSON condition decoded through the field's codec equals the one
      built in code.
  - **Codecs:**
    - an enum round trip through the payload and `initialValues`;
    - a `DateTime` field without a codec throws when the form is built,
      in release mode too.
  - **Cycles:** mutually dependent `late` members fail when the form is
    built.
  - **Rebuilds** (`rebuild_test.dart`):
    - a `FieldView` rebuilds only its own field;
    - typing rebuilds no layout node;
    - a visibility flip rebuilds only the chain of enclosing nodes, not
      sibling sections;
    - changing the snapshot does not rebuild every `FieldView` under a
      `FormScope`.
  - **`wrap`:** a hidden field with `wrap` leaves no `Card` and no
    `Expanded`.
  - **Debug checks:** a field not in the form, a field placed twice, and a
    visible field placed nowhere are each reported.
  - **Layout tolerance:** every row of the table in §5.
  - **Visibility:** a section whose children are all hidden is not
    rendered.
  - **Equivalence:** the same form, built from JSON and from the class,
    produces equal snapshots.

## Open questions

1. **A lint for `fields`.** Is the explicit list plus the debug checks
   enough, or do we want a custom analyzer rule that flags a `FieldDef`
   member missing from `fields`?
2. **`visibleWhen` on layout nodes.** Should a section be able to have its
   own rule (hide the whole section), or is "all children hidden" enough?
3. **List items in layout.** 0001 leaves list UI to a later doc. Placing
   `FieldView`s for list items is decided there, not here.
4. **Names.** `FieldView` and `SnapshotFieldView` follow 0004's `FormView`
   and `SnapshotFormView`. They should be decided with 0004's open
   question 1 (two widgets or one).
5. **Where `localizer` and `enabled` live long term.** §4 puts them on
   `FormScope` and `FieldView`. Should they move into the controller, so
   Bloc users get them without a scope?
