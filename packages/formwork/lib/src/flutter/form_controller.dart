import 'package:flutter/foundation.dart';
import 'package:formwork_core/formwork_core.dart';

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
  }) : _snapshot = engine.registerAll(
          engine.initial(initialValues: initialValues),
          form.fields,
        ) {
    _status = ValueNotifier(_snapshot.status);
  }

  /// The rules this controller applies.
  final FormEngine engine;

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

  /// Marks a submit attempt, which shows every error, and returns the
  /// payload when the form is valid, else `null`.
  Map<String, Object?>? submit() {
    final (:snapshot, :payload) = engine.submit(_snapshot);
    _moveTo(snapshot);
    return payload;
  }

  @override
  void dispose() {
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
