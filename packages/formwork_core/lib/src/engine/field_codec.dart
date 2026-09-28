/// Converts a field's value between its Dart type [T] and JSON (design doc
/// 0006 §3, decision 15 of 0001).
///
/// It applies wherever JSON meets the form: initial values are decoded
/// when their field registers, condition operands in a catalog are decoded
/// through the field they read, and the payload is encoded. `null` is never
/// passed to either function: it stays `null`.
///
/// `String`, `num` and `bool` are their own JSON, and a `ChoiceFieldDef`
/// derives its codec from its options. Any other [T] needs a codec:
///
/// ```dart
/// final isoDate = FieldCodec<DateTime>(
///   encode: (date) => date.toIso8601String(),
///   decode: (json) => DateTime.parse(json as String),
/// );
/// ```
///
/// A codec built from functions compares by identity, so keep one instance
/// per type, as above, instead of building one inside each definition.
abstract class FieldCodec<T> {
  /// A codec from two functions. [decode] throws, for example a
  /// [FormatException], when the JSON is not a valid [T].
  const factory FieldCodec({
    required Object? Function(T value) encode,
    required T Function(Object json) decode,
  }) = _FunctionCodec<T>;

  /// Const constructor for subclasses, which should compare by value.
  const FieldCodec.base();

  /// The JSON for [value].
  Object? encode(T value);

  /// The value for [json]. Throws when [json] is not a valid [T].
  T decode(Object json);
}

final class _FunctionCodec<T> extends FieldCodec<T> {
  const _FunctionCodec({
    required Object? Function(T value) encode,
    required T Function(Object json) decode,
  })  : _encode = encode,
        _decode = decode,
        super.base();

  final Object? Function(T value) _encode;
  final T Function(Object json) _decode;

  @override
  Object? encode(T value) => _encode(value);

  @override
  T decode(Object json) => _decode(json);
}

/// The codec of a type that is its own JSON: `String`, `num` or `bool`.
/// Compares by value, so equal definitions stay equal. Engine-side; the
/// package barrel does not export it.
final class JsonValueCodec<T> extends FieldCodec<T> {
  /// The codec for [T]. Throws an [ArgumentError] when [T] is not its own
  /// JSON, so a missing codec fails when the definition is built, in
  /// release too (design doc 0006 §3).
  JsonValueCodec() : super.base() {
    if (!isJsonValueType<T>()) {
      throw ArgumentError(
        '$T is not JSON: pass a codec: that converts it (design doc 0006 §3).',
      );
    }
  }

  @override
  Object? encode(T value) => value;

  @override
  T decode(Object json) =>
      json is T ? json as T : throw FormatException('Expected $T', json);

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => T.hashCode;
}

/// Whether [T] is its own JSON: `String`, `num` or `bool`, or a subtype.
bool isJsonValueType<T>() =>
    <T>[] is List<String?> || <T>[] is List<num?> || <T>[] is List<bool?>;
