import '../engine/condition.dart';

/// Builds a custom condition from the arguments of its operator in a JSON
/// catalog: whatever the operator's key maps to.
///
/// [decode] decodes a nested condition, for operators that combine others.
/// Throw a [FormatException] when [args] is malformed. Let exceptions
/// thrown by [decode] propagate: it signals an unknown nested operator that
/// way, so that the whole condition is dropped.
typedef ConditionFactory = Condition Function(
  Object? args,
  Condition Function(Object? json) decode,
);

/// Decodes the conditions of a JSON catalog, such as
/// `{"eq": ["maritalStatus", "married"]}`, into [Condition]s (design doc
/// 0001 §4).
///
/// A condition is an object with exactly one key, its operator:
///
/// | Operator                          | Arguments                  |
/// |-----------------------------------|----------------------------|
/// | `eq`, `ne`, `gt`, `gte`, `lt`, `lte` | `["path", value]`       |
/// | `in`                              | `["path", [value, ...]]`   |
/// | `empty`                           | `["path"]`                 |
/// | `all`, `any`                      | `[condition, ...]`         |
/// | `not`                             | `condition`                |
///
/// Custom operators [register] like validators.
class ConditionRegistry {
  /// Creates a registry with the built-in operators.
  ///
  /// [onUnknown] is called when a condition uses an unregistered operator.
  /// The catalog may come from a server that is newer than the app, so the
  /// condition is dropped instead of throwing: the field behaves as if it
  /// had no such rule.
  ConditionRegistry({this.onUnknown}) {
    _factories.addAll(_builtIns);
  }

  /// Called with the name of every unknown operator.
  final void Function(String operator)? onUnknown;

  final Map<String, ConditionFactory> _factories = {};

  /// Registers or replaces an operator.
  void register(String operator, ConditionFactory factory) =>
      _factories[operator] = factory;

  /// Decodes [json] into a condition.
  ///
  /// Returns `null` when an unknown operator appears anywhere in [json],
  /// nested ones included, after reporting it to [onUnknown]. Dropping only
  /// the unknown branch would change what the rest means: inside `all` it
  /// would make the condition hold more often, inside `not` less.
  ///
  /// Throws a [FormatException] when [json] is malformed.
  Condition? decode(Object? json) {
    try {
      return _decode(json);
    } on _UnknownOperator catch (e) {
      onUnknown?.call(e.operator);
      return null;
    }
  }

  Condition _decode(Object? json) {
    if (json is! Map || json.length != 1 || json.keys.single is! String) {
      throw FormatException(
          'A condition is an object with exactly one operator', json);
    }
    final operator = json.keys.single as String;
    final factory = _factories[operator];
    if (factory == null) throw _UnknownOperator(operator);
    return factory(json.values.single, _decode);
  }
}

/// Thrown inside [ConditionRegistry._decode] so that an unknown operator
/// drops the whole condition, through custom factories too.
final class _UnknownOperator implements Exception {
  _UnknownOperator(this.operator);

  final String operator;
}

final Map<String, ConditionFactory> _builtIns = {
  'eq': _pathAndValue(eq),
  'ne': _pathAndValue(ne),
  'gt': _pathAndValue((path, value) => gt(path, _nonNull(value))),
  'gte': _pathAndValue((path, value) => gte(path, _nonNull(value))),
  'lt': _pathAndValue((path, value) => lt(path, _nonNull(value))),
  'lte': _pathAndValue((path, value) => lte(path, _nonNull(value))),
  'in': _pathAndValue((path, values) => values is List
      ? isIn(path, values)
      : throw FormatException('"in" takes a list of values', values)),
  'empty': (args, _) => switch (args) {
        [final String path] => empty(path),
        _ => throw FormatException('"empty" takes ["path"]', args),
      },
  'all': (args, decode) => all(_conditions(args, decode)),
  'any': (args, decode) => any(_conditions(args, decode)),
  'not': (args, decode) => not(decode(args)),
};

ConditionFactory _pathAndValue(Condition Function(String, Object?) build) =>
    (args, _) => switch (args) {
          [final String path, final value] => build(path, value),
          _ => throw FormatException('Expected ["path", value]', args),
        };

Object _nonNull(Object? value) =>
    value ?? (throw const FormatException('A comparison needs a value'));

List<Condition> _conditions(
  Object? args,
  Condition Function(Object? json) decode,
) =>
    args is List
        ? [for (final c in args) decode(c)]
        : throw FormatException('Expected a list of conditions', args);
