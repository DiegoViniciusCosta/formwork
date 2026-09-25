# 0008: Form status in the UI, and focus

Status: **draft**

## Problem

**Whole-form UI is hand-built today.** Take a submit button that shows
"Sending…", and a banner that reads "3 fields need attention":

```dart
ValueListenableBuilder<FormSnapshot>(
  valueListenable: controller,          // notifies on every keystroke
  builder: (context, s, _) => Column(children: [
    if (s.submitAttempted && !s.isValid)
      Text('${s.errors.length} fields need attention'),
    FilledButton(
      onPressed: sending ? null : onSubmit,  // `sending` lives in the app
      child: Text(sending ? 'Sending…' : 'Send'),
    ),
  ]),
)
```

- **It rebuilds on every keystroke,** although the button only cares about
  a few form-level facts.
- **The state lives outside the snapshot.** Each app keeps its own
  `sending` flag. Bloc and Riverpod users rebuild it once more.
- **Server errors have no way back in.** After `await api.save(payload)`,
  there is no API for applying the server's answer. Principle 3 promises
  it: "server-side errors are first-class".
- **Double taps submit twice.** Nothing stops a second `submit()` while
  the first is still sending.

**Focus is unreachable.** After a failed submit, the user should land on
the first field with an error. Builders get no `FocusNode` (0004's
`FieldProps` has none), and nothing knows which field widgets are
mounted. So an app cannot even do this by hand without keeping its own
map of nodes.

## Principles

- **Reinforces 3 (validation).**
  - Submitting and server errors become engine transitions on the
    snapshot, so they are deterministic and testable.
  - A server error that arrives for a value the user has since changed is
    stale, so it is discarded.
  - A second submit while one is running is ignored.
- **Reinforces 2 (rebuilds).**
  - Form-level UI listens to a small `FormStatus` that changes only when
    one of its facts changes. Typing in a valid field notifies nothing
    at form level.
  - Focus moving rebuilds no field, as PRINCIPLES.md §2 requires.
- **Reinforces 1 (agnostic).**
  - The status is in the snapshot, so `BlocSelector` and `select` read it
    like any other state.
  - Focus handling is a plain object the app can create. It does not
    depend on `FormController`.
- **Risk to 2:** a status computed per change must cost O(1), not
  O(fields). It reads counters that are kept up to date on each change,
  as 0002 stage 2 already plans for `isValid`.

## Decision

### 1. `FormStatus`: the form-level facts, in the snapshot

```dart
final class FormStatus {            // formwork_core, value equality
  final int errorCount;             // active fields with an error
  final int submitCount;            // submit attempts so far
  final bool submitting;
  final bool validating;            // any async validation pending
  final bool dirty;                 // any field differs from its initial value

  bool get isValid => errorCount == 0;
  bool get submitAttempted => submitCount > 0;
}

snapshot.status // O(1); the identical instance when nothing in it changed
```

- **Counts, not lists.** `errorCount`, and the counters behind `validating`
  and `dirty`, change by at most the number of fields a change touches.
  Lists of errors stay on the per-field state.
- **`errorCount` counts every active error, shown or not.** A banner
  usually shows only after a submit attempt: `if (status.submitAttempted
  && !status.isValid)`. Server errors for paths that never register are
  not counted: they do not block submit (0007, decided with acceptance).
  The snapshot keeps listing them.
- **`submitCount` is an edge, not only a flag.** A `BlocListener` or
  `ref.listen` reacts to "a new submit attempt happened" by comparing
  counts. A boolean cannot say that twice.
- **`validating`** is `false` until async validation ships. It is in the
  type now, as 0001 §6 did for `FieldState.validating`, so adding async
  validation later is not a breaking change.

### 2. Submitting: three engine transitions

```dart
var (:snapshot, :payload) = engine.submit(s);  // unchanged: marks the attempt
if (payload != null) {
  snapshot = engine.startSubmitting(snapshot);  // status.submitting = true
  final serverErrors = await api.save(payload); // the app's own I/O
  snapshot = engine.completeSubmit(snapshot, serverErrors: serverErrors);
}
```

- **`submit` keeps its 0004 meaning.** It marks the attempt, increments
  `submitCount`, and returns the payload when valid. A form that sends
  synchronously, or does not track sending, never calls the other two
  transitions.
