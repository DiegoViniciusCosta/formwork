import 'deep_equality.dart';

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
          for (final e in params.entries) e.key: freeze(e.value),
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
      deepEquals(other.params, params);

  @override
  int get hashCode => Object.hash(code, source, deepHash(params));

  @override
  String toString() =>
      'ValidationError($code${params.isEmpty ? '' : ', $params'}'
      '${source == ErrorSource.local ? '' : ', ${source.name}'})';
}
