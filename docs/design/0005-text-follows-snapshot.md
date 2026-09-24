# 0005: Text fields follow the snapshot

Status: **accepted** (2026-09-23)

## Problem

When a value changes from outside a text field, the field keeps showing
the old text. Examples of an outside change:
- undo;
- reset;
- "fill sample";
- data loaded from a server after the form opened;
- a Bloc or Riverpod state restored.

The snapshot is right, and the screen is wrong.

```dart
controller.change('name', 'Bruno');   // snapshot: 'Bruno'
// TextField still shows 'Ana'
```

- **Only text inputs are affected.** A probe with `formwork_material`
  shows the text and number fields keep their old text, while the
  dropdown and the checkbox follow the snapshot.
- **The cause is `TextControllerBinding`.** It creates its
  `TextEditingController` once, from `initialText`, and its dartdoc says
  "Later changes are ignored". That was deliberate: recreating the
  controller on every rebuild breaks the cursor.
- **Every design system inherits the bug.** The binding is the helper we
  tell builder authors to use (`formwork_material/AGENTS.md`).
- **It is visible today.** The example scenario "External state & undo"
  shows it, and its test "text fields follow values set from outside" is
  skipped.

This breaks principle 1's promise. With Bloc, Riverpod or any external
state, the snapshot is supposed to be the single source of truth, but
for text fields it is not.

## Principles

- **Reinforces 1 (agnostic).** The snapshot becomes the source of truth
  for every field type, with any state management, and every design
  system using the binding gets the fix for free.
  - **Assumption:** the adapter applies each change before the next one
    arrives. See Known limits.
- **Neutral on 2 (rebuilds).** No new rebuilds. The binding reacts only
  when its field already rebuilds, because its value, displayed error or
  `enabled` changed.
- **Neutral on 3 (validation).** Values and errors are untouched; only
  what the text box shows changes.

## Decision

### The rule: keep the text while it still means the value

When the field rebuilds, the binding keeps the current text, with its
cursor, selection and composition, if either of these holds:

1. `parse(text) == value`: the text means the value. This is the case
   while the user types, because the value came from this very text.
2. `text == format(value)`: the text is already how the value is shown.
   This covers an untouched empty field, where the value is `null` and
   the text is `''`, and any value whose `parse(format(v))` is not `v`:
   - server data of the wrong type;
   - `NaN`;
   - custom types without `==`.

Otherwise the value came from outside. The binding replaces the text with
`format(value)` and puts the cursor at the end.

Checking the second condition is what keeps an error-only rebuild (a
submit showing "required") from touching the text.

Why not only the second condition? The user's text often differs from
the formatted value while meaning the same thing:

| User typed | Value after `parse` | `format(value)` | Condition 2 alone would |
|---|---|---|---|
| `-` | `null` | `''` | erase the minus: negative numbers cannot be typed |
| `1.50` | `1.5` | `1.5` | drop the zero while typing `1.505` |
| `1,5` | `1.5` | `1.5` | swap the comma under the cursor |

Condition 1 keeps all three.

**Invariant for authors.** `parse(format(v)) == v` for every value the
field can hold. Condition 2 tolerates values that break it, but they are
then never rewritten while their text stays the same.

**Equality is Dart's `==`.** `41 == 41.0`, so an outside `41` leaves the
typed `41.0` on screen. The per-field cache uses the same `==`, so that
case does not even rebuild. This is acceptable: the text still means the
value.

### API

The binding owns `parse`, `format` and the conversion in `onChanged`, so
each conversion has one source. The builder gets a ready callback for
text:

```dart
TextControllerBinding<num>(
  value: ctx.value as num?,
  parse: (text) => num.tryParse(text.replaceAll(',', '.')),
  onChanged: ctx.onChanged,
  builder: (context, controller, onTextChanged) => TextField(
    controller: controller,
    onChanged: onTextChanged, // parses, then calls ctx.onChanged
  ),
)
```

- **Generic now**, in the shape 0004 will need: `T? value`,
  `T? Function(String) parse`, `String Function(T?) format`,
  `ValueChanged<T?> onChanged`. Today builders use `T = Object` or a
  narrower type, since `FieldContext.value` is `Object?`. After 0001 and
  0004, `FieldProps<T>` feeds it directly, and the binding does not break
  a second time.
- **Defaults:** `parse` returns the text; `format` is `toString`, with
  `null` shown as `''`. A plain text builder passes neither.
- **Controller:** created once, never recreated, so the cursor survives
  every rebuild.
- **No echo:** replacing the text does not call `onChanged`. Setting a
  controller does not fire `TextField.onChanged`, and a test pins it.
  Otherwise every outside change would come back as an extra engine
  change.

