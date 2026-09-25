import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart';

void main() {
  group('ValidationError', () {
    test('is data: a code and params, local by default', () {
      final error = ValidationError('minLength', params: {'min': 3});
      expect(error.code, 'minLength');
      expect(error.params, {'min': 3});
      expect(error.source, ErrorSource.local);
    });

    test('compares by value, params included', () {
      expect(
        ValidationError('minLength', params: {'min': 3}),
        ValidationError('minLength', params: {'min': 3}),
      );
      expect(
        ValidationError('minLength', params: {'min': 3}).hashCode,
        ValidationError('minLength', params: {'min': 3}).hashCode,
      );
      expect(
        ValidationError('minLength', params: {'min': 3}),
        isNot(ValidationError('minLength', params: {'min': 4})),
      );
    });

    test('the source is part of equality', () {
      expect(
        ValidationError('taken'),
        isNot(ValidationError('taken', source: ErrorSource.server)),
      );
    });

    test('params compare deeply', () {
      expect(
        ValidationError('oneOf', params: {
          'allowed': ['a', 'b'],
        }),
        ValidationError('oneOf', params: {
          'allowed': ['a', 'b'],
        }),
      );
    });

    test('different codes are different errors', () {
      expect(ValidationError('min'), isNot(ValidationError('max')));
    });

    test('params are copied: changing the map later changes nothing', () {
      final params = <String, Object?>{
        'min': 3,
        'allowed': ['a'],
      };
      final error = ValidationError('min', params: params);
      final hash = error.hashCode;
      params['min'] = 4;
      (params['allowed']! as List).add('b');
      expect(error.params, {
        'min': 3,
        'allowed': ['a'],
      });
      expect(error.hashCode, hash);
    });

    test('sets and nested maps in params compare by value', () {
      expect(
        ValidationError('x', params: {
          's': {1, 2},
          'm': {
            'k': [1]
          },
        }),
        ValidationError('x', params: {
          's': {2, 1},
          'm': {
            'k': [1]
          },
        }),
      );
    });

    test('params are read-only all the way down', () {
      final error = ValidationError('x', params: {
        'list': [1],
      });
      expect(
          () => (error.params['list']! as List).add(2), throwsUnsupportedError);
    });

    test('params are read-only', () {
      final error = ValidationError('min', params: {'min': 1});
      expect(() => error.params['min'] = 2, throwsUnsupportedError);
    });
  });
}
