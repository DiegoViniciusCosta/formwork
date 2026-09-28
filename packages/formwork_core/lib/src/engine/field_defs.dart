import 'condition.dart' as c;
import 'condition.dart' show Condition;
import 'deep_equality.dart';
import 'field_codec.dart';
import 'field_def.dart';

/// A text field: `"text"` in a catalog.
final class TextFieldDef extends FieldDef<String> {
  /// A text field at [key]. See [FieldDef.new] for the parameters.
  TextFieldDef(
    super.key, {
    super.label,
    super.hint,
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.validators,
    super.initialValue,
    super.extra,
    super.messages,
  });

  @override
  String get type => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextFieldDef && sameFieldDef(this, other);

  @override
  int get hashCode => fieldDefHash(this);
}

/// A number field: `"number"` in a catalog.
final class NumberFieldDef extends FieldDef<num> {
  /// A number field at [key]. See [FieldDef.new] for the parameters.
  NumberFieldDef(
    super.key, {
    super.label,
    super.hint,
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.validators,
    super.initialValue,
    super.extra,
    super.messages,
  });

  @override
  String get type => 'number';

  /// A condition that holds when this field's value is greater than
  /// [value]: the same condition as `gt(key, value)`.
  Condition greaterThan(num value) => c.gt(path.toString(), value);

  /// A condition that holds when this field's value is at least [value]:
  /// the same condition as `gte(key, value)`.
  Condition greaterThanOrEqualTo(num value) => c.gte(path.toString(), value);

  /// A condition that holds when this field's value is less than [value]:
  /// the same condition as `lt(key, value)`.
  Condition lessThan(num value) => c.lt(path.toString(), value);

  /// A condition that holds when this field's value is at most [value]: the
  /// same condition as `lte(key, value)`.
  Condition lessThanOrEqualTo(num value) => c.lte(path.toString(), value);

  @override
  bool operator ==(Object other) =>
      other is NumberFieldDef && sameFieldDef(this, other);

  @override
  int get hashCode => fieldDefHash(this);
}

/// A yes-or-no field: `"checkbox"` in a catalog.
///
/// A required checkbox must be checked: `required` counts `false` as
/// empty. For a question whose "no" is a valid answer, use a
/// `ChoiceFieldDef` (design doc 0003).
final class BoolFieldDef extends FieldDef<bool> {
  /// A checkbox at [key]. See [FieldDef.new] for the parameters.
  BoolFieldDef(
    super.key, {
    super.label,
    super.hint,
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.validators,
    super.initialValue,
    super.extra,
    super.messages,
  });

  @override
  String get type => 'checkbox';

  @override
  bool operator ==(Object other) =>
      other is BoolFieldDef && sameFieldDef(this, other);

  @override
  int get hashCode => fieldDefHash(this);
}

/// One option of a [ChoiceFieldDef]: a [value], the [label] shown for it,
/// and its [json].
final class Option<T> {
  /// An option. [json] defaults to the enum's `name` when [value] is an
  /// enum, and to [value] itself when it is a `String`, `num` or `bool`
  /// (design doc 0006 §3).
  ///
  /// Throws an [ArgumentError] when [value] is of another type and [json]
  /// is omitted: it would otherwise fail later, when the payload is sent.
  Option(this.value, this.label, {Object? json})
      : json = json ?? _defaultJson(value);

  static Object _defaultJson(Object? value) => switch (value) {
        Enum(:final name) => name,
        final String v => v,
        final num v => v,
        final bool v => v,
        _ => throw ArgumentError.value(
            value,
            'value',
            'Not JSON: pass json: for this option (design doc 0006 §3)',
          ),
      };

  /// The value the field holds when this option is chosen.
  final T value;

  /// The text shown for this option.
  final String label;

  /// How [value] appears in JSON: in the payload, initial values and
  /// catalog conditions.
  final Object? json;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is Option<T> &&
      other.value == value &&
      other.label == label &&
      deepEquals(other.json, json);

  @override
  int get hashCode => Object.hash(value, label, deepHash(json));

  @override
  String toString() => 'Option($value, $label)';
}

/// A field whose value is one of [options]: `"dropdown"` in a catalog.
///
/// Its codec comes from the options: each value is encoded as its option's
/// `json`, and JSON is decoded by looking it up among the options, so a
/// choice field accepts exactly the values it lists.
final class ChoiceFieldDef<T> extends FieldDef<T> {
  /// A choice field at [key]. See [FieldDef.new] for the other parameters.
  ChoiceFieldDef(
    super.key, {
    required List<Option<T>> options,
    super.label,
    super.hint,
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.validators,
    super.initialValue,
    super.extra,
    super.messages,
  })  : options = List.unmodifiable(options),
        super(codec: _OptionsCodec<T>(List.unmodifiable(options)));

  /// The values to choose from, in the order they are shown.
  final List<Option<T>> options;

  @override
  String get type => 'dropdown';

  @override
  bool operator ==(Object other) =>
      other is ChoiceFieldDef<T> &&
      sameFieldDef(this, other) &&
      deepEquals(other.options, options);

  @override
  int get hashCode => Object.hash(fieldDefHash(this), deepHash(options));
}

final class _OptionsCodec<T> extends FieldCodec<T> {
  const _OptionsCodec(this.options) : super.base();

  final List<Option<T>> options;

  @override
  Object? encode(T value) {
    for (final option in options) {
      if (option.value == value) return option.json;
    }
    // A value outside the options, set in code: encode it as an option
    // would be.
    return value is Enum ? value.name : value;
  }

  @override
  T decode(Object json) {
    for (final option in options) {
      if (deepEquals(option.json, json)) return option.value;
    }
    throw FormatException('Not one of the options', json);
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is _OptionsCodec<T> &&
      deepEquals(other.options, options);

  @override
  int get hashCode => deepHash(options);
}
