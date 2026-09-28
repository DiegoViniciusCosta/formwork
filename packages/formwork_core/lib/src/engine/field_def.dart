import 'condition.dart' as c;
import 'condition.dart' show Condition;
import 'deep_equality.dart';
import 'field_codec.dart';
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
/// Subclasses name their registry key in [type]. A [T] that is not
/// `String`, `num` or `bool` needs a [codec] (design doc 0006 §3).
///
/// The base class compares
/// by identity (design doc 0007 §3): a subclass that wants an equal
/// re-registration to be free overrides `==` and `hashCode` over every
/// parameter, its own and the ones declared here ([messages] and [codec]
/// included), lists and maps compared by content.
abstract class FieldDef<T> {
  /// A field at [key], which is also its payload key.
  ///
  /// Throws a [FormatException] when [key] is not a valid [FieldPath], and
  /// an [ArgumentError] when [T] is not JSON and there is no [codec].
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
    Map<String, String> messages = const {},
    FieldCodec<T>? codec,
  })  : path = FieldPath(key),
        validators = List.unmodifiable(validators),
        extra = Map.unmodifiable(freeze(extra)! as Map),
        messages = Map.unmodifiable(messages),
        codec = codec ?? JsonValueCodec<T>();

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

  /// Text that replaces the localized message of an error, by error code,
  /// for this field only (design doc 0001 §2 and decision 17).
  final Map<String, String> messages;

  /// Converts the value to and from JSON.
  final FieldCodec<T> codec;

  /// A condition that holds when this field's value equals [value]: the
  /// same condition as `eq(key, value)`, checked by the compiler.
  Condition equals(T value) => c.eq(path.toString(), value);

  /// A condition that holds when this field's value is one of [values]: the
  /// same condition as `isIn(key, values)`.
  Condition isIn(List<T> values) => c.isIn(path.toString(), values);

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

/// Whether [a] and [b] are equal in every parameter [FieldDef] declares,
/// lists and maps by content. Built-in definitions compare with it and add
/// their own parameters. Engine-side; the package barrel does not export
/// it.
bool sameFieldDef(FieldDef<Object?> a, FieldDef<Object?> b) =>
    a.runtimeType == b.runtimeType &&
    a.path == b.path &&
    a.label == b.label &&
    a.hint == b.hint &&
    a.required == b.required &&
    a.visibleWhen == b.visibleWhen &&
    a.enabledWhen == b.enabledWhen &&
    a.requiredWhen == b.requiredWhen &&
    deepEquals(a.validators, b.validators) &&
    deepEquals(a.initialValue, b.initialValue) &&
    deepEquals(a.extra, b.extra) &&
    deepEquals(a.messages, b.messages) &&
    a.codec == b.codec;

/// A hash consistent with [sameFieldDef].
int fieldDefHash(FieldDef<Object?> def) => Object.hash(
      def.runtimeType,
      def.path,
      def.label,
      def.hint,
      def.required,
      def.visibleWhen,
      def.enabledWhen,
      def.requiredWhen,
      deepHash(def.validators),
      deepHash(def.initialValue),
      deepHash(def.extra),
      deepHash(def.messages),
      def.codec,
    );

/// Decodes [json] for [def]. Returns `(null, true)` for `null`, and
/// `(null, false)` when [def]'s codec rejects it. Engine-side.
(Object?, bool) decodeFieldValue(FieldDef<Object?> def, Object? json) {
  if (json == null) return (null, true);
  try {
    return (def.codec.decode(json), true);
  } on Object {
    return (null, false);
  }
}

/// Encodes [value] for [def]; `null` stays `null`. Engine-side.
Object? encodeFieldValue(FieldDef<Object?> def, Object? value) =>
    value == null ? null : def.codec.encode(value);

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
