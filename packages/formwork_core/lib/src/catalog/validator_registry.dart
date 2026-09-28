import '../engine/built_in_validators.dart';
import '../engine/field_def.dart';
import '../engine/field_path.dart';

/// Builds a validator from its catalog spec, such as
/// `{"type": "minLength", "value": 3}`.
///
/// The validator must accept the value type of the fields it is used on:
/// one that does not is skipped there and reported. Throw a
/// [FormatException] when the spec is malformed.
typedef ValidatorFactory = Validator<Object?> Function(
  Map<String, Object?> spec,
);

/// Decodes the validator specs of a JSON catalog into [Validator]s.
///
/// Built-in types: `required` (it sets the field's `required`),
/// `minLength`, `maxLength`, `pattern`, `email`, `min`, `max` and
/// `matches` (`{"type": "matches", "field": "password"}`). Every spec takes
/// an optional `message`, which overrides the text of that validator's
/// error code on the field (decision 17 of design doc 0001).
class ValidatorRegistry {
  final Map<String, ValidatorFactory> _custom = {};

  /// Registers or replaces a validator type, a built-in one included.
  void register(String type, ValidatorFactory factory) =>
      _custom[type] = factory;

  /// Whether [type] is known.
  bool knows(String type) =>
      _custom.containsKey(type) ||
      _builtIns.containsKey(type) ||
      type == 'matches' ||
      type == 'required';

  /// The validator for [spec], for a field holding [T]; `null` when its
  /// type is unknown, or when it does not accept a [T].
  ///
  /// Throws a [FormatException] when [spec] is malformed.
  Validator<T>? build<T>(Map<String, Object?> spec) {
    final type = spec['type'];
    if (type is! String) {
      throw FormatException('A validator needs a type', spec);
    }
    if (_custom[type] case final factory?) return _typed<T>(factory(spec));
    if (type == 'matches') {
      return matchesPath<T>(FieldPath(_string(spec, 'field')));
    }
    if (_builtIns[type] case final factory?) return _typed<T>(factory(spec));
    return null;
  }
}

/// [validator] as a `Validator<T>` when it accepts every [T]. A covariant
/// `is` check alone would let a `Validator<String>` onto an `Object` field.
Validator<T>? _typed<T>(Validator<Object?> validator) =>
    validator is Validator<T> && validatorAccepts<T>(validator)
        ? validator
        : null;

final Map<String, ValidatorFactory> _builtIns = {
  'minLength': (spec) => minLength(_int(spec, 'value')),
  'maxLength': (spec) => maxLength(_int(spec, 'value')),
  'pattern': (spec) => pattern(_string(spec, 'value')),
  'email': (_) => email(),
  'min': (spec) => min(_num(spec, 'value')),
  'max': (spec) => max(_num(spec, 'value')),
};

int _int(Map<String, Object?> spec, String key) => switch (spec[key]) {
      final int v => v,
      _ => throw FormatException('"$key" must be an integer', spec),
    };

num _num(Map<String, Object?> spec, String key) => switch (spec[key]) {
      final num v => v,
      _ => throw FormatException('"$key" must be a number', spec),
    };

String _string(Map<String, Object?> spec, String key) => switch (spec[key]) {
      final String v => v,
      _ => throw FormatException('"$key" must be text', spec),
    };
