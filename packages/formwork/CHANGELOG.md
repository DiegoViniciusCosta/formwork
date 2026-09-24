## Unreleased

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
