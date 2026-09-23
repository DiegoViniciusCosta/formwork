# 0004: Public API names and shape

Status: **draft**

## Problem

The API works, but it reads worse than it should. From building the
example gallery and reviewing it:

- **"Dynamic" everywhere.** `DynamicForm`, `DynamicFormView` and
  `DynamicFormController` repeat an adjective that is true of the whole
  package. AGENTS.md asks for domain names, and "dynamic" is neither
  domain nor distinguishing.
- **Two "contexts" in every builder.** A builder is
  `(BuildContext context, FieldConfig field, FieldContext ctx)`: three
  parameters, two of them called context. Every reference builder in
  `formwork_material` abbreviates the third one to `x`.
- **Errors that are not what they seem.**
  - `snapshot.errors` holds every current error, including the ones not
    shown yet.
  - `snapshot.errorFor(key)` is the one on screen.
  - Early in this project we had to read the code to explain why errors
    did not show.
- **`touched` means "changed at least once".** It is set on the first
  change, not on focus loss.
- **Duplicates and misplaced members.**
  - `engine.visibleFields(s)` returns `s.visibleFields`.
  - `engine.payloadOf(s)` needs nothing but the snapshot.
- **One idea, three names.** The same data is `userData` in
  `missingFields`, `initialData` in the controller and `initial()`, and
  `values` in the snapshot.
- **Hard to discover.** `missingFields` is a top-level function. Nobody
  finds it from autocomplete on the form.

Other docs already own part of this surface, and this doc does not touch
it:
- **0001 renames the model:** `FieldConfig` → `FieldDef<T>`, `FormConfig`
  → `FormDef`, `VisibilityRule` → `Condition`, string errors →
  `ValidationError`.
- **0001 §6 replaces per-field snapshot state** with `FieldState`
  (`value`, `error`, `visible`, `enabled`, `required`, `touched`, `dirty`,
  `validating`).
- **0002 decides the snapshot surface** (open question 2: `Map` views or
  `FieldState` accessors).

## Principles

- **Reinforces 1 (agnostic).** The builder contract is what every design
  system implements. Making it one complete object is the biggest
  usability win for people writing their own builders.
- **Neutral on 2 (rebuilds),** provided the cache contract below holds.
- **Neutral on 3 (validation).** No rule changes.
- **Risk: churn.** Renaming twice (now, then again for 0001) is the worst
  outcome. See Order and migration.

## Decision

### Before and after

The Quick start today:

```dart
final pending = missingFields(catalog, userData, validators: validators);
final controller = DynamicFormController(
  FormEngine(config: pending, validators: validators),
  initialData: userData,
);
DynamicForm(controller: controller, registry: registry);
final payload = controller.submit();
```

The same flow after this doc and 0001. Validators live on each `FieldDef`
(0001 §3), so none are passed around:

```dart
final form = catalog.onlyMissing(data);
final controller = FormController(FormEngine(form), initialValues: data);
FormView(controller: controller, registry: registry);
final payload = controller.submit();
```

A builder today, then after:

```dart
'text': (context, field, ctx) => TextField(
      decoration: InputDecoration(
        labelText: field.label,
        errorText: ctx.errorText,
      ),
      onChanged: ctx.onChanged,
    ),

'text': (context, field) => TextField(
      decoration: InputDecoration(
        labelText: field.def.label,
        errorText: field.errorText,
      ),
      onChanged: field.onChanged,
    ),
```

### `FieldProps`: the whole builder contract

One object replaces the `FieldConfig` + `FieldContext` pair. Its fields
follow 0001 §2 and §6:

```dart
final class FieldProps<T> {
  final FieldDef<T> def;
  final T? value;
  final ValidationError? error; // raw, for design systems (0001 §2)
  final String? errorText;      // localized, displayed now
  final bool enabled;           // field rule and view-level flag combined
  final bool required;
  final bool validating;
  final ValueChanged<T?> onChanged;
}
```

**Cache contract.** A field rebuilds when its `FieldProps` would change.
Concretely, the view compares:
- the identity of the field's `FieldState` (0001 §6);
- the view-level `enabled` flag, which is not in `FieldState`;
- the localizer.

Whether the error is displayed depends on `touched` and `submitAttempted`.
A submit changes it for every field with an error, and the engine
reflects it in those fields' `FieldState`. A `def` change needs no check:
it only comes with a new engine, which clears the cache.

### Renames and moves

