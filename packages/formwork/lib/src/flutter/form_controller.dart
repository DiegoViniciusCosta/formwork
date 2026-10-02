import 'package:flutter/foundation.dart';
import 'package:formwork_core/formwork_core.dart';

import 'form_focus.dart';

/// What an app does with a valid payload: sends it, and reports the
/// server's answer, `null` when it accepted (design doc 0008 §2).
typedef FormSender = Future<ServerErrors?> Function(
  Map<String, Object?> payload,
);

/// Holds a form's snapshot for apps without a state management package,
/// and tells each field when its own state changes (design docs 0004 and
/// 0006 §6).
///
/// As a [ValueListenable] of [FormSnapshot] it notifies on every change,
/// for whole-form UI. Field views listen to [fieldState] instead, which
/// notifies only the fields whose state changed: a keystroke costs the
/// fields it touches, whatever the size of the form.
class FormController extends ChangeNotifier
    implements ValueListenable<FormSnapshot> {
  /// A controller for [form], starting from [initialValues]: what is
  /// already known, as JSON, keyed by path.
  FormController(
    FormDef form, {
    Map<String, Object?> initialValues = const {},
    this.engine = const FormEngine(),
  })  : layout = form.layout,
        _snapshot = engine.registerAll(
          engine.initial(initialValues: initialValues),
          form.fields,
        ) {
    _status = ValueNotifier(_snapshot.status);
  }

  /// The rules this controller applies.
  final FormEngine engine;

  /// How [FormView] arranges the fields: the form's layout, `null` for a
  /// column (design doc 0006 §5).
  final LayoutNode? layout;

  /// The focus of this form's fields, used by default by the field views
  /// below a `FormScope` of this controller.
  final FormFocus focus = FormFocus();

  bool _disposed = false;

  FormSnapshot _snapshot;
  late final ValueNotifier<FormStatus> _status;
  final Map<FieldPath, _FieldListenable> _fields = {};

  /// The current snapshot.
  @override
  FormSnapshot get value => _snapshot;

  /// Moves to [next], which the engine made from the current snapshot: its
  /// `changedPaths` are what differs, so only those fields are told.
  void _moveTo(FormSnapshot next) {
    if (identical(next, _snapshot)) return;
    _snapshot = next;
    for (final path in next.changedPaths) {
      _fields[path]?.refresh(next);
    }
    _status.value = next.status;
    notifyListeners();
  }

  /// The form-level facts, notified only when they change (design doc
  /// 0008 §3).
  ValueListenable<FormStatus> get status => _status;

  /// The state of [def]'s field, `null` while it is not registered,
  /// notified only when that state changes. Created on first use and
  /// kept.
  ValueListenable<FieldState?> fieldState(FieldDef<Object?> def) =>
      _fields[def.path] ??= _FieldListenable(def, _snapshot);

  /// Sets the value at [path]: a field's value of its type, or user data
  /// as JSON (see [FormEngine.change]).
  void change(FieldPath path, Object? value) =>
      _moveTo(engine.change(_snapshot, path, value));

  /// Adds an item to the list at [list], at the end or at index [at], its
  /// fields filled from [values] (see [FormEngine.addItem]).
  void addItem(
    FieldPath list, {
    Map<String, Object?> values = const {},
    int? at,
  }) =>
      _moveTo(engine.addItem(_snapshot, list, values: values, at: at));

  /// Removes the list item at [item], such as `ListFieldDef.itemPath(id)`
  /// (see [FormEngine.removeItem]).
  void removeItem(FieldPath item) =>
      _moveTo(engine.removeItem(_snapshot, item));

  /// Moves the list item at [item] to index [to] (see
  /// [FormEngine.moveItem]).
  void moveItem(FieldPath item, int to) =>
      _moveTo(engine.moveItem(_snapshot, item, to));

  /// Marks a submit attempt, which shows every error, and returns the
  /// payload when the form is valid, else `null`. It sends nothing: see
  /// [submitTo] to send and record the answer in one call.
  Map<String, Object?>? submit() {
    final (:snapshot, :payload) = engine.submit(_snapshot);
    _moveTo(snapshot);
    return payload;
  }

  /// Submits, and sends a valid payload with [send] (design doc 0008 §2):
  /// "submit to `api.saveProfile`".
  ///
  /// Returns `null` when validation stopped the submit, while a send is
  /// in progress, or when the controller was disposed before the answer;
  /// otherwise how the send ended. When validation or the
  /// server rejects the payload, focus moves to the first field with an
  /// error, scrolling to it unless [scroll] is false. When [send] throws,
  /// the send is abandoned and the error rethrown, so the form never stays
  /// submitting. See [submit] for the attempt alone.
  Future<SubmitOutcome?> submitTo(FormSender send, {bool scroll = true}) async {
    if (_snapshot.status.submitting) return null;
    final payload = submit();
    if (payload == null) {
      focus.requestFirstError(_snapshot, scroll: scroll);
      return null;
    }
    _moveTo(engine.startSubmitting(_snapshot));
    final ServerErrors? answer;
    try {
      answer = await send(payload);
    } catch (_) {
      if (!_disposed) _moveTo(engine.abandonSubmit(_snapshot));
      rethrow;
    }
    if (_disposed) return null;
    _moveTo(engine.completeSubmit(_snapshot, answer));
    final outcome = _snapshot.status.lastSubmit;
    if (outcome == SubmitOutcome.rejected) {
      focus.requestFirstError(_snapshot, scroll: scroll);
    }
    return outcome;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final field in _fields.values) {
      field.dispose();
    }
    _status.dispose();
    super.dispose();
  }
}

/// One field's state, refreshed only when its path changed.
final class _FieldListenable extends ValueNotifier<FieldState?> {
  _FieldListenable(this.def, FormSnapshot snapshot)
      : super(snapshot.stateOf(def));

  final FieldDef<Object?> def;

  void refresh(FormSnapshot snapshot) => value = snapshot.stateOf(def);
}
