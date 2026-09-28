import 'package:formwork_core/formwork_core.dart'
    hide FormEngine, FormSnapshot, ValidatorRegistry;
import 'package:formwork_core/src/catalog/form_catalog.dart';
import 'package:formwork_core/src/catalog/validator_registry.dart';
import 'package:formwork_core/src/engine/engine.dart';
import 'package:test/test.dart' hide isIn, matches;

enum MaritalStatus { single, married }

final class RatingFieldDef extends FieldDef<int> {
  RatingFieldDef(super.key, {super.label, super.visibleWhen, this.max = 5});

  final int max;

  @override
  String get type => 'rating';
}

FieldPath p(String path) => FieldPath(path);

FieldTypeRegistry withStatus() => FieldTypeRegistry()
  ..register(
    'status',
    (f) => ChoiceFieldDef<MaritalStatus>(
      f.key,
      options: [for (final s in MaritalStatus.values) Option(s, s.name)],
      visibleWhen: f.visibleWhen,
      initialValue: f.initialValue as MaritalStatus?,
    ),
  );

void main() {
  const engine = FormEngine();

  test('reads the built-in types in catalog order', () {
    final catalog = FormCatalog.fromJson({
      'schemaVersion': 1,
      'fields': [
        {
          'key': 'name',
          'type': 'text',
          'label': 'Name',
          'required': true,
          'validators': [
            {'type': 'minLength', 'value': 3},
          ],
        },
        {'key': 'income', 'type': 'number', 'initialValue': 1500},
        {'key': 'terms', 'type': 'checkbox'},
        {
          'key': 'state',
          'type': 'dropdown',
          'options': [
            {'value': 'SP', 'label': 'São Paulo'},
          ],
        },
      ],
    });
    expect(catalog.issues, isEmpty);
    expect(catalog.fields, [
      TextFieldDef('name',
          label: 'Name', required: true, validators: [minLength(3)]),
      NumberFieldDef('income', initialValue: 1500),
      BoolFieldDef('terms'),
      ChoiceFieldDef<Object>('state', options: [Option('SP', 'São Paulo')]),
    ]);
  });

  test('a JSON condition decoded through the field codec equals code', () {
    // The reader comes before the field it reads: order does not matter.
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'spouse',
          'type': 'text',
          'visibleWhen': {
            'eq': ['status', 'married'],
          },
        },
        {'key': 'status', 'type': 'status'},
      ],
    }, types: withStatus());
    final status = catalog.fields[1] as ChoiceFieldDef<MaritalStatus>;
    expect(catalog.fields[0].visibleWhen, status.equals(MaritalStatus.married));
  });

  test('a catalog form runs in the engine like one written in code', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'status', 'type': 'status', 'initialValue': 'single'},
        {
          'key': 'spouse',
          'type': 'text',
          'required': true,
          'visibleWhen': {
            'eq': ['status', 'married'],
          },
        },
      ],
    }, types: withStatus());
    var s = engine.registerAll(engine.initial(), catalog.fields);
    expect(s.payload(), {'status': 'single'});

    s = engine.change(s, p('status'), MaritalStatus.married);
    expect(s.payload(), {'status': 'married', 'spouse': null});
    expect(s.isValid, isFalse);
  });

  test('a required validator and messages are read', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'name',
          'type': 'text',
          'validators': [
            {'type': 'required', 'message': 'Tell us'},
            {'type': 'minLength', 'value': 3, 'message': 'Too short'},
          ],
        },
      ],
    });
    final def = catalog.fields.single;
    expect(def.required, isTrue);
    expect(def.messages, {'required': 'Tell us', 'minLength': 'Too short'});
    expect(def.validators, [minLength(3)]);
  });

  test('matches reads the field it names', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'password', 'type': 'text'},
        {
          'key': 'confirm',
          'type': 'text',
          'validators': [
            {'type': 'matches', 'field': 'password'},
          ],
        },
      ],
    });
    expect(catalog.fields[1].validators,
        [matches(catalog.fields[0] as TextFieldDef)]);
  });

  test('a custom type builds from a FieldJson', () {
    final types = FieldTypeRegistry()
      ..register(
        'rating',
        (f) => RatingFieldDef(f.key,
            label: f.label,
            visibleWhen: f.visibleWhen,
            max: f.json['max'] as int? ?? 5),
      );
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'stars', 'type': 'rating', 'label': 'Stars', 'max': 10},
      ],
    }, types: types);
    final def = catalog.fields.single as RatingFieldDef;
    expect(def.max, 10);
    expect(def.label, 'Stars');
  });

  test('a custom validator registers by type', () {
    final validators = ValidatorRegistry()
      ..register('cpf', (_) => const _Cpf());
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'document',
          'type': 'text',
          'validators': [
            {'type': 'cpf'},
          ],
        },
      ],
    }, validators: validators);
    expect(catalog.issues, isEmpty);
    expect(catalog.fields.single.validators, [const _Cpf()]);
  });

  test('in lists and nested operands decode through the field codec', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'status', 'type': 'status'},
        {
          'key': 'a',
          'type': 'text',
          'enabledWhen': {
            'in': [
              'status',
              ['single', 'married'],
            ],
          },
          'requiredWhen': {
            'not': {
              'any': [
                {
                  'eq': ['status', 'married'],
                },
              ],
            },
          },
        },
      ],
    }, types: withStatus());
    final a = catalog.fields[1];
    expect(a.enabledWhen, isIn('status', MaritalStatus.values));
    expect(a.requiredWhen, not(any([eq('status', MaritalStatus.married)])));
  });

  test('one bad element in an in list drops the whole condition', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'status', 'type': 'status'},
        {
          'key': 'a',
          'type': 'text',
          'visibleWhen': {
            'in': [
              'status',
              ['single', 'widowed'],
            ],
          },
        },
      ],
    }, types: withStatus());
    expect(catalog.fields[1].visibleWhen, isNull);
    expect(catalog.issues.single.kind, CatalogIssueKind.undecodableOperand);
  });

  test('schemaVersion is read, 1 by default', () {
    expect(FormCatalog.fromJson({'fields': []}).schemaVersion, 1);
    expect(
        FormCatalog.fromJson({'schemaVersion': 2, 'fields': []}).schemaVersion,
        2);
  });

  test('a factory reads the validators once, and cannot change the entry', () {
    final types = FieldTypeRegistry()
      ..register('twice', (f) {
        f.validators<String>();
        expect(() => f.json['key'] = 'x', throwsUnsupportedError);
        return TextFieldDef(f.key, validators: f.validators<String>());
      });
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'a',
          'type': 'twice',
          'validators': [
            {'type': 'nope'},
          ],
        },
      ],
    }, types: types);
    expect(catalog.issues, hasLength(1));
  });

  test('keys no built-in part reads are kept as extra', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {'key': 'cpf', 'type': 'text', 'mask': '###.###.###-##'},
      ],
    });
    expect(catalog.fields.single.extra, {'mask': '###.###.###-##'});
  });

  group('tolerance: skipped and reported', () {
    test('an unknown type skips the field', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'where', 'type': 'map'},
          {'key': 'name', 'type': 'text'},
        ],
      });
      expect(catalog.fields.map((d) => d.path), [p('name')]);
      expect(catalog.issues,
          [CatalogIssue(CatalogIssueKind.unknownType, p('where'), 'map')]);
    });

    test('an unknown validator, or one of another type, is skipped', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'name',
            'type': 'text',
            'validators': [
              {'type': 'cpf'},
              {'type': 'min', 'value': 3},
              {'type': 'minLength', 'value': 3},
            ],
          },
        ],
      });
      expect(catalog.fields.single.validators, [minLength(3)]);
      expect(catalog.issues.map((i) => i.kind), [
        CatalogIssueKind.unknownValidator,
        CatalogIssueKind.unknownValidator,
      ]);
      expect(catalog.issues.first.detail, 'cpf');
    });

    test('a validator that does not accept every value is skipped', () {
      // By covariance a Validator<String> is a Validator<Object>, but a
      // dropdown of numbers would crash it.
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'n',
            'type': 'dropdown',
            'options': [
              {'value': 1, 'label': 'One'},
            ],
            'validators': [
              {'type': 'minLength', 'value': 2},
            ],
          },
        ],
      });
      expect(catalog.fields.single.validators, isEmpty);
      expect(catalog.issues.single.detail, 'minLength does not accept Object');
      var s = engine.registerAll(engine.initial(), catalog.fields);
      expect(() => s = engine.change(s, p('n'), 1), returnsNormally);
    });

    test('a custom validator of a narrower type is skipped', () {
      final validators = ValidatorRegistry()
        ..register('even', (_) => const _Even());
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'n',
            'type': 'number',
            'validators': [
              {'type': 'even'},
            ],
          },
        ],
      }, validators: validators);
      expect(catalog.fields.single.validators, isEmpty);
      expect(catalog.issues.single.kind, CatalogIssueKind.unknownValidator);
    });

    test('an unknown operator drops the condition, not the field', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'plate',
            'type': 'text',
            'visibleWhen': {
              'matchesRegex': ['x', '^a'],
            },
          },
        ],
      });
      expect(catalog.fields.single.visibleWhen, isNull);
      expect(catalog.issues, [
        CatalogIssue(
            CatalogIssueKind.unknownOperator, p('plate'), 'matchesRegex'),
      ]);
    });

    test('an operand the field codec rejects drops the condition', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'status', 'type': 'status'},
          {
            'key': 'spouse',
            'type': 'text',
            'visibleWhen': {
              'eq': ['status', 'widowed'],
            },
          },
        ],
      }, types: withStatus());
      expect(catalog.fields[1].visibleWhen, isNull);
      expect(catalog.issues, [
        CatalogIssue(
            CatalogIssueKind.undecodableOperand, p('spouse'), 'widowed'),
      ]);
    });

    test('an operand on a path outside the form stays JSON', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'spouse',
            'type': 'text',
            'visibleWhen': {
              'eq': ['userStatus', 'married'],
            },
          },
        ],
      });
      expect(catalog.fields.single.visibleWhen, eq('userStatus', 'married'));
    });

    test('an initial value the codec rejects is ignored', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'income', 'type': 'number', 'initialValue': 'lots'},
        ],
      });
      expect(catalog.fields.single.initialValue, isNull);
      expect(catalog.issues, [
        CatalogIssue(CatalogIssueKind.undecodableValue, p('income'), 'lots'),
      ]);
    });

    test('a field that closes a cycle is skipped, and the rest works', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'a',
            'type': 'text',
            'visibleWhen': {
              'eq': ['b', 'x'],
            },
          },
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {
              'eq': ['a', 'y'],
            },
          },
          {'key': 'c', 'type': 'text'},
        ],
      });
      expect(catalog.fields.map((d) => d.path), [p('a'), p('c')]);
      expect(catalog.issues.single.kind, CatalogIssueKind.cycle);
      expect(catalog.issues.single.detail, [p('b'), p('a'), p('b')]);
      expect(catalog.issues.single.path, p('b'));
      expect(() => engine.registerAll(engine.initial(), catalog.fields),
          returnsNormally);
    });
  });

  test('a field skipped for a cycle reports only the cycle', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'a',
          'type': 'text',
          'visibleWhen': {
            'eq': ['b', 'x'],
          },
        },
        {
          'key': 'b',
          'type': 'text',
          'validators': [
            {'type': 'nope'},
          ],
          'visibleWhen': {
            'eq': ['a', 'y'],
          },
        },
      ],
    });
    expect(catalog.issues.map((i) => i.kind), [CatalogIssueKind.cycle]);
  });

  test('operands on a field skipped for a cycle are read as JSON', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'a',
          'type': 'text',
          'visibleWhen': {
            'eq': ['status', 'single'],
          },
        },
        {
          'key': 'status',
          'type': 'status',
          'visibleWhen': {
            'eq': ['a', 'y'],
          },
        },
        {
          'key': 'c',
          'type': 'text',
          'visibleWhen': {
            'eq': ['status', 'married'],
          },
        },
      ],
    }, types: withStatus());
    expect(catalog.fields.map((d) => d.path), [p('a'), p('c')]);
    expect(catalog.fields[1].visibleWhen, eq('status', 'married'));
  });

  test('a field skipped for a cycle with a mistyped initial value', () {
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'a',
          'type': 'text',
          'visibleWhen': {
            'eq': ['b', 'x'],
          },
        },
        {
          'key': 'b',
          'type': 'text',
          'initialValue': 5,
          'visibleWhen': {
            'eq': ['a', 'y'],
          },
        },
      ],
    });
    expect(catalog.issues.map((i) => i.kind), [CatalogIssueKind.cycle]);
  });

  test('a validator that implements Validator instead of extending it', () {
    final validators = ValidatorRegistry()
      ..register('upper', (_) => const _Upper());
    final catalog = FormCatalog.fromJson({
      'fields': [
        {
          'key': 'a',
          'type': 'text',
          'validators': [
            {'type': 'upper'},
          ],
        },
      ],
    }, validators: validators);
    expect(catalog.fields.single.validators, [const _Upper()]);
  });

  group('a malformed catalog throws', () {
    for (final (name, json) in <(String, Map<String, Object?>)>[
      (
        'options that are not a list',
        {
          'fields': [
            {'key': 'a', 'type': 'dropdown', 'options': 'x'},
          ],
        }
      ),
      (
        'a field with a key that is not text',
        {
          'fields': [
            {'key': 'a', 'type': 'text', 1: 2},
          ],
        }
      ),
      ('fields that are not a list', {'fields': 'x'}),
      (
        'a field that is not an object',
        {
          'fields': [1],
        }
      ),
      (
        'a label that is not text',
        {
          'fields': [
            {'key': 'a', 'type': 'text', 'label': 3},
          ],
        }
      ),
      (
        'a validator that is not an object',
        {
          'fields': [
            {
              'key': 'a',
              'type': 'text',
              'validators': [1],
            },
          ],
        }
      ),
      (
        'validators that are not a list',
        {
          'fields': [
            {'key': 'a', 'type': 'text', 'validators': <String, Object?>{}},
          ],
        }
      ),
      ('a schemaVersion that is not a number', {'schemaVersion': '1'}),
      (
        'an option without a label',
        {
          'fields': [
            {
              'key': 'a',
              'type': 'dropdown',
              'options': [
                {'value': 1},
              ],
            },
          ],
        }
      ),
      (
        'a duplicated key',
        {
          'fields': [
            {'key': 'a', 'type': 'text'},
            {'key': 'a', 'type': 'number'},
          ],
        }
      ),
      (
        'a field without a type',
        {
          'fields': [
            {'key': 'a'},
          ],
        }
      ),
      (
        'a validator without its value',
        {
          'fields': [
            {
              'key': 'a',
              'type': 'text',
              'validators': [
                {'type': 'minLength'},
              ],
            },
          ],
        }
      ),
      (
        'a malformed condition',
        {
          'fields': [
            {
              'key': 'a',
              'type': 'text',
              'visibleWhen': {
                'eq': ['b'],
              },
            },
          ],
        }
      ),
    ]) {
      test(name, () {
        expect(() => FormCatalog.fromJson(json), throwsFormatException);
      });
    }
  });
}

final class _Cpf extends Validator<String> {
  const _Cpf();

  @override
  ValidationError? validate(String value, _) =>
      value.length == 11 ? null : ValidationError('cpf');

  @override
  bool operator ==(Object other) => other is _Cpf;

  @override
  int get hashCode => (_Cpf).hashCode;
}

final class _Even extends Validator<int> {
  const _Even();

  @override
  ValidationError? validate(int value, _) =>
      value.isEven ? null : ValidationError('even');
}

final class _Upper implements Validator<String> {
  const _Upper();

  @override
  Set<FieldPath> get reads => const {};

  @override
  ValidationError? validate(String value, _) =>
      value == value.toUpperCase() ? null : ValidationError('upper');
}
