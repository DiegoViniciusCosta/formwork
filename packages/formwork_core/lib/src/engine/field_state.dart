import 'validation_error.dart';

/// Everything a view needs to draw one field, as one immutable value
/// (design doc 0001 §6).
///
/// When the engine applies a change, every field whose state did not change
/// keeps the *identical* instance. A view therefore rebuilds a field if and
/// only if its state is not identical to the previous one. For that reason
/// `FieldState` compares by identity: two states that look equal are still
/// two states.
final class FieldState {
  /// A state; the defaults describe an empty, visible, enabled field.
  const FieldState({
    this.value,
    this.error,
    this.visible = true,
    this.enabled = true,
    this.required = false,
    this.touched = false,
    this.dirty = false,
    this.validating = false,
    this.generation = 0,
  });

  /// The current value, decoded to the field's type.
  final Object? value;

  /// The current error, shown or not; see [touched].
  final ValidationError? error;

  /// Whether the field's visibility rule, and every rule up its chain,
  /// passes.
  final bool visible;

  /// Whether the field's enabled rule passes.
  final bool enabled;

  /// Whether the field's required rule passes.
  final bool required;

  /// Whether the user has changed the field at least once.
  final bool touched;

  /// Whether the value differs from the initial value.
  final bool dirty;

  /// Whether an asynchronous validation is pending for the current value.
  final bool validating;

  /// How many times this path was registered or its definition replaced
  /// (design doc 0007 §6). An asynchronous result tagged with an older
  /// generation is stale, and is discarded.
  final int generation;

  @override
  String toString() => 'FieldState(value: $value, error: $error, '
      'visible: $visible, enabled: $enabled, required: $required, '
      'touched: $touched, dirty: $dirty, validating: $validating, '
      'generation: $generation)';
}

/// Engine-side updates of [FieldState]. Not exported: only the engine
/// builds new states.
extension FieldStateUpdate on FieldState {
  /// A new state with the given fields replaced. Pass `null` to [value] to
  /// clear it, and [clearError] to remove the error.
  FieldState copyWith({
    Object? value = _unset,
    ValidationError? error,
    bool clearError = false,
    bool? visible,
    bool? enabled,
    bool? required,
    bool? touched,
    bool? dirty,
    bool? validating,
    int? generation,
  }) =>
      FieldState(
        value: identical(value, _unset) ? this.value : value,
        error: clearError ? null : error ?? this.error,
        visible: visible ?? this.visible,
        enabled: enabled ?? this.enabled,
        required: required ?? this.required,
        touched: touched ?? this.touched,
        dirty: dirty ?? this.dirty,
        validating: validating ?? this.validating,
        generation: generation ?? this.generation,
      );
}

const Object _unset = Object();
