import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

/// Everything a field builder receives: the whole builder contract
/// (design doc 0004).
///
/// Small on purpose, so any component, design-system ones included, can
/// satisfy it. A design system that renders errors its own way reads the
/// raw [error]; one that shows text reads [errorText].
final class FieldProps<T> {
  /// The props of one field.
  const FieldProps({
    required this.def,
    required this.value,
    required this.error,
    required this.errorText,
    required this.enabled,
    required this.required,
    required this.validating,
    required this.onChanged,
  });

  /// The field's definition: label, hint, options and the rest.
  final FieldDef<T> def;

  /// The current value.
  final T? value;

  /// The current error as data, shown or not (design doc 0001 §2).
  final ValidationError? error;

  /// The localized error to display now: only once the user changed the
  /// field or tried to submit.
  final String? errorText;

  /// Whether the field accepts input: its own rule and the view-level flag
  /// combined.
  final bool enabled;

  /// Whether the field is required now.
  final bool required;

  /// Whether an asynchronous validation is pending.
  final bool validating;

  /// Reports a new value.
  final ValueChanged<T?> onChanged;
}
