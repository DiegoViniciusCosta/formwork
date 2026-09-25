/// Where a [ValidationError] came from.
enum ErrorSource {
  /// A synchronous validator on the device.
  local,

  /// An asynchronous validator, such as "is this e-mail taken?".
  async,

  /// The server, in its answer to a submit.
  server,
}

/// A validation failure as data: a [code] plus [params], never display text
/// (design doc 0001 §2).
///
/// An error localizer turns it into text, so the design system decides how
/// errors read and look. Errors are immutable and compare by value, lists,
/// sets and maps inside [params] included, so tests and change detection
/// can compare them directly.
final class ValidationError {
  /// An error with [code], for example `minLength` with `{'min': 3}`.
  ///
  /// [params] is copied, so changing the map afterwards does not change the
  /// error.
  ValidationError(
    this.code, {
    Map<String, Object?> params = const {},
    this.source = ErrorSource.local,
  }) : params = Map.unmodifiable({
          for (final e in params.entries) e.key: _freeze(e.value),
        });

  /// What failed, for example `required` or `minLength`.
  final String code;

  /// What the localizer needs to explain the error, for example
  /// `{'min': 3}`. Read-only, all the way down.
  final Map<String, Object?> params;

  /// Where the error came from.
  final ErrorSource source;

  @override
  bool operator ==(Object other) =>
      other is ValidationError &&
      other.code == code &&
      other.source == source &&
      _deepEquals(other.params, params);

  @override
  int get hashCode => Object.hash(code, source, _deepHash(params));

  @override
  String toString() =>
      'ValidationError($code${params.isEmpty ? '' : ', $params'}'
      '${source == ErrorSource.local ? '' : ', ${source.name}'})';
}

Object? _freeze(Object? value) => switch (value) {
      Map() => Map<Object?, Object?>.unmodifiable({
          for (final e in value.entries) e.key: _freeze(e.value),
        }),
      List() => List<Object?>.unmodifiable(value.map(_freeze)),
      Set() => Set<Object?>.unmodifiable(value.map(_freeze)),
      _ => value,
    };

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length &&
        a.every((x) => b.any((y) => _deepEquals(x, y)));
  }
  return a == b;
}

int _deepHash(Object? value) => switch (value) {
      Map() => Object.hashAllUnordered([
          for (final e in value.entries) Object.hash(e.key, _deepHash(e.value)),
        ]),
      List() => Object.hashAll(value.map(_deepHash)),
      Set() => Object.hashAllUnordered(value.map(_deepHash)),
      _ => value.hashCode,
    };
