import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart';

final catalog = FormConfig.fromMap({
  'fields': [
    {'key': 'name', 'type': 'text', 'label': 'Name', 'required': true},
    {
      'key': 'maritalStatus',
      'type': 'dropdown',
      'label': 'Marital status',
      'required': true,
      'options': [
        {'value': 'single', 'label': 'Single'},
        {'value': 'married', 'label': 'Married'},
      ],
    },
    {
      'key': 'spouseName',
      'type': 'text',
      'label': 'Spouse name',
      'required': true,
      'visibleWhen': {'field': 'maritalStatus', 'equals': 'married'},
    },
    {
      'key': 'email',
      'type': 'email',
      'label': 'Email',
      'validators': [
        {'type': 'email'},
      ],
    },
  ],
});

List<String> keysOf(FormConfig c) => c.fields.map((f) => f.key).toList();

void main() {
  group('missingFields', () {
    test('asks only for required fields that are empty', () {
      final pending = missingFields(catalog, {'name': 'Maria'});
      expect(keysOf(pending), ['maritalStatus', 'spouseName']);
    });

    test('skips a dependent field when its rule is already false', () {
      final pending = missingFields(
        catalog,
        {'name': 'Maria', 'maritalStatus': 'single'},
      );
      expect(keysOf(pending), isEmpty);
    });

    test('asks for a value that is filled but invalid', () {
      final pending = missingFields(catalog, {
        'name': 'Maria',
        'maritalStatus': 'single',
        'email': 'broken',
      });
      expect(keysOf(pending), ['email']);
    });
  });

  group('FormEngine', () {
    final engine = FormEngine(config: catalog);

    test('errors show only after interaction or submit attempt', () {
      var s = engine.initial();
      expect(s.errorFor('name'), isNull);

      s = engine.change(s, 'name', '');
      expect(s.errorFor('name'), 'This field is required');
      expect(s.errorFor('maritalStatus'), isNull);

      final result = engine.submit(s);
      expect(result.payload, isNull);
      expect(
        result.snapshot.errorFor('maritalStatus'),
        'This field is required',
      );
    });

    test('hidden required field neither blocks submit nor enters payload', () {
      var s = engine.initial();
      s = engine.change(s, 'name', 'Maria');
      s = engine.change(s, 'maritalStatus', 'single');

      final result = engine.submit(s);
      expect(result.payload, {
        'name': 'Maria',
        'maritalStatus': 'single',
        'email': null,
      });
    });

    test('incremental validation matches full validation', () {
      var s = engine.initial();
      for (final (key, value) in [
        ('name', 'Maria'),
        ('maritalStatus', 'married'),
        ('spouseName', ''),
        ('maritalStatus', 'single'),
        ('name', ''),
        ('maritalStatus', 'married'),
        ('email', 'broken'),
      ]) {
        s = engine.change(s, key, value);
        final full = engine.initial(s.values);
        expect(s.errors, full.errors, reason: 'after $key=$value');
        expect(
          s.visibleFields.map((f) => f.key),
          full.visibleFields.map((f) => f.key),
          reason: 'after $key=$value',
        );
      }
    });
  });

  group('snapshot sharing', () {
    final engine = FormEngine(config: catalog);

    test('a change that leaves errors intact reuses the errors map', () {
      var s = engine.initial();
      s = engine.change(s, 'name', 'Maria');
      final before = s.errors;

      s = engine.change(s, 'name', 'Mariana');

      expect(identical(s.errors, before), isTrue);
    });

    test('a controller change that keeps every error reuses the map', () {
      // maritalStatus has a dependent; staying off 'married' keeps
      // spouseName hidden, so no recomputed error changes.
      var s = engine.change(engine.initial(), 'maritalStatus', 'single');
      final before = s.errors;

      s = engine.change(s, 'maritalStatus', 'divorced');

      expect(identical(s.errors, before), isTrue);
    });

    test('a change that alters an error builds a new errors map', () {
      final s1 = engine.change(engine.initial(), 'name', 'Maria');
      final s2 = engine.change(s1, 'name', '');

      expect(identical(s2.errors, s1.errors), isFalse);
      expect(s1.errors.containsKey('name'), isFalse);
      expect(s2.errors['name'], 'This field is required');
    });

    test('snapshot maps are read-only', () {
      final s1 = engine.initial();
      final s2 = engine.change(s1, 'name', 'Maria');
      for (final s in [s1, s2]) {
        expect(() => s.values['name'] = 'x', throwsUnsupportedError);
        expect(() => s.errors['name'] = 'x', throwsUnsupportedError);
      }
    });

    test('touched keys are read-only', () {
      final s0 = engine.initial();
      final s1 = engine.change(s0, 'name', 'Maria');
      final s2 = engine.change(s1, 'name', 'Mariana');
      final s3 = engine.submit(s2).snapshot;

      for (final s in [s0, s1, s2, s3]) {
        expect(() => s.touched.add('email'), throwsUnsupportedError);
      }
      expect(s1.touched, {'name'});
    });

    test('a change never alters the previous snapshot', () {
      final s1 = engine.change(engine.initial(), 'name', 'Maria');
      final values = Map.of(s1.values);
      final errors = Map.of(s1.errors);

      engine.change(s1, 'name', '');
      engine.change(s1, 'maritalStatus', 'married');

      expect(s1.values, values);
      expect(s1.errors, errors);
    });
  });

  group('visibility chains', () {
    // hasVehicle -> vehicleType -> licensePlate
    final chain = FormConfig.fromMap({
      'fields': [
        {'key': 'hasVehicle', 'type': 'checkbox'},
        {
          'key': 'vehicleType',
          'type': 'dropdown',
          'required': true,
          'visibleWhen': {'field': 'hasVehicle', 'equals': true},
        },
        {
          'key': 'licensePlate',
          'type': 'text',
          'required': true,
          'visibleWhen': {'field': 'vehicleType', 'equals': 'car'},
        },
      ],
    });
    final engine = FormEngine(config: chain);

    test('hiding a field hides the fields that depend on it', () {
      var s = engine.initial();
      s = engine.change(s, 'hasVehicle', true);
      s = engine.change(s, 'vehicleType', 'car');
      expect(keysOf(FormConfig(s.visibleFields)), [
        'hasVehicle',
        'vehicleType',
        'licensePlate',
      ]);

      s = engine.change(s, 'hasVehicle', false);

      expect(keysOf(FormConfig(s.visibleFields)), ['hasVehicle']);
      expect(s.errors, isEmpty);
      expect(engine.submit(s).payload, {'hasVehicle': false});
    });

    test('showing a field again restores its dependents', () {
      var s = engine.initial({'vehicleType': 'car'});
      expect(keysOf(FormConfig(s.visibleFields)), ['hasVehicle']);

      s = engine.change(s, 'hasVehicle', true);

      expect(keysOf(FormConfig(s.visibleFields)), [
        'hasVehicle',
        'vehicleType',
        'licensePlate',
      ]);
      expect(s.errors.keys, ['licensePlate']);
    });

    test('a controller outside the form is judged by its value only', () {
      final narrowed = FormEngine(config: FormConfig([chain.fields.last]));
      final s = narrowed.initial({'vehicleType': 'car'});
      expect(keysOf(FormConfig(s.visibleFields)), ['licensePlate']);
    });

    test('incremental validation matches full validation', () {
      var s = engine.initial();
      for (final (key, value) in [
        ('hasVehicle', true),
        ('vehicleType', 'car'),
        ('licensePlate', ''),
        ('hasVehicle', false),
        ('vehicleType', 'bike'),
        ('hasVehicle', true),
        ('vehicleType', 'car'),
        ('hasVehicle', false),
      ]) {
        s = engine.change(s, key, value);
        final full = engine.initial(s.values);
        expect(s.errors, full.errors, reason: 'after $key=$value');
        expect(
          s.visibleFields.map((f) => f.key),
          full.visibleFields.map((f) => f.key),
          reason: 'after $key=$value',
        );
      }
    });

    test('a visibility cycle does not hang', () {
      final cycle = FormConfig.fromMap({
        'fields': [
          {
            'key': 'a',
            'type': 'text',
            'visibleWhen': {'field': 'b', 'equals': 'x'},
          },
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {'field': 'a', 'equals': 'x'},
          },
        ],
      });
      // How a cycle resolves is left to design doc 0001, which plans to
      // reject cycles at build time. Here it only has to terminate.
      FormEngine(config: cycle).initial();
      missingFields(cycle, {});
    });

    test('missingFields skips a chain whose root is already false', () {
      final pending = missingFields(
        chain,
        {'hasVehicle': false, 'vehicleType': 'car'},
      );
      expect(keysOf(pending), isEmpty);
    });

    test('missingFields drops a chain hidden by an empty optional root', () {
      // hasVehicle is optional and empty, so it is not asked, and the whole
      // chain below it stays hidden.
      expect(keysOf(missingFields(chain, {})), isEmpty);
    });

    test('missingFields keeps a chain whose root is still asked', () {
      final requiredRoot = FormConfig([
        const FieldConfig(
          key: 'hasVehicle',
          type: 'checkbox',
          label: '',
          required: true,
        ),
        ...chain.fields.skip(1),
      ]);
      expect(keysOf(missingFields(requiredRoot, {})), [
        'hasVehicle',
        'vehicleType',
        'licensePlate',
      ]);
    });
  });

  group('missing data (design doc 0003)', () {
    // hasVehicle -> vehicleType -> licensePlate, with a yes/no root: a
    // required checkbox would count "no" (false) as empty.
    final renewal = FormConfig.fromMap({
      'fields': [
        {'key': 'hasVehicle', 'type': 'dropdown', 'required': true},
        {
          'key': 'vehicleType',
          'type': 'dropdown',
          'required': true,
          'visibleWhen': {'field': 'hasVehicle', 'equals': 'yes'},
        },
        {
          'key': 'licensePlate',
          'type': 'text',
          'required': true,
          'visibleWhen': {'field': 'vehicleType', 'equals': 'car'},
        },
      ],
    });
    const stored = {'vehicleType': 'car'};

    test('a known field between two missing keys is asked', () {
      expect(keysOf(missingFields(renewal, stored)), [
        'hasVehicle',
        'vehicleType',
        'licensePlate',
      ]);
    });

    test('answering "no" hides the chain and submits', () {
      final engine = FormEngine(config: missingFields(renewal, stored));
      var s = engine.initial(stored);
      s = engine.change(s, 'hasVehicle', 'no');

      expect(keysOf(FormConfig(s.visibleFields)), ['hasVehicle']);
      expect(engine.submit(s).payload, {'hasVehicle': 'no'});
    });

    test('a link shows its stored value when it becomes visible', () {
      final engine = FormEngine(config: missingFields(renewal, stored));
      final s = engine.change(engine.initial(stored), 'hasVehicle', 'yes');

      expect(keysOf(FormConfig(s.visibleFields)), [
        'hasVehicle',
        'vehicleType',
        'licensePlate',
      ]);
      expect(s.values['vehicleType'], 'car');
    });

    test('missingKeys never contains links', () {
      expect(missingKeys(renewal, stored), {'hasVehicle', 'licensePlate'});
    });

    test('missingKeys matches missingFields when there are no links', () {
      for (final data in <Map<String, Object?>>[
        {'name': 'Maria'},
        {'name': 'Maria', 'maritalStatus': 'single'},
        {'name': 'Maria', 'maritalStatus': 'single', 'email': 'broken'},
      ]) {
        expect(
          missingKeys(catalog, data),
          keysOf(missingFields(catalog, data)).toSet(),
          reason: '$data',
        );
      }
    });

    test('a known field with nothing missing above it stays hidden', () {
      final known = {'hasVehicle': 'yes', 'vehicleType': 'car'};
      expect(keysOf(missingFields(renewal, known)), ['licensePlate']);
    });

    test('catalog order does not change the result', () {
      final reversed = FormConfig(renewal.fields.reversed.toList());

      expect(missingKeys(reversed, stored), missingKeys(renewal, stored));
      expect(keysOf(missingFields(reversed, stored)), [
        'licensePlate',
        'vehicleType',
        'hasVehicle',
      ]);
    });

    test('two consecutive known fields between missing keys are asked', () {
      final longChain = FormConfig.fromMap({
        'fields': [
          {'key': 'a', 'type': 'dropdown', 'required': true},
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {'field': 'a', 'equals': 'yes'},
          },
          {
            'key': 'c',
            'type': 'text',
            'visibleWhen': {'field': 'b', 'equals': 'x'},
          },
          {
            'key': 'd',
            'type': 'text',
            'required': true,
            'visibleWhen': {'field': 'c', 'equals': 'y'},
          },
        ],
      });

      expect(
        keysOf(missingFields(longChain, {'b': 'x', 'c': 'y'})),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('a cycle among known ancestors does not hang', () {
      // a (missing) reads b; b and c are known and read each other.
      final cycle = FormConfig.fromMap({
        'fields': [
          {
            'key': 'a',
            'type': 'text',
            'required': true,
            'visibleWhen': {'field': 'b', 'equals': 'x'},
          },
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {'field': 'c', 'equals': 'x'},
          },
          {
            'key': 'c',
            'type': 'text',
            'visibleWhen': {'field': 'b', 'equals': 'x'},
          },
        ],
      });
      const data = {'b': 'x', 'c': 'x'};

      expect(missingKeys(cycle, data), {'a'});
      expect(keysOf(missingFields(cycle, data)), ['a']);
    });
  });

  test('unknown validator is skipped and reported', () {
    final unknown = <String>[];
    final registry = ValidatorRegistry(onUnknown: unknown.add);
    final field = FieldConfig.fromMap({
      'key': 'x',
      'type': 'text',
      'validators': [
        {'type': 'doesNotExist'},
      ],
    });

    expect(registry.buildFor(field), isNull);
    expect(unknown, ['doesNotExist']);
  });

  test('unsupported field types are dropped and reported', () {
    final dropped = <String>[];
    final config = FormConfig.fromMap(
      {
        'fields': [
          {'key': 'a', 'type': 'text'},
          {'key': 'b', 'type': 'signature'},
        ],
      },
      supportedTypes: {'text'},
      onUnsupported: (f) => dropped.add(f.key),
    );

    expect(keysOf(config), ['a']);
    expect(dropped, ['b']);
  });
}
