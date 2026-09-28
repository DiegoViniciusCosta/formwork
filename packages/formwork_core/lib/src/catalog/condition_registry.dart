import '../engine/condition.dart';
import '../engine/field_path.dart';

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
  ConditionRegistry({this.onUnknown});

  /// Called with the name of every unknown operator.
  final void Function(String operator)? onUnknown;

  final Map<String, ConditionFactory> _custom = {};

  /// Registers or replaces an operator, a built-in one included.
  void register(String operator, ConditionFactory factory) =>
      _custom[operator] = factory;

  /// Decodes [json] into a condition.
  ///
  /// Returns `null` when an unknown operator appears anywhere in [json],
  /// nested ones included, after reporting it to [onUnknown] and to this
  /// call's [unknown]. Dropping only the unknown branch would change what
  /// the rest means: inside `all` it would make the condition hold more
  /// often, inside `not` less.
  ///
  /// [decodeOperand] turns the JSON operand of a built-in comparison into
  /// the value it is compared with, given the path it reads: a catalog
  /// decodes it through that field's codec (design doc 0006 §3). When it
  /// throws, the whole condition is dropped too (decision 22 of 0001).
  ///
  /// Throws a [FormatException] when [json] is malformed.
  Condition? decode(
    Object? json, {
    Object? Function(FieldPath path, Object? json)? decodeOperand,
    void Function(String operator)? unknown,
  }) {
    final decoder = _Decoder(this, decodeOperand);
    try {
      return decoder.decode(json);
    } on _UnknownOperator catch (e) {
      onUnknown?.call(e.operator);
      unknown?.call(e.operator);
      return null;
    } on _UndecodableOperand {
      return null;
    }
  }
}

/// One [ConditionRegistry.decode] call.
final class _Decoder {
  _Decoder(this.registry, this.decodeOperand);

  final ConditionRegistry registry;
  final Object? Function(FieldPath path, Object? json)? decodeOperand;

  Condition decode(Object? json) {
    if (json is! Map || json.length != 1 || json.keys.single is! String) {
      throw FormatException(
          'A condition is an object with exactly one operator', json);
    }
    final operator = json.keys.single as String;
    final args = json.values.single;
    if (registry._custom[operator] case final factory?) {
      return factory(args, decode);
    }
    if (_builtIns[operator] case final builtIn?) return builtIn(args, this);
    throw _UnknownOperator(operator);
  }

  /// [json] as the value compared with [path].
  Object? operand(String path, Object? json) {
    final decode = decodeOperand;
    if (decode == null) return json;
    // Parsed outside the try: a malformed path is a malformed catalog.
    final fieldPath = FieldPath(path);
    try {
      return decode(fieldPath, json);
    } on Object {
      throw const _UndecodableOperand();
    }
  }
}

/// Thrown inside a decode so that an unknown operator drops the whole
/// condition, through custom factories too.
final class _UnknownOperator implements Exception {
  _UnknownOperator(this.operator);

  final String operator;
}

/// Thrown inside a decode when an operand does not decode.
final class _UndecodableOperand implements Exception {
  const _UndecodableOperand();
}

typedef _BuiltIn = Condition Function(Object? args, _Decoder decoder);

final Map<String, _BuiltIn> _builtIns = {
  'eq': _compare(eq),
  'ne': _compare(ne),
  'gt': _compare((path, value) => gt(path, _nonNull(value))),
  'gte': _compare((path, value) => gte(path, _nonNull(value))),
  'lt': _compare((path, value) => lt(path, _nonNull(value))),
  'lte': _compare((path, value) => lte(path, _nonNull(value))),
  'in': (args, d) => switch (args) {
        [final String path, final List<Object?> values] =>
          isIn(path, [for (final v in values) d.operand(path, v)]),
        _ => throw FormatException('"in" takes ["path", [values]]', args),
      },
  'empty': (args, _) => switch (args) {
        [final String path] => empty(path),
        _ => throw FormatException('"empty" takes ["path"]', args),
      },
  'all': (args, d) => all(_conditions(args, d)),
  'any': (args, d) => any(_conditions(args, d)),
  'not': (args, d) => not(d.decode(args)),
};

_BuiltIn _compare(Condition Function(String, Object?) build) =>
    (args, d) => switch (args) {
          [final String path, final value] =>
            build(path, value == null ? null : d.operand(path, value)),
          _ => throw FormatException('Expected ["path", value]', args),
        };

Object _nonNull(Object? value) =>
    value ?? (throw const FormatException('A comparison needs a value'));

List<Condition> _conditions(Object? args, _Decoder d) => args is List
    ? [for (final c in args) d.decode(c)]
    : throw FormatException('Expected a list of conditions', args);
