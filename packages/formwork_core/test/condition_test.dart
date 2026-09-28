import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide isIn;

void main() {
  bool check(Condition condition, Map<String, Object?> values) =>
      condition.evaluate((path) => values[path.toString()]);

  group('Condition operators', () {
    test('eq and ne compare the value at a path', () {
      expect(check(eq('status', 'married'), {'status': 'married'}), isTrue);
      expect(check(eq('status', 'married'), {'status': 'single'}), isFalse);
      expect(check(eq('status', 'married'), {}), isFalse);
      expect(check(ne('status', 'married'), {'status': 'single'}), isTrue);
      expect(check(ne('status', 'married'), {}), isTrue);
    });

    test('eq compares lists by content, for multi-choice values', () {
      expect(
        check(eq('tags', ['a', 'b']), {
          'tags': ['a', 'b'],
        }),
        isTrue,
      );
    });

    test('eq on false tells "answered no" apart from "not answered"', () {
      expect(check(eq('hasCar', false), {'hasCar': false}), isTrue);
      expect(check(eq('hasCar', false), {}), isFalse);
    });

    test('isIn matches any of the listed values', () {
      final condition = isIn('state', ['SP', 'RJ']);
      expect(check(condition, {'state': 'RJ'}), isTrue);
      expect(check(condition, {'state': 'MG'}), isFalse);
      expect(check(condition, {}), isFalse);
    });

    test('comparisons order numbers', () {
      expect(check(gt('age', 18), {'age': 19}), isTrue);
      expect(check(gt('age', 18), {'age': 18}), isFalse);
      expect(check(gte('age', 18), {'age': 18}), isTrue);
      expect(check(lt('age', 18), {'age': 17.5}), isTrue);
      expect(check(lte('age', 18), {'age': 18}), isTrue);
      expect(check(lte('age', 18), {'age': 19}), isFalse);
    });

    test('comparisons order values of the same comparable type', () {
      final start = DateTime(2026, 1, 1);
      expect(
        check(gte('date', start), {'date': DateTime(2026, 2, 1)}),
        isTrue,
      );
      expect(check(lt('name', 'm'), {'name': 'ana'}), isTrue);
    });

    test('comparisons are false for missing or incomparable values', () {
      expect(check(gt('age', 18), {}), isFalse);
      expect(check(lt('age', 18), {}), isFalse);
      expect(check(gt('age', 18), {'age': '19'}), isFalse);
      expect(check(lt('age', 18), {'age': '17'}), isFalse);
    });

    test('empty counts what required counts as empty', () {
      for (final value in [
        null,
        '',
        '  ',
        false,
        <Object?>[],
        <Object?, Object?>{}
      ]) {
        expect(check(empty('x'), {'x': value}), isTrue, reason: '$value');
      }
      for (final value in [
        'a',
        0,
        true,
        ['a']
      ]) {
        expect(check(empty('x'), {'x': value}), isFalse, reason: '$value');
      }
    });

    test('all, any and not combine conditions', () {
      final adult = gte('age', 18);
      final married = eq('status', 'married');
      final values = {'age': 20, 'status': 'single'};

      expect(check(all([adult, married]), values), isFalse);
      expect(check(any([adult, married]), values), isTrue);
      expect(check(not(married), values), isTrue);
      expect(check(all([]), values), isTrue);
      expect(check(any([]), values), isFalse);
    });
  });

  group('Condition.reads', () {
    test('lists the path an operator reads', () {
      expect(eq('status', 'married').reads, {FieldPath('status')});
      expect(empty('address.zipCode').reads, {FieldPath('address.zipCode')});
    });

    test('combines the paths of nested conditions', () {
      final condition = all([
        eq('status', 'married'),
        not(any([gte('age', 18), empty('status')])),
      ]);
      expect(condition.reads, {FieldPath('status'), FieldPath('age')});
    });

    test('cannot be changed from outside', () {
      expect(
        () => eq('status', 'married').reads.add(FieldPath('age')),
        throwsUnsupportedError,
      );
    });
  });

  group('Condition equality', () {
    test('built-in conditions compare by value', () {
      expect(eq('status', 'married'), eq('status', 'married'));
      expect(
        eq('status', 'married').hashCode,
        eq('status', 'married').hashCode,
      );
      expect(eq('status', 'married'), isNot(ne('status', 'married')));
      expect(eq('status', 'married'), isNot(eq('status', 'single')));
      expect(gt('age', 18), isNot(gte('age', 18)));
    });

    test('operands compare deeply', () {
      expect(isIn('state', ['SP', 'RJ']), isIn('state', ['SP', 'RJ']));
      expect(
        isIn('state', ['SP', 'RJ']).hashCode,
        isIn('state', ['SP', 'RJ']).hashCode,
      );
      expect(isIn('state', ['SP', 'RJ']), isNot(isIn('state', ['RJ', 'SP'])));
    });

    test('combinators compare their children in order', () {
      final a = eq('status', 'married');
      final b = gte('age', 18);
      expect(all([a, b]), all([eq('status', 'married'), gte('age', 18)]));
      expect(all([a, b]), isNot(all([b, a])));
      expect(all([a, b]), isNot(any([a, b])));
      expect(not(a), not(eq('status', 'married')));
    });

    test('changing an operand list afterwards does not change a condition', () {
      final states = ['SP'];
      final condition = isIn('state', states);
      states.add('RJ');
      expect(check(condition, {'state': 'RJ'}), isFalse);
      expect(condition, isIn('state', ['SP']));
    });
  });

  test('a malformed path throws when the condition is built', () {
    expect(() => eq('a..b', 1), throwsFormatException);
  });

  test('a custom condition takes part like a built-in one', () {
    final condition = all([eq('country', 'BR'), _IsCpf('document')]);
    expect(condition.reads, {FieldPath('country'), FieldPath('document')});
    expect(
      check(condition, {'country': 'BR', 'document': '12345678901'}),
      isTrue,
    );
    expect(check(condition, {'country': 'BR', 'document': '123'}), isFalse);
  });
}

final class _IsCpf extends Condition {
  _IsCpf(String path) : path = FieldPath(path);

  final FieldPath path;

  @override
  Set<FieldPath> get reads => {path};

  @override
  bool evaluate(Object? Function(FieldPath path) valueOf) {
    final value = valueOf(path);
    return value is String && value.length == 11;
  }

  @override
  bool operator ==(Object other) => other is _IsCpf && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
