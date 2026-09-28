import 'package:formwork_core/formwork_core.dart'
    hide FormEngine, FormSnapshot, ValidatorRegistry;
import 'package:formwork_core/src/catalog/form_catalog.dart';
import 'package:formwork_core/src/catalog/missing_data.dart';
import 'package:formwork_core/src/engine/engine.dart';
import 'package:test/test.dart';

const engine = FormEngine();

FieldPath p(String path) => FieldPath(path);

List<String> keysOf(FormCatalog c) =>
    [for (final def in c.fields) def.path.toString()];

Set<FieldPath> paths(Iterable<String> keys) => {for (final k in keys) p(k)};

Map<String, Object?> choice(String key, List<String> values,
        {bool required = false, Object? visibleWhen}) =>
    {
      'key': key,
      'type': 'dropdown',
      'required': required,
      'options': [
        for (final v in values) {'value': v, 'label': v},
      ],
      if (visibleWhen != null) 'visibleWhen': visibleWhen,
    };

final profile = FormCatalog.fromJson({
  'fields': [
    {'key': 'name', 'type': 'text', 'required': true},
    choice('maritalStatus', ['single', 'married'], required: true),
    {
      'key': 'spouseName',
      'type': 'text',
      'required': true,
      'visibleWhen': {
        'eq': ['maritalStatus', 'married'],
      },
    },
    {
      'key': 'email',
      'type': 'text',
      'validators': [
        {'type': 'email'},
      ],
    },
  ],
});

// hasVehicle -> vehicleType -> licensePlate, with a yes/no root: a
// required checkbox would count "no" (false) as empty.
final renewal = FormCatalog.fromJson({
  'fields': [
    choice('hasVehicle', ['yes', 'no'], required: true),
    choice('vehicleType', ['car', 'bike'],
        required: true,
        visibleWhen: {
          'eq': ['hasVehicle', 'yes'],
        }),
    {
      'key': 'licensePlate',
      'type': 'text',
      'required': true,
      'visibleWhen': {
        'eq': ['vehicleType', 'car'],
      },
    },
  ],
});
const stored = {'vehicleType': 'car'};