- **While `submitting`, `submit` returns the identical snapshot and no
  payload.** This is the double-tap guard.
- **`completeSubmit(s, serverErrors: {path: ValidationError})`** clears
  `submitting` and applies the server errors with `source: server`
  (0001 §2).
  - If the user changed a field after `startSubmitting`, its server error
    refers to a value that is gone, so it is discarded. This is principle
    3's race-free rule applied to the server.
  - A path that is not registered keeps its error until it registers
    (0007 §6).
  - A server error clears the next time its field changes, like any other
    error.
- **The engine does no I/O.** Sending, retries and timeouts stay in the
  app. The engine only records what the app reports.

The controller wraps the whole sequence for apps that use it:

```dart
final ok = await controller.submitWith((payload) => api.save(payload));
// save returns the server errors, or null when accepted.
```

`submitWith` also moves focus to the first error (§4) when validation or
the server rejects the payload. If `send` throws, it calls
`completeSubmit` with no errors and rethrows, so the form never stays in
`submitting`. `controller.submit()` stays as 0004 defines it.

### 3. Listening to the status

```dart
FormStatusBuilder(
  builder: (context, status) => FilledButton(
    onPressed: status.submitting ? null : () => controller.submitWith(save),
    child: Text(status.submitting ? 'Sending…' : 'Send'),
  ),
)
```

- **`controller.status`** is a `ValueListenable<FormStatus>` that notifies
  only when the status changes. It is 0006 §6's form-level listenable,
  narrowed.
- **`FormStatusBuilder`** takes `controller:` explicitly, or reads it from
  `FormScope`, like `FieldView` does (0006 §4).
- **Bloc and Riverpod:** `BlocSelector((s) => s.status)` or
  `select((s) => s.status)`. Nothing new is needed.
- **Disabling fields while sending** stays the app's choice, through the
  view-level `enabled` of 0006 §4: `FormScope(enabled:
  !status.submitting)`. It rebuilds every field once, which is correct:
  every field's `enabled` changed.

### 4. Focus: a node per field, and a `FormFocus`

**`FieldProps` gains `focusNode`:**

```dart
final class FieldProps<T> {
  ...
  final FocusNode focusNode; // owned by the FieldView; stable across builds
}

'text': (context, field) => TextField(focusNode: field.focusNode, ...),
'rating': (context, field) => Focus(focusNode: field.focusNode, child: ...),
```

- **`FieldView` creates the node** in its `State`, disposes it on
  unmount, and keeps the same node across rebuilds. Its identity never
  changes while the field is mounted, so it adds nothing to 0004's cache
  contract.
- **A builder whose component takes no `FocusNode`** wraps it in `Focus`,
  as above. `formwork_material` wires every builder.
- **Focus is not in `FieldProps` as a value.** A builder that styles on
  focus listens to the node itself. Moving focus therefore rebuilds no
  `FieldView`.

**`FormFocus` knows which fields are mounted:**

```dart
final focus = FormFocus(); // widgets layer; no controller needed

SnapshotFormView(..., focus: focus);  // or FormScope(focus: focus)
focus.requestFirstError(snapshot);    // true if it moved focus
```

- **`FieldView` and `SnapshotFieldView` register their node** with the
  `FormFocus` they get from `FormScope` or from `focus:`. They unregister
  on unmount. Registering rebuilds nothing.
- **`FormController` owns one** (`controller.focus`), and `FormScope` uses
  it by default. Bloc and Riverpod users create one and pass it.
- **"First" means registration order,** which is the order of the
  payload and of `FormView` without a layout (0006 §1, 0007 §2). The
  engine computes it: `snapshot.firstErrorPath`, among the active fields
  that show an error.
- **Unmounted fields are skipped.** `requestFirstError` focuses the first
  field with an error that is mounted. It scrolls to it with
  `Scrollable.ensureVisible`, then requests focus. If no field with an
  error is mounted, it returns `false`, and in debug mode it reports the
  paths. That matches 0006 §4's "visible fields placed nowhere" check.
- **Bloc users** call it from a `BlocListener` that fires when
  `submitCount` grows and `isValid` is false. The focus call stays in the
  UI, not in the bloc.

## Alternatives considered

