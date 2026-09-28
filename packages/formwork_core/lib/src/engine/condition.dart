import 'deep_equality.dart';
import 'field_path.dart';
import 'empty_value.dart';

/// A rule over the form's values, such as "`maritalStatus` is `married`",
/// used by `visibleWhen`, `enabledWhen` and `requiredWhen` (design doc 0001
/// §4).
///
/// Conditions are a tree of data, not strings: they can be compared,
/// tested and inspected. Build them with [eq], [ne], [isIn], [gt], [gte],
/// [lt], [lte], [empty], [all], [any] and [not]. Built-in conditions are
/// immutable and compare by value.
///
/// A custom condition extends this class, and must override `==` and
/// `hashCode` over every parameter, so that an equal re-registration is
/// recognised as the same (design doc 0007 §3).
abstract class Condition {
  /// Const constructor for subclasses.
  const Condition();

  /// The paths this condition reads. They feed the dependency graph: a
  /// change to one of them re-evaluates the condition, and nothing else
  /// does.
  Set<FieldPath> get reads;

  /// Whether the condition holds, reading values through [valueOf].
  ///
  /// [valueOf] returns `null` for a path without a value.
  bool evaluate(Object? Function(FieldPath path) valueOf);
}

/// Holds when the value at [path] equals [value]. Lists, sets and maps
/// compare by content.
///
/// Throws a [FormatException] when [path] is malformed.
Condition eq(String path, Object? value) =>
    _Compare(_Op.eq, FieldPath(path), freeze(value));

/// Holds when the value at [path] does not equal [value]. A missing value
/// is not equal to anything but `null`.
///
/// Throws a [FormatException] when [path] is malformed.
Condition ne(String path, Object? value) =>
    _Compare(_Op.ne, FieldPath(path), freeze(value));

/// Holds when the value at [path] is greater than [value].
///
/// Numbers compare with numbers, and other values with values of the same
/// [Comparable] type, such as two `DateTime`s. Anything else, a missing
/// value included, does not hold. The same applies to [gte], [lt] and
/// [lte].
///
/// Throws a [FormatException] when [path] is malformed.
Condition gt(String path, Object value) =>
    _Compare(_Op.gt, FieldPath(path), freeze(value));

/// Holds when the value at [path] is greater than or equal to [value]. See
/// [gt] for which values compare.
Condition gte(String path, Object value) =>
    _Compare(_Op.gte, FieldPath(path), freeze(value));

/// Holds when the value at [path] is less than [value]. See [gt] for which
/// values compare.
Condition lt(String path, Object value) =>
    _Compare(_Op.lt, FieldPath(path), freeze(value));

/// Holds when the value at [path] is less than or equal to [value]. See
/// [gt] for which values compare.
Condition lte(String path, Object value) =>
    _Compare(_Op.lte, FieldPath(path), freeze(value));

/// Holds when the value at [path] equals one of [values]. Called `in` in a
/// JSON catalog, a reserved word in Dart.
///
/// [values] is copied, so changing the list afterwards does not change the
/// condition. Throws a [FormatException] when [path] is malformed.
Condition isIn(String path, List<Object?> values) =>
    _IsIn(FieldPath(path), freeze(values)! as List<Object?>);

/// Holds when the value at [path] is empty exactly as `required` counts
/// it: `null`, blank text, `false` or an empty collection. To tell "answered
/// no" apart from "not answered", use `eq(path, false)`.
///
/// Throws a [FormatException] when [path] is malformed.
Condition empty(String path) => _Empty(FieldPath(path));

/// Holds when every one of [conditions] holds; an empty list holds.
Condition all(List<Condition> conditions) =>
    _All(List.unmodifiable(conditions));

/// Holds when at least one of [conditions] holds; an empty list does not.
Condition any(List<Condition> conditions) =>
    _Any(List.unmodifiable(conditions));

/// Holds when [condition] does not.
Condition not(Condition condition) => _Not(condition);

enum _Op { eq, ne, gt, gte, lt, lte }

final class _Compare extends Condition {
  _Compare(this.op, this.path, this.operand) : reads = Set.unmodifiable({path});

  final _Op op;
  final FieldPath path;
  final Object? operand;

  @override
  final Set<FieldPath> reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) {
    final value = valueOf(path);
    switch (op) {
      case _Op.eq:
        return deepEquals(value, operand);
      case _Op.ne:
        return !deepEquals(value, operand);
      case _Op.gt || _Op.gte || _Op.lt || _Op.lte:
        final order = _compare(value, operand);
        if (order == null) return false;
        return switch (op) {
          _Op.gt => order > 0,
          _Op.gte => order >= 0,
          _Op.lt => order < 0,
          _ => order <= 0,
        };
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _Compare &&
      other.op == op &&
      other.path == path &&
      deepEquals(other.operand, operand);

  @override
  int get hashCode => Object.hash(op, path, deepHash(operand));

  @override
  String toString() => '${op.name}($path, $operand)';
}

/// The order of [a] relative to [b], or `null` when they do not compare.
int? _compare(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is Comparable && b is Comparable && a.runtimeType == b.runtimeType) {
    return a.compareTo(b);
  }
  return null;
}

final class _IsIn extends Condition {
  _IsIn(this.path, this.values) : reads = Set.unmodifiable({path});

  final FieldPath path;
  final List<Object?> values;

  @override
  final Set<FieldPath> reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) {
    final value = valueOf(path);
    return values.any((v) => deepEquals(v, value));
  }

  @override
  bool operator ==(Object other) =>
      other is _IsIn && other.path == path && deepEquals(other.values, values);

  @override
  int get hashCode => Object.hash(_IsIn, path, deepHash(values));

  @override
  String toString() => 'isIn($path, $values)';
}

final class _Empty extends Condition {
  _Empty(this.path) : reads = Set.unmodifiable({path});

  final FieldPath path;

  @override
  final Set<FieldPath> reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) =>
      isEmptyValue(valueOf(path));

  @override
  bool operator ==(Object other) => other is _Empty && other.path == path;

  @override
  int get hashCode => Object.hash(_Empty, path);

  @override
  String toString() => 'empty($path)';
}

final class _All extends Condition {
  _All(this.conditions) : reads = _union(conditions);

  final List<Condition> conditions;

  @override
  final Set<FieldPath> reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) =>
      conditions.every((c) => c.evaluate(valueOf));

  @override
  bool operator ==(Object other) =>
      other is _All && deepEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(_All, Object.hashAll(conditions));

  @override
  String toString() => 'all($conditions)';
}

final class _Any extends Condition {
  _Any(this.conditions) : reads = _union(conditions);

  final List<Condition> conditions;

  @override
  final Set<FieldPath> reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) =>
      conditions.any((c) => c.evaluate(valueOf));

  @override
  bool operator ==(Object other) =>
      other is _Any && deepEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(_Any, Object.hashAll(conditions));

  @override
  String toString() => 'any($conditions)';
}

final class _Not extends Condition {
  _Not(this.condition);

  final Condition condition;

  @override
  Set<FieldPath> get reads => condition.reads;

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) =>
      !condition.evaluate(valueOf);

  @override
  bool operator ==(Object other) =>
      other is _Not && other.condition == condition;

  @override
  int get hashCode => Object.hash(_Not, condition);

  @override
  String toString() => 'not($condition)';
}

Set<FieldPath> _union(List<Condition> conditions) =>
    Set.unmodifiable({for (final c in conditions) ...c.reads});
