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
- **The server's answer has no way back in.** After
  `await api.save(payload)`, there is no API for applying the answer.
  Principle 3 promises that "server-side errors are first-class".
  - Some answers belong to a field ("this e-mail is taken").
  - Others belong to the whole form ("wrong e-mail or password").
  - Some are a success the UI wants to confirm ("Saved").
- **Double taps submit twice.** Nothing stops a second `submit()` while
  the first is still sending.

**Focus is unreachable.** After a failed submit, the user should land on
the first field with an error. Builders get no `FocusNode` (0004's
`FieldProps` has none), and nothing knows which field widgets are
mounted. So an app cannot even do this by hand without keeping its own
map of nodes.

**How competitors handle it** (checked on 2026-09-25):

| | Form status | "Sending" | Server errors | Focus on first error |
|---|---|---|---|---|
| Flutter `Form` | none: `validate()` returns a `bool` | none | `forceErrorText` on a field (text) | none |
| flutter_form_builder 11.0.0 | `isValid`, `isDirty`, `isTouched` (each walks every field) | none | `invalidate('…', shouldFocus: true)` (text) | `validate(focusOnInvalid: true)` by default, in mount order; scrolling off by default |
| reactive_forms 18.2.2 | `valid`, `pending`, `dirty` per control; the consumer rebuilds on validity changes | none | `setErrors`, overwritten by the next validation | none; `control.focus()` lives on the model |
| react-hook-form | `formState`: `submitCount`, `isSubmitSuccessful`, … | `isSubmitting` | per field, and `root.serverError` for the form | `shouldFocusError`, in `register` order |

No Flutter package has a "sending" state, a form-level error, or error
data from the server. react-hook-form has the closest model, and this doc
follows it where it fits Dart.

## Principles

- **Reinforces 3 (validation).**
  - Submitting and the server's answer become engine transitions on the
    snapshot, so they are deterministic and testable.
  - A server error that arrives for a value the user has since changed is
    stale, so it is discarded.
  - A second submit while one is running is ignored.
- **Reinforces 2 (rebuilds).**
  - Form-level UI selects the facts it reads from a small `FormStatus`,
    and rebuilds only when those change. Typing in a valid field notifies
    nothing at form level.
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
  final ValidationError? formError; // the server's answer for the whole form
  final int submitCount;            // submit attempts so far
  final bool submitting;
  final SubmitOutcome? lastSubmit;  // how the last send ended; null if none
  final bool validating;            // any async validation pending
  final bool dirty;                 // any field differs from its initial value

  bool get isValid => errorCount == 0;
  bool get submitAttempted => submitCount > 0;
}

enum SubmitOutcome { accepted, rejected, abandoned }

snapshot.status // O(1); the identical instance when nothing in it changed
```

- **Counts, not lists.** `errorCount`, and the counters behind `validating`
  and `dirty`, change by at most the number of fields a change touches.
  Lists of errors stay on the per-field state.
- **`errorCount` counts every active field error, shown or not.** A banner
  usually shows only after a submit attempt: `if (status.submitAttempted
  && !status.isValid)`.
  - Server errors for paths that never register are not counted: they do
    not block submit (0007, decided with acceptance). The snapshot keeps
    listing them.
  - `formError` is not counted either (§2).
- **`submitCount` is an edge, not only a flag.** A `BlocListener` or
  `ref.listen` reacts to "a new submit attempt happened" by comparing
  counts. A boolean cannot say that twice.
- **`lastSubmit`** says how the last send ended (§2), so the UI can show
  "Saved" or "Could not send, try again".
- **`validating`** is `false` until async validation ships. It is in the
  type now, as 0001 §6 did for `FieldState.validating`, so adding async
  validation later is not a breaking change.

### 2. Submitting: engine transitions

```dart
var (:snapshot, :payload) = engine.submit(s);  // unchanged: marks the attempt
if (payload != null) {
  snapshot = engine.startSubmitting(snapshot);  // submitting = true
  try {
    final ServerErrors? answer = await api.save(payload); // the app's I/O
    snapshot = engine.completeSubmit(snapshot, answer);
  } catch (_) {
    snapshot = engine.abandonSubmit(snapshot);
  }
}
```

```dart
final class ServerErrors {          // formwork_core
  final Map<FieldPath, ValidationError> fields;
  final ValidationError? form;      // "wrong e-mail or password"
}
```

- **`submit` keeps its 0004 meaning.** It marks the attempt, increments
  `submitCount`, and returns the payload when valid. A form that sends
  synchronously, or does not track sending, never calls the other
  transitions.
- **While `submitting`, `submit` returns the identical snapshot and no
  payload.** This is the double-tap guard. None of the competitors has
  one in the library; they leave it to a disabled button.
- **`startSubmitting`** sets `submitting`, and clears `formError` and
  `lastSubmit` from the previous send.
- **`completeSubmit(s, answer)`** clears `submitting`.
  - **`null`, or no errors:** `lastSubmit` is `accepted`.
  - **Otherwise** it is `rejected`, and the errors are applied with
    `source: server` (0001 §2):
    - **Field errors:**
      - If the user changed a field after `startSubmitting`, its error
        refers to a value that is gone, so it is discarded. This is
        principle 3's race-free rule applied to the server; none of the
        competitors does it.
      - A path that is not registered keeps its error until it registers
        (0007 §6).
      - A field error clears the next time its field changes, like any
        other error.
    - **The form error** goes to `status.formError`. It does not block
      the next submit: there is no field to fix, and blocking would be a
      dead end. It clears on the next `startSubmitting`.
- **`abandonSubmit`** clears `submitting` and sets `lastSubmit` to
  `abandoned`. It applies nothing. This covers a send that fails without
  an answer (a network error, a timeout) or that the user cancels. It is
  not the same as `rejected`: the data may be fine, and trying again
  makes sense.
- **The engine does no I/O.** Sending, retries and timeouts stay in the
  app. The engine only records what the app reports.

The controller wraps the whole sequence for apps that use it:

```dart
final outcome = await controller.submitWith((payload) => api.save(payload));
// save returns ServerErrors, or null when the server accepted.
```

- It returns `null` when validation stopped the submit before sending, and
  the `SubmitOutcome` otherwise.
- It moves focus to the first field error (§4) when validation or the
  server rejects the payload.
- If `send` throws, it calls `abandonSubmit` and rethrows, so the form
  never stays in `submitting`.
- `controller.submit()` stays as 0004 defines it.

### 3. Listening to the status: select what you read

```dart
FormStatusBuilder(
  select: (s) => s.submitting,
  builder: (context, submitting) => FilledButton(
    onPressed: submitting ? null : () => controller.submitWith(save),
    child: Text(submitting ? 'Sending…' : 'Send'),
  ),
)

