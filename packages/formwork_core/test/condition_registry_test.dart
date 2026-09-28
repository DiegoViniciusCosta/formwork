import 'dart:convert';

import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide isIn;

void main() {
  group('ConditionRegistry.decode', () {
    final conditions = ConditionRegistry();

    test('decodes every built-in operator to the condition built in code', () {
      final cases = <Object, Condition>{
        '{"eq": ["status", "married"]}': eq('status', 'married'),
        '{"ne": ["status", "married"]}': ne('status', 'married'),
        '{"in": ["state", ["SP", "RJ"]]}': isIn('state', ['SP', 'RJ']),
        '{"gt": ["age", 18]}': gt('age', 18),
        '{"gte": ["age", 18]}': gte('age', 18),
        '{"lt": ["age", 18]}': lt('age', 18),
        '{"lte": ["age", 18]}': lte('age', 18),
        '{"empty": ["address.zipCode"]}': empty('address.zipCode'),
        '{"not": {"eq": ["status", "married"]}}': not(eq('status', 'married')),
      };
      cases.forEach((json, expected) {
        expect(conditions.decode(jsonDecode(json as String)), expected,
            reason: json);
      });
    });

    test('decodes nested combinators', () {
      final json = {
        'all': [
          {
            'eq': ['maritalStatus', 'married'],
          },
          {
            'any': [
              {
                'gte': ['age', 18],
              },
              {
                'empty': ['guardian'],
              },
            ],
          },
        ],
      };
      expect(
        conditions.decode(json),
        all([
          eq('maritalStatus', 'married'),
          any([gte('age', 18), empty('guardian')]),
        ]),
      );
    });

    test('throws a FormatException on a malformed condition', () {
      for (final json in <Object?>[
        null,
        'eq',
        <String, Object?>{},
        {
          'eq': ['a', 1],
          'ne': ['a', 2]
        },
        {
          'eq': ['a']
        },
        {
          'eq': [1, 2]
        },
        {
          'eq': ['a..b', 1]
        },
        {
          'in': ['a', 'SP']
        },
        {'empty': 'a'},
        {
          'all': {
            'eq': ['a', 1]
          }
        },
        {
          'not': ['a']
        },
      ]) {
        expect(() => conditions.decode(json), throwsFormatException,
            reason: '$json');
      }
    });
  });

  group('an unknown operator (a catalog newer than the app)', () {
    test('drops the whole condition and reports the operator', () {
      final unknown = <String>[];
      final conditions = ConditionRegistry(onUnknown: unknown.add);
      expect(
          conditions.decode({
            'matchesRegex': ['a', '^x']
          }),
          isNull);
      expect(unknown, ['matchesRegex']);
    });

    test('inside a combinator drops the whole condition, not the branch', () {
      final unknown = <String>[];
      final conditions = ConditionRegistry(onUnknown: unknown.add);
      final json = {
        'not': {
          'any': [
            {
              'eq': ['a', 1],
            },
            {'future': []},
          ],
        },
      };
      expect(conditions.decode(json), isNull);
      expect(unknown, ['future']);
    });
  });

  group('custom operators', () {
    test('register like validators and decode to the custom condition', () {
      final conditions = ConditionRegistry()
        ..register('cpf', (args, decode) => _IsCpf(args as String));
      expect(
        conditions.decode({
          'all': [
            {
              'eq': ['country', 'BR'],
            },
            {'cpf': 'document'},
          ],
        }),
        all([eq('country', 'BR'), _IsCpf('document')]),
      );
    });

    test('can decode nested conditions', () {
      final conditions = ConditionRegistry()
        ..register('unless', (args, decode) => not(decode(args)));
      expect(
        conditions.decode({
          'unless': {
            'eq': ['a', 1],
          },
        }),
        not(eq('a', 1)),
      );
    });

    test('an unknown operator nested in a custom one drops the condition', () {
      final unknown = <String>[];
      final conditions = ConditionRegistry(onUnknown: unknown.add)
        ..register('unless', (args, decode) => not(decode(args)));
      expect(
        conditions.decode({
          'unless': {'future': []},
        }),
        isNull,
      );
      expect(unknown, ['future']);
    });
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
