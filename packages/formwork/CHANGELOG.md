## Unreleased

- **Breaking:** the widgets follow the foundation (design docs 0001,
  0004, 0006 §4 and §6, and 0007):
  - `FormController(form, initialValues:)` replaces
    `DynamicFormController`; `change` takes a `FieldPath`. It notifies each
    field only when that field's state changes (`fieldState(def)`), and
    exposes `status` for form-level UI.
  - `FormView` and `SnapshotFormView` replace `DynamicForm` and
    `DynamicFormView`.
  - `FieldProps<T>` replaces `FieldContext`: builders take
    `(context, props)`, and read the definition from `props.def` and the
    raw error from `props.error`. `FieldRegistry.registerDef<D, T>`
    registers a builder for a definition class, typed.
  - New: `FieldView` places one field anywhere in a layout, with an
    optional per-view `builder:` and a `wrap:` built only while the field
    is visible; `FormScope` provides the controller, registry, localizer
    and `enabled` below it; `SnapshotFieldView` does the same for Bloc and
    Riverpod. Debug builds report a `FieldView` for a field not in the
    form, a field shown twice, and a visible field no `FieldView` shows.
  - Error text comes from an `ErrorLocalizer`, English by default.
- **Breaking:** the engine moved to a new pure Dart package,
  `formwork_core` (design doc 0007), so a Dart backend can validate the
  same catalogs without Flutter. `package:formwork/formwork.dart`
  re-exports it, so Flutter apps change nothing.
  `package:formwork/core.dart` is gone: import
  `package:formwork_core/formwork_core.dart` instead, and list
  `formwork_core` in your `pubspec.yaml`.
- **Breaking:** `TextControllerBinding` is now generic and follows the
  value (design doc 0005). It takes `value`, `onChanged`, and optional
  `parse` and `format`, instead of `initialText`; its builder gets a third
  argument, `onTextChanged`, to wire to the input. The text is kept while
  it still means the value, so typing is untouched, and replaced when the
  value comes from outside: undo, reset, state restored by Bloc or
  Riverpod.
- Added `missingKeys`: the keys a user still has to answer, without
  hiding anything, for apps that show the whole form and highlight what
  is missing (design doc 0003).
- Fixed: `missingFields` could hide a known field in the middle of a
  `visibleWhen` chain, so the engine lost the link. Answering "no" at the
  top of the chain left fields below it required, and submit was blocked.
  Such a field is now kept, prefilled when you pass the same data to the
  engine. `missingFields` may therefore return a field whose value is
  already known.
- Faster `FormEngine.change`: the new snapshot copies `values` once
  instead of twice, and shares the previous `errors` map when no error
  changed. About 4x faster per keystroke on large forms. Snapshot maps are
  now `UnmodifiableMapView`s; they stay read-only.
- Fixed: `FormSnapshot.touched` was a mutable `Set`. Adding to it changed
  every snapshot sharing it. It is now read-only: mutating it throws
  `UnsupportedError`.
- Fixed: `visibleWhen` now follows chains. When a field is hidden, every
  field whose rule reads it, directly or through other fields, is hidden
  too, in `FormEngine` and in `missingFields`. Before, a dependent could
  stay visible and required under a hidden controller and block submit.

## 0.1.0

- Initial release: field catalog parsing, validators, `missingFields`,
  `FormEngine`, `DynamicFormView` with per-field rebuilds, Material builders.