FormStatusBuilder(
  select: (s) => (s.submitAttempted, s.errorCount, s.formError),
  builder: (context, v) => ErrorBanner(...),
)
```

- **`FormStatusBuilder<R>(select:, builder:)`** rebuilds only when the
  selected value changes, compared with `==`. Records compare by value, so
  selecting several facts is one line. `select: (s) => s` takes the whole
  status. This is react-hook-form's per-property subscription, made
  explicit: Dart has no `Proxy`, and an explicit `select` can be read and
  tested.
- **`controller.status`** is a `ValueListenable<FormStatus>` that notifies
  only when the status changes. It is 0006 §6's form-level listenable,
  narrowed. `FormStatusBuilder` listens to it.
- **`FormStatusBuilder`** takes `controller:` explicitly, or reads it from
  `FormScope`, like `FieldView` does (0006 §4).
- **Bloc and Riverpod:** `BlocSelector((s) => s.status.submitting)` or
  `select((s) => s.status.submitting)`. Nothing new is needed.
- **Disabling fields while sending** stays the app's choice, through the
  view-level `enabled` of 0006 §4: `FormScope(enabled: !submitting)`. It
  rebuilds every field once, which is correct: every field's `enabled`
  changed.
- **The form error is localized** by the same `ErrorLocalizer` (0001 §2),
  with no field.

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

SnapshotFormView(..., focus: focus);          // or FormScope(focus: focus)
focus.requestFirstError(snapshot);            // true if it moved focus
focus.requestFirstError(snapshot, scroll: false);
```

- **`FieldView` and `SnapshotFieldView` register their node** with the
  `FormFocus` they get from `FormScope` or from `focus:`. They unregister
  on unmount. Registering rebuilds nothing.
- **`FormController` owns one** (`controller.focus`), and `FormScope` uses
  it by default. Bloc and Riverpod users create one and pass it.
- **"First" means registration order,** which is the order of the
  payload and of `FormView` without a layout (0006 §1, 0007 §2). This is
  also what react-hook-form (`register` order) and flutter_form_builder
  (mount order) do. The engine computes it: `snapshot.firstErrorPath`,
  among the active fields that show an error.
- **Unmounted fields are skipped.** `requestFirstError` focuses the first
  field with an error that is mounted. If no field with an error is
  mounted, it returns `false`, and in debug mode it reports the paths.
  That matches 0006 §4's "visible fields placed nowhere" check.
- **It scrolls by default.** It calls `Scrollable.ensureVisible` before
  requesting focus, because focusing a field the user cannot see is worse
  than scrolling. `scroll: false` turns it off, for example in a layout
  that scrolls on its own. flutter_form_builder defaults the other way.
  `submitWith` takes the same `scroll:` and forwards it.
- **A form error alone moves no focus.** There is no field to focus; the
  app shows `status.formError` where it wants.
