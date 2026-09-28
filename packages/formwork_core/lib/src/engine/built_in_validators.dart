import 'field_def.dart';
import 'field_path.dart';
import 'validation_error.dart';

/// Text at least [min] characters long. Error: `minLength`, `{'min': min}`.
Validator<String> minLength(int min) => _Length('minLength', 'min', min);

/// Text at most [max] characters long. Error: `maxLength`, `{'max': max}`.
Validator<String> maxLength(int max) => _Length('maxLength', 'max', max);

/// Text matching [pattern] somewhere. Error: `pattern`,
/// `{'pattern': pattern}`.
Validator<String> pattern(String pattern) => _Pattern(pattern);

/// A plausible e-mail address. Error: `email`.
Validator<String> email() => const _Email();

/// A number of at least [min]. Error: `min`, `{'min': min}`.
Validator<num> min(num min) => _Bound('min', min);

/// A number of at most [max]. Error: `max`, `{'max': max}`.
Validator<num> max(num max) => _Bound('max', max);

/// The same value as [other], such as a password confirmation. Error:
/// `matches`, `{'field': 'password'}`.
///
/// It reads [other], so it revalidates when [other] changes. Two fields may
/// match each other: validators do not form cycles.
Validator<T> matches<T>(FieldDef<T> other) => _Matches<T>(other.path);

/// [matches] for a field known only by its key, as a catalog names it.
Validator<T> matchesPath<T>(FieldPath other) => _Matches<T>(other);

final class _Length extends Validator<String> {
  const _Length(this.code, this.param, this.limit);

  final String code;
  final String param;
  final int limit;

  @override
  ValidationError? validate(String value, _) {
    final tooShort = code == 'minLength' && value.length < limit;
    final tooLong = code == 'maxLength' && value.length > limit;
    return tooShort || tooLong
        ? ValidationError(code, params: {param: limit})
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is _Length && other.code == code && other.limit == limit;

  @override
  int get hashCode => Object.hash(code, limit);
}

final class _Pattern extends Validator<String> {
  _Pattern(this.source) : _regExp = RegExp(source);

  final String source;
  final RegExp _regExp;

  @override
  ValidationError? validate(String value, _) => _regExp.hasMatch(value)
      ? null
      : ValidationError('pattern', params: {'pattern': source});

  @override
  bool operator ==(Object other) => other is _Pattern && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

final class _Email extends Validator<String> {
  const _Email();

  static final _shape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  ValidationError? validate(String value, _) =>
      _shape.hasMatch(value) ? null : ValidationError('email');

  @override
  bool operator ==(Object other) => other is _Email;

  @override
  int get hashCode => (_Email).hashCode;
}

final class _Bound extends Validator<num> {
  const _Bound(this.code, this.limit);

  final String code;
  final num limit;

  @override
  ValidationError? validate(num value, _) {
    final outside = code == 'min' ? value < limit : value > limit;
    return outside ? ValidationError(code, params: {code: limit}) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is _Bound && other.code == code && other.limit == limit;

  @override
  int get hashCode => Object.hash(code, limit);
}

final class _Matches<T> extends Validator<T> {
  _Matches(this.other) : reads = Set.unmodifiable({other});

  final FieldPath other;

  @override
  final Set<FieldPath> reads;

  @override
  ValidationError? validate(
          T value, Object? Function(FieldPath path) valueOf) =>
      value == valueOf(other)
          ? null
          : ValidationError('matches', params: {'field': other.toString()});

  @override
  bool operator ==(Object o) =>
      o.runtimeType == runtimeType && o is _Matches<T> && o.other == other;

  @override
  int get hashCode => Object.hash(_Matches, other);
}
