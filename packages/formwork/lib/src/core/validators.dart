import 'field_config.dart';

/// Returns an error message, or `null` when [value] is valid.
typedef FieldValidator = String? Function(Object? value);

/// Builds a validator from its spec, e.g. `{'type': 'minLength', 'value': 3}`.
typedef ValidatorFactory = FieldValidator Function(Map<String, dynamic> spec);

/// Whether [v] counts as empty: `null`, blank string, `false` or empty
/// collection.
bool isEmptyValue(Object? v) =>
    v == null ||
    (v is String && v.trim().isEmpty) ||
    (v is bool && !v) ||
    (v is Iterable && v.isEmpty);

String _msg(Map<String, dynamic> spec, String fallback) =>
    spec['message'] as String? ?? fallback;

final Map<String, ValidatorFactory> _defaults = {
  'required': (s) =>
      (v) => isEmptyValue(v) ? _msg(s, 'This field is required') : null,
  'minLength': (s) {
    final min = s['value'] as int;
    return (v) => v.toString().length < min
        ? _msg(s, 'Must be at least $min characters')
        : null;
  },
  'maxLength': (s) {
    final max = s['value'] as int;
    return (v) => v.toString().length > max
        ? _msg(s, 'Must be at most $max characters')
        : null;
  },
  'pattern': (s) {
    final re = RegExp(s['value'] as String);
    return (v) => re.hasMatch(v.toString()) ? null : _msg(s, 'Invalid format');
  },
  'email': (s) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return (v) =>
        re.hasMatch(v.toString()) ? null : _msg(s, 'Invalid email address');
  },
  'min': (s) {
    final min = s['value'] as num;
    return (v) => v is num && v < min ? _msg(s, 'Must be at least $min') : null;
  },
  'max': (s) {
    final max = s['value'] as num;
    return (v) => v is num && v > max ? _msg(s, 'Must be at most $max') : null;
  },
};

/// Resolves validator specs into [FieldValidator]s.
///
/// Built-in types: `required`, `minLength`, `maxLength`, `pattern`, `email`,
/// `min`, `max`. Every spec accepts an optional `message` override.
class ValidatorRegistry {
  /// Creates a registry with the built-in validators.
  ///
  /// [onUnknown] is called when a spec uses an unregistered type. The spec
  /// is skipped instead of throwing: the catalog may come from a server that
  /// is newer than the app, and the server is the final authority anyway.
  ValidatorRegistry({this.onUnknown}) {
    _factories.addAll(_defaults);
  }

  /// Called with the type of every unknown validator spec.
  final void Function(String type)? onUnknown;

  final Map<String, ValidatorFactory> _factories = {};

  /// Registers or replaces a validator type.
  void register(String type, ValidatorFactory factory) =>
      _factories[type] = factory;

  /// Composes `required` plus the field's specs. Returns the first error.
  FieldValidator? buildFor(FieldConfig field) {
    final chain = <FieldValidator>[
      if (field.required) _resolve(const {'type': 'required'})!,
      for (final spec in field.validators)
        if (_resolve(spec) case final validator?) validator,
    ];
    if (chain.isEmpty) return null;

    return (value) {
      for (final validate in chain) {
        final error = validate(value);
        if (error != null) return error;
      }
      return null;
    };
  }

  FieldValidator? _resolve(Map<String, dynamic> spec) {
    final type = spec['type'] as String? ?? '';
    final factory = _factories[type];
    if (factory == null) {
      onUnknown?.call(type);
      return null;
    }
    final inner = factory(spec);
    // Empty values are the sole responsibility of `required`.
    if (type == 'required') return inner;
    return (v) => isEmptyValue(v) ? null : inner(v);
  }
}