- **Bloc users** call it from a `BlocListener` that fires when
  `submitCount` grows and `isValid` is false, or when `lastSubmit` becomes
  `rejected`. The focus call stays in the UI, not in the bloc.

## Alternatives considered

- **`submitting` held in the controller,** outside the snapshot. It is
  simpler, but it breaks the rule that validation state lives in the
  snapshot, and Bloc users get nothing. Lost.
- **`submit()` becomes async and sets `submitting` itself** (like
  react-hook-form's `handleSubmit`). Lost: it breaks 0004's synchronous
  `submit()`, and it puts I/O in the flow of forms that do not need it.
  The transitions keep it opt-in, and `submitWith` gives the one-call
  version.
- **The form error as a reserved path** (react-hook-form's `root`). It
  reuses the field-error machinery, but a reserved key can clash with a
  catalog key. It would also count as an unregistered path, which 0007
  treats differently. A separate `formError` is clearer. Lost.
- **`lastSubmit` as a `bool`** (react-hook-form's `isSubmitSuccessful`).
  It cannot tell "the server said no" from "the server never answered".
  The UI needs that difference: one means fix the data, the other means
  try again. formz's status enum draws the same line. Lost.
- **Disable the submit button while the form is invalid, by default.** It
  is a common pattern, but it hides why the button does nothing, and the
  user never learns which field is wrong. `FormStatus` gives the facts
  and leaves the UX to the app.
- **A `FormStatusBuilder` that always passes the whole status.** It is
  simpler, but a button that reads only `submitting` would rebuild when
  `dirty` or `errorCount` changes. `select` costs one parameter. Lost.
- **Screen order for "first error"** (topmost render box, then leading
  edge). It follows custom layouts, but it depends on a layout pass, on
  text direction and on screen width (a row that wraps on a phone), so the
  same form could focus different fields on different devices. It is also
  harder to test. Registration order is deterministic and computed in the
  engine. Apps whose screen order differs can reorder `fields`.
- **A focus registry inside `FormController`,** or `focus()` on the model
  as in reactive_forms. It fits the default path, but `SnapshotFormView`
  users have no controller, and the model would hold UI objects.
  `FormFocus` is the same thing as a standalone object, and the
  controller just owns one.
- **`hasFocus` in `FieldProps`.** It is convenient for styling, but every
  focus move would rebuild two fields, which PRINCIPLES.md §2 forbids.

## Impact

**Amends accepted docs.**

| Doc | What changes |
|---|---|
| 0001 | §2: server errors enter through `completeSubmit`, as `ServerErrors`. `ErrorLocalizer` takes a nullable field, for the form error. The snapshot gains `status` and `firstErrorPath`. |
| 0004 | `FieldProps` gains `focusNode`. The cache contract is unchanged. `controller.submit()` is unchanged, and `submitWith` is added. `submit` ignores a call while submitting. |
| 0006 | §4: `FieldView` owns a `FocusNode`. `FormScope` and the field views take `focus:`. §6: the form-level listenable is `controller.status`. |
| 0007 | §6: server errors for registered paths are applied by `completeSubmit`, and discarded when the field changed during the submit. |

**Code.**
- `formwork_core`:
  - `FormStatus` and `SubmitOutcome`, with the status counters kept up to
    date on each change;
  - `ServerErrors`;
  - `startSubmitting`, `completeSubmit` and `abandonSubmit`;
  - `firstErrorPath`.
- `formwork`:
  - `controller.status` and `submitWith`;
  - `FormStatusBuilder` and `FormFocus`;
  - `focusNode` in `FieldProps`.
- `formwork_material`: every builder passes `focusNode`.
- The example:
  - the external-state scenario (Bloc-like) uses `submitCount` and
    `FormFocus`;
  - one scenario shows a submit button with "Sending…", field and form
    errors from a fake server, "Saved", and a failed send.

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
  - `completeSubmit` with no errors gives `accepted`; with field or form
    errors, `rejected`, and applies them;
  - a server error for a field changed during the submit is discarded;
  - the form error neither counts in `errorCount` nor blocks the next
    submit, and clears on the next `startSubmitting`;
  - `abandonSubmit` gives `abandoned` and applies nothing;
  - `submitWith` abandons the submit when `send` throws, and rethrows.
- **Rebuilds** (`rebuild_test.dart`):
  - typing in a valid field does not rebuild a `FormStatusBuilder`;
  - a `FormStatusBuilder` selecting `submitting` does not rebuild when
    `dirty` or `errorCount` changes;
  - moving focus between fields rebuilds no `FieldView`;
  - registering focus nodes rebuilds nothing.
- **Focus:**
  - a failed submit focuses the first field with an error in registration
    order, and scrolls to it;
  - `scroll: false` focuses without scrolling;
  - an unmounted field with an error is skipped;
  - with no mounted field in error, it returns `false` and reports in
    debug;
  - a form error alone moves no focus;
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
