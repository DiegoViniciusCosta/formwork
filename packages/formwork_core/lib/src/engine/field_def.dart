import 'condition.dart';
import 'field_path.dart';
import 'validation_error.dart';
import 'validators.dart' show isEmptyValue;

/// A rule a field's value must follow, returning error data, never display
/// text (design doc 0001 §2 and decision 9).
///
/// A validator that reads other fields, such as "matches `password`",
/// lists them in [reads]; the engine then revalidates it when they change.
/// Validators never see empty values: only `required` judges emptiness.
///
/// A custom validator should override `==` and `hashCode` over every
/// parameter, so that an equal re-registration is recognised as the same
/// (design doc 0007 §3).
abstract class Validator<T> {
  /// Const constructor for subclasses.
  const Validator();

  /// The other paths this validator reads; none for most validators.
  Set<FieldPath> get reads => const {};

  /// The error for [value], or `null` when it is valid. [valueOf] reads the
  /// value of another path, one listed in [reads].
  ValidationError? validate(T value, Object? Function(FieldPath path) valueOf);
}

/// The definition of one field holding a [T] (design doc 0001 §3): where it
/// lives, what it shows, and the rules it follows.
///
/// Subclasses name their registry key in [type]. The base class compares
/// by identity (design doc 0007 §3): a subclass that wants an equal
/// re-registration to be free overrides `==` and `hashCode` over every
/// parameter, lists and maps compared by content.
abstract class FieldDef<T> {
  /// A field at [key], which is also its payload key.
  ///
  /// Throws a [FormatException] when [key] is not a valid [FieldPath].
  FieldDef(
    String key, {
    this.label,
    this.hint,
    this.required = false,
    this.visibleWhen,
    this.enabledWhen,
    this.requiredWhen,
    List<Validator<T>> validators = const [],
    this.initialValue,
    Map<String, Object?> extra = const {},
  })  : path = FieldPath(key),
        validators = List.unmodifiable(validators),
        extra = Map.unmodifiable(extra);

  /// Where the field lives in the form.
  final FieldPath path;

  /// The key of the field registry that renders this field, and the JSON
  /// `"type"`.
  String get type;

  /// Text that names the field, if any.
  final String? label;

  /// Helper text, if any.
  final String? hint;

  /// Whether the field is always required. See [requiredWhen].
  final bool required;

  /// When the field is shown; always, if `null`. A hidden field is not
  /// validated and is not in the payload, and neither is any field whose
  /// [visibleWhen] reads it.
  final Condition? visibleWhen;

  /// When the field can be edited; always, if `null`. A disabled field is
  /// read-only data: it stays in the payload and is not validated.
  final Condition? enabledWhen;

  /// When the field is required, in addition to [required]: the field is
  /// required when either holds.
  final Condition? requiredWhen;

  /// The rules the value follows, in order; the first error wins.
  final List<Validator<T>> validators;

  /// The value when neither the initial values nor an earlier registration
  /// provide one.
  final T? initialValue;

  /// Catalog keys this definition does not know, for custom builders.
  final Map<String, Object?> extra;

  /// The paths this field's conditions read.
  Set<FieldPath> get conditionReads => {
        ...?visibleWhen?.reads,
        ...?enabledWhen?.reads,
        ...?requiredWhen?.reads,
      };

  /// The paths this field's validators read.
  Set<FieldPath> get validatorReads => {
        for (final v in validators) ...v.reads,
      };

  ValidationError? _validate(
    Object? value,
    bool required,
    Object? Function(FieldPath path) valueOf,
  ) {
    if (isEmptyValue(value)) {
      return required ? ValidationError('required') : null;
    }
    // Values are decoded to T at registration from step 4 on (design doc
    // 0006 §3); until then a value of another type is a programmer error.
    final typed = value as T;
    for (final validator in validators) {
      if (validator.validate(typed, valueOf) case final error?) return error;
    }
    return null;
  }

  @override
  String toString() => '$runtimeType($path)';
}

/// The error of [def] for [value]: `required` when it is empty and
/// [required], otherwise the first validator's error. Engine-side; the
/// package barrel does not export it.
ValidationError? validateField(
  FieldDef<Object?> def,
  Object? value, {
  required bool required,
  required Object? Function(FieldPath path) valueOf,
}) =>
    def._validate(value, required, valueOf);