- **`submitting` held in the controller,** outside the snapshot. It is
  simpler, but it breaks the rule that validation state lives in the
  snapshot, and Bloc users get nothing. Lost.
- **`submit()` becomes async and sets `submitting` itself.** Lost: it
  breaks 0004's synchronous `submit()`, and it puts I/O in the flow of
  forms that do not need it. The three transitions keep it opt-in.
- **Disable the submit button while the form is invalid, by default.** It
  is a common pattern, but it hides why the button does nothing, and the
  user never learns which field is wrong. `FormStatus` gives the facts
  and leaves the UX to the app.
- **Screen order for "first error"** (topmost render box, then leading
  edge). It follows custom layouts, but it depends on a layout pass, on
  text direction and on screen width (a row that wraps on a phone), so the
  same form could focus different fields on different devices. It is also
  harder to test. Registration order is deterministic and computed in the
  engine. Apps whose screen order differs can reorder `fields`.
- **A focus registry inside `FormController`.** It fits the default
  path, but `SnapshotFormView` users have no controller. `FormFocus` is
  the same thing as a standalone object, and the controller just owns
  one.
- **`hasFocus` in `FieldProps`.** It is convenient for styling, but every
  focus move would rebuild two fields, which PRINCIPLES.md §2 forbids.

## Impact

**Amends accepted docs.**

| Doc | What changes |
|---|---|
| 0001 | §2: server errors enter through `completeSubmit`. The snapshot gains `status` and `firstErrorPath`. |
| 0004 | `FieldProps` gains `focusNode`. The cache contract is unchanged. `controller.submit()` is unchanged, and `submitWith` is added. `submit` ignores a call while submitting. |
| 0006 | §4: `FieldView` owns a `FocusNode`. `FormScope` and the field views take `focus:`. §6: the form-level listenable is `controller.status`. |
| 0007 | §6: server errors for registered paths are applied by `completeSubmit`, and discarded when the field changed during the submit. |

**Code.**
- `formwork_core`:
  - `FormStatus`, with its counters kept up to date on each change;
  - `startSubmitting` and `completeSubmit`;
  - `firstErrorPath`.
- `formwork`:
  - `controller.status` and `submitWith`;
  - `FormStatusBuilder` and `FormFocus`;
  - `focusNode` in `FieldProps`.
- `formwork_material`: every builder passes `focusNode`.
- The example: the external-state scenario (Bloc-like) uses `submitCount`
  and `FormFocus`, and one scenario shows a submit button with "Sending…"
  and server errors.

Ships in the foundation release (backlog item 4), with 0001 and 0004. It
is not breaking beyond what that release already breaks.

**Tests, written first.**
- **Status:**
  - typing in a valid field returns the identical `status`;
  - `errorCount` matches a full count after random change sequences (an
    equivalence test, like principle 3's);
  - the cost stays flat: the same counter work at 10 and 10,000 fields.
- **Submitting:**
  - a submit while submitting returns the identical snapshot and no
    payload;
  - `completeSubmit` applies server errors and clears `submitting`;
  - a server error for a field changed during the submit is discarded;
  - `submitWith` completes the submit when `send` throws, and rethrows.
- **Rebuilds** (`rebuild_test.dart`):
  - typing in a valid field does not rebuild a `FormStatusBuilder`;
  - moving focus between fields rebuilds no `FieldView`;
  - registering focus nodes rebuilds nothing.
- **Focus:**
  - a failed submit focuses the first field with an error in registration
    order;
  - an unmounted field with an error is skipped;
  - with no mounted field in error, it returns `false` and reports in
    debug;
  - the same flow through `SnapshotFormView` with a standalone
    `FormFocus`.

## Open questions

1. **Name of `submitWith`.** Alternatives: `send`, `submitAndSend`,
   `submitAsync`. It should read well next to `submit()`.
2. **Touched on blur.** With a `FocusNode` per field, a field could be
   marked touched when it loses focus, so its errors show on blur instead
   of on the first change (0004 kept today's meaning of `touched`). Is
   that a validation mode worth adding, and in which release?
3. **Server errors for unregistered paths in the status.** Should
   `FormStatus` count them separately (`unplacedErrorCount`), so a banner
   can mention them, or is the list on the snapshot enough?