| Today | Proposed | Why |
|---|---|---|
| `DynamicFormController` | `FormController` | Domain name; "dynamic" adds nothing |
| `DynamicForm` | `FormView` | The common case gets the short name |
| `DynamicFormView` | `SnapshotFormView` | Says what it takes: a snapshot and a callback, for Bloc, Riverpod and others |
| `FieldContext` + `FieldConfig` args | `FieldProps<T>` | One complete object; no clash with `BuildContext` |
| `FieldBuilder = (context, field, ctx)` | `FieldBuilder = (context, props)` | Follows from `FieldProps` |
| `FieldRegistry.build(context, field, ctx)` | `FieldRegistry.build(context, props)` | Same |
| `engine.payloadOf(s)` | `snapshot.payload()` | Needs only the snapshot. A method, not a getter: it allocates, and after 0001 it maps list ids to indexes |
| `engine.visibleFields(s)` | removed | Duplicate of `snapshot.visibleFields` |
| `FormEngine(config: x)` | `FormEngine(x)` | The form is the only required input |
| `initialData` / `userData` | `initialValues` | Pairs with `snapshot.values` |
| `missingFields(catalog, data)` | `catalog.onlyMissing(data)` | Extension method in the recipe library: found by autocomplete, but not a member of `FormDef` |
| `missingKeys(catalog, data)` (0003) | `catalog.missingKeys(data)` | Same |

The two missing-data methods are **extensions** in their own library, not
members of `FormDef`. They stay a recipe, as PRINCIPLES.md and 0003 ask,
and still show up in autocomplete once the library is imported.

### Not renamed here

- **`errors`, `errorFor`, `touched`.** They become per-field state in 0001
  §6 (`FieldState.error`, `touched`, `dirty`), and the displayed error
  becomes `FieldProps.errorText`. Renaming them now would change their
  meaning again later: today's `touched` is "changed at least once",
  while `dirty` usually means "differs from the initial value". Their
  future is decided by 0001 §6 and 0002 open question 2.
- **`FormEngine`, `FormSnapshot`, `SubmitResult`.** Clear, domain-named.
- **`FieldRegistry` with `register` / `registerAll` / `types`.** Small and
  obvious.
- **`ValidatorRegistry`.** Its shape changes with 0001's typed validators.
- **`FieldOption`, `schemaVersion`, `extra`.** Fine as they are.
- **`TextControllerBinding`.** Accurate for builder authors. Its behaviour
  with values set from outside is a separate issue.
- **`materialFieldRegistry()`.** Reads well. `materialFieldBuilders`
  changes signature with `FieldBuilder`, but keeps its name.

### Order and migration

1. **0003 first**, on today's names. It is not breaking.
2. **0004 together with 0001**, in one breaking release. Users migrate
   once.

**0.1 is unpublished**, so step 2 is a clean break, as 0001 plans: no
deprecated aliases and no migration guide. This was checked on pub.dev on
2026-09-23: neither `formwork` nor `formwork_material` exists, so both
names are also still free.

## Alternatives considered

- **Keep the names, document better.** Lost: docs cannot fix a builder
  signature with two contexts.
- **Rename now, before 0001.** Lost: users would migrate twice.
- **One widget with two constructors** (`FormView(controller:)` and
  `FormView.snapshot(...)`). Fewer names, but one class with two sets of
  nullable fields is harder to read and document. Kept as an open
  question.
- **Prefix everything** (`FwForm`, `FormworkController`). Avoids clashes
  with app code, but reads like mechanism. Dart's import prefixes already
  solve clashes for apps that have them. None of the proposed names clash
  with Flutter; `Form`, `FormState`, `FormField*` and `FormFieldBuilder`
  do, and are not used.
- **Missing-data methods as members of `FormDef`.** Most discoverable,
  but they turn a recipe into core model API. Extensions give the same
  autocomplete.

## Impact

- **Breaking**, bundled with 0001.
- **Code:**
  - `packages/formwork/lib` (all public files);
  - `packages/formwork_material` (every builder, to the new signature);
  - `packages/formwork/example`;
  - both READMEs;
  - every test.
- **Rules that name `FieldContext`:**
  - PRINCIPLES.md §1;
  - `packages/formwork/AGENTS.md`;
  - `packages/formwork_material/AGENTS.md`.

  They must say `FieldProps`. PRINCIPLES.md changes need a human.
- **CHANGELOG:** one entry, with the rename table, which is enough for a
  package that was never published.
- **Tests:**
  - every existing test passes after a mechanical rename;
  - the rebuild tests prove the cache contract;
  - a new rebuild test: a submit rebuilds exactly the fields whose
    displayed error changed, under `FieldState` identity.

## Open questions

1. **Two widgets or one?** `FormView` + `SnapshotFormView`, or one
   `FormView` with a named constructor.
2. **`FieldProps` or another name?** Candidates: `FieldProps` (familiar
   from React), `FieldBinding`, `FieldHandle`. And should it be generic
   (`FieldProps<T>`, matching `FieldDef<T>`) or untyped?
3. **`initialValues` or `data`?** `initialValues` pairs with
   `snapshot.values`, but the map also carries user data outside the form,
   which feeds visibility rules and is never shown.