### Where it happens

In the binding's `didUpdateWidget`:
- It runs only when the per-field cache already missed.
- Setting the controller notifies only listeners below the binding
  (`EditableText`, `UndoHistory`). They are descendants being built in
  the same frame, so Flutter's setState-during-build assertion allows it.
- The controller is private, so no outside listener can be affected.

### Known limits

- **The adapter must apply changes in order, without lag.**
  `DynamicFormController` does, and so does a Bloc or Riverpod handler
  that updates synchronously. A throttled or async adapter can deliver an
  old value after the user typed more. Example:
  - the user types `ab`, but the state still holds `a`;
  - the rule sees an outside change and resets the text to `a`;
  - a keystroke is lost.

  See "Decided with acceptance", item 2.
- **Normalizing in `onChanged` is not supported.** If an app trims or
  uppercases the value on every keystroke, the value stops meaning the
  text. The text is replaced, and typing breaks (a trim makes spaces
  between words impossible). Normalize at submit time, or in the payload,
  instead.
- **A reset that does not change the value keeps stale text.** If the
  text is `-` (value `null`) and the app resets to `null`, nothing
  changed. The field does not rebuild, and `-` stays. This is harmless:
  the value is right, and the text is an unfinished entry.

## Alternatives considered

- **Condition 2 alone** (replace the text when it differs from
  `format(value)`). Lost: it breaks typing, as the table shows.
- **Remember the last value the field emitted**, and ignore that echo.
  - It works for plain typing.
  - It tolerates lag better, if it remembers every pending value and not
    only the last one.
  - It fails when the app transforms `onChanged`, because the value that
    comes back was never emitted.
  - Lost for now: it adds mutable state per field. It is the candidate
    if lagging adapters need handling later.
- **Mark outside changes in the engine** (`change(..., fromUser: false)`,
  or a revision counter in `FieldContext`). Lost:
  - it adds engine and `FieldContext` API for something only text inputs
    need;
  - the controller cannot tell who is "outside", because a Bloc event and
    a keystroke both end up as `change`.
- **Remount on reset** (the app changes the form's `Key`). It works
  today, with no library change. Lost as the answer:
  - every app has to discover it;
  - it destroys every field's state;
  - it does not cover undo of one field, or state restored by Bloc.
- **No persistent controller.** Lost: the cursor jumps on every keystroke,
  which is what the binding exists to prevent.

## Impact

- **Breaking:** `TextControllerBinding(initialText:, builder:)` becomes
  `TextControllerBinding<T>(value:, parse:, format:, onChanged:,
  builder:)`, and the builder gets a third argument.
  - 0.1 is unpublished (0004), so this is a clean break, and nobody
    migrates.
  - It ships now rather than with 0001: it fixes a visible bug, no user
    pays for a second migration, and the generic shape already fits 0004.
- **Code and docs:**
  - `packages/formwork/lib/src/flutter/text_controller_binding.dart`, and
    its dartdoc ("Later changes are ignored" goes);
  - the `_text` builder in `formwork_material`, which moves `parse` into
    the binding;
  - `packages/formwork/README.md`, whose custom-field section uses
    `initialText:`;
  - the example scenario "External state & undo": its caveat and
    "KNOWN BUG" note go, and its skipped test is unskipped.
- **CHANGELOG:** entries in both packages.
- **Tests, written first, on the binding alone:**
  - an outside value replaces the text, with the cursor at the end;
  - typing `-`, `1.50` and `1,5` in a number field keeps the text;
  - typing in the middle keeps the cursor where it is;
  - an error-only rebuild of an empty, untouched field keeps the
    selection and the composition (the `''` and `null` case);
  - an outside value of the wrong type (the string `'41'` in a number
    field) is not rewritten on later rebuilds;
  - replacing the text does not call `onChanged`;
  - reset to `null` while the text is `-` keeps `-` (a known limit, pinned
    by a test);
  - an adapter that delivers values late reverts typed text (a known
    limit, pinned by a test).
- **Tests on rebuilds:** `rebuild_test.dart` already proves an outside
  change rebuilds only its field. A new test checks the binding runs no
  extra builds of its own.
- **Tests in the example:** undo, reset and "fill sample" in "External
  state & undo" update the text.

## Decided with acceptance

1. **IME composition:** accepted. An outside change that arrives while the
   user is composing drops the composition, because an outside change and
   typing at the same instant are rare.
2. **Lagging adapters:** not handled now. The "pending echoes" variant
   stays documented above, for when a real adapter needs it. The limit is
   pinned by a test.