void main() {
  group('onlyMissing', () {
    test('asks only for required fields that are empty', () {
      expect(keysOf(profile.onlyMissing({'name': 'Maria'})),
          ['maritalStatus', 'spouseName']);
    });

    test('skips a dependent field when its rule is already false', () {
      expect(
          keysOf(profile.onlyMissing({
            'name': 'Maria',
            'maritalStatus': 'single',
          })),
          isEmpty);
    });

    test('asks for a value that is filled but invalid', () {
      expect(
          keysOf(profile.onlyMissing({
            'name': 'Maria',
            'maritalStatus': 'single',
            'email': 'broken',
          })),
          ['email']);
    });

    test('asks for a value its codec cannot decode', () {
      expect(
          keysOf(profile.onlyMissing({
            'name': 'Maria',
            'maritalStatus': 'widowed',
          })),
          ['maritalStatus', 'spouseName']);
    });

    test('a disabled field is not missing, whatever its value', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'cpf',
            'type': 'number',
            'required': true,
            'enabledWhen': {
              'eq': ['editable', true],
            },
          },
        ],
      });
      expect(catalog.missingKeys({'editable': false}), isEmpty);
      expect(catalog.missingKeys({'editable': false, 'cpf': 'abc'}), isEmpty);
      expect(catalog.missingKeys({'editable': true}), paths(['cpf']));
    });

    test('keeps the issues and schema version of the catalog', () {
      final catalog = FormCatalog.fromJson({
        'schemaVersion': 3,
        'fields': [
          {'key': 'map', 'type': 'map'},
          {'key': 'a', 'type': 'text', 'required': true},
        ],
      });
      final narrowed = catalog.onlyMissing({});
      expect(narrowed.schemaVersion, 3);
      expect(narrowed.issues, catalog.issues);
    });
  });

  group('chains (design doc 0003)', () {
    test('a known field between two missing keys is asked', () {
      expect(keysOf(renewal.onlyMissing(stored)),
          ['hasVehicle', 'vehicleType', 'licensePlate']);
    });

    test('answering "no" hides the chain and submits', () {
      var s = engine.registerAll(engine.initial(initialValues: stored),
          renewal.onlyMissing(stored).fields);
      s = engine.change(s, p('hasVehicle'), 'no');
      expect(s.visibleFields.map((d) => d.path), [p('hasVehicle')]);
      expect(engine.submit(s).payload, {'hasVehicle': 'no'});
    });

    test('a link shows its stored value when it becomes visible', () {
      var s = engine.registerAll(engine.initial(initialValues: stored),
          renewal.onlyMissing(stored).fields);
      s = engine.change(s, p('hasVehicle'), 'yes');
      expect(s.visibleFields.map((d) => d.path),
          [p('hasVehicle'), p('vehicleType'), p('licensePlate')]);
      expect(s.valueOf(renewal.fields[1]), 'car');
    });

    test('missingKeys never contains links', () {
      expect(
          renewal.missingKeys(stored), paths(['hasVehicle', 'licensePlate']));
    });

    test('missingKeys matches onlyMissing when there are no links', () {
      for (final data in <Map<String, Object?>>[
        {'name': 'Maria'},
        {'name': 'Maria', 'maritalStatus': 'single'},
        {'name': 'Maria', 'maritalStatus': 'single', 'email': 'broken'},
      ]) {
        expect(
            profile.missingKeys(data), paths(keysOf(profile.onlyMissing(data))),
            reason: '$data');
      }
    });

    test('a known field with nothing missing above it stays hidden', () {
      expect(
          keysOf(
              renewal.onlyMissing({'hasVehicle': 'yes', 'vehicleType': 'car'})),
          ['licensePlate']);
    });

    test('an empty optional root hides its chain', () {
      final optionalRoot = FormCatalog.fromJson({
        'fields': [
          choice('hasVehicle', ['yes', 'no']),
          choice('vehicleType', ['car', 'bike'],
              required: true,
              visibleWhen: {
                'eq': ['hasVehicle', 'yes'],
              }),
        ],
      });
      expect(keysOf(optionalRoot.onlyMissing({})), isEmpty);
    });

    test('catalog order does not change the result', () {
      final reversed = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'licensePlate',
            'type': 'text',
            'required': true,
            'visibleWhen': {
              'eq': ['vehicleType', 'car'],
            },
          },
          choice('vehicleType', ['car', 'bike'],
              required: true,
              visibleWhen: {
                'eq': ['hasVehicle', 'yes'],
              }),
          choice('hasVehicle', ['yes', 'no'], required: true),
        ],
      });
      expect(reversed.missingKeys(stored), renewal.missingKeys(stored));
      expect(keysOf(reversed.onlyMissing(stored)),
          ['licensePlate', 'vehicleType', 'hasVehicle']);
    });

    test('two consecutive known fields between missing keys are asked', () {
      final longChain = FormCatalog.fromJson({
        'fields': [
          choice('a', ['yes', 'no'], required: true),
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {
              'eq': ['a', 'yes'],
            },
          },
          {
            'key': 'c',
            'type': 'text',
            'visibleWhen': {
              'eq': ['b', 'x'],
            },
          },
          {
            'key': 'd',
            'type': 'text',
            'required': true,
            'visibleWhen': {
              'eq': ['c', 'y'],
            },
          },
        ],
      });
      expect(keysOf(longChain.onlyMissing({'b': 'x', 'c': 'y'})),
          ['a', 'b', 'c', 'd']);
    });

    test('a condition on two fields links through either of them', () {
      // d is shown when b or c holds; b hangs from missing a, c is known
      // and hangs from nothing missing.
      final graph = FormCatalog.fromJson({
        'fields': [
          choice('a', ['yes', 'no'], required: true),
          {
            'key': 'b',
            'type': 'text',
            'visibleWhen': {
              'eq': ['a', 'yes'],
            },
          },
          {'key': 'c', 'type': 'text'},
          {
            'key': 'd',
            'type': 'text',
            'required': true,
            'visibleWhen': {
              'any': [
                {
                  'eq': ['b', 'x'],
                },
                {
                  'eq': ['c', 'x'],
                },
              ],
            },
          },
        ],
      });
      expect(keysOf(graph.onlyMissing({'b': 'x', 'c': 'x'})), ['a', 'b', 'd']);
    });
  });
}
