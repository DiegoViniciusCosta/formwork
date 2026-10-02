import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide isIn, matches;

FieldPath p(String path) => FieldPath(path);

void main() {
  const engine = FormEngine();

  FormSnapshot form(List<FieldDef<Object?>> defs,
          [Map<String, Object?> values = const {}]) =>
      engine.registerAll(engine.initial(initialValues: values), defs);

  group('the payload is nested JSON (0009 §2)', () {
    test('groups become objects, in registration order', () {
      final s = form([
        TextFieldDef('name'),
        TextFieldDef('address.street'),
        TextFieldDef('address.geo.zone'),
        TextFieldDef('address.zipCode'),
      ], {
        'name': 'Ana',
        'address.street': 'Rua A',
        'address.geo.zone': 'Sul',
        'address.zipCode': '01000',
      });
      expect(s.payload(), {
        'name': 'Ana',
        'address': {
          'street': 'Rua A',
          'geo': {'zone': 'Sul'},
          'zipCode': '01000',
        },
      });
      expect(s.payload()['address'], isA<Map<String, Object?>>());
    });

    test('a hidden field is left out, and so is a group with none visible', () {
      final s = form([
        TextFieldDef('hide'),
        TextFieldDef('address.street', visibleWhen: eq('hide', 'no')),
        TextFieldDef('other.note', visibleWhen: eq('hide', 'no')),
        TextFieldDef('other.kept'),
      ], {
        'hide': 'yes',
      });
      expect(s.payload(), {
        'hide': 'yes',
        'other': {'kept': null},
      });
    });

    test('submit returns the nested payload', () {
      final s =
          form([TextFieldDef('address.zipCode')], {'address.zipCode': '01000'});
      expect(engine.submit(s).payload, {
        'address': {'zipCode': '01000'},
      });
    });
  });

  group('initial values take the payload shape (0009 §2)', () {
    test('a field finds its value through nested objects', () {
      final s = form([
        TextFieldDef('address.zipCode'),
        TextFieldDef('address.geo.zone'),
      ], {
        'address': {
          'zipCode': '01000',
          'geo': {'zone': 'Sul'},
        },
      });
      expect(s.stateOf(TextFieldDef('address.zipCode'))!.value, '01000');
      expect(s.stateOf(TextFieldDef('address.geo.zone'))!.value, 'Sul');
    });

    test('a flat key wins over the nested one', () {
      final zip = TextFieldDef('address.zipCode');
      final s = form([
        zip
      ], {
        'address': {'zipCode': 'nested'},
        'address.zipCode': 'flat',
      });
      expect(s.stateOf(zip)!.value, 'flat');
    });

    test('the payload round-trips as initial values', () {
      final defs = [
        TextFieldDef('name'),
        TextFieldDef('address.street'),
        TextFieldDef('address.zipCode'),
      ];
      final first = form(defs, {
        'name': 'Ana',
        'address.street': 'Rua A',
        'address.zipCode': '01000',
      });
      final again = form(defs, first.payload());
      expect(again.payload(), first.payload());
      for (final def in defs) {
        expect(again.stateOf(def)!.dirty, isFalse);
      }
    });

    test('a field whose value is a map keeps it whole', () {
      final where = _Place('where');
      final s = form([
        where
      ], {
        'where': {'text': 'here'},
      });
      expect(s.stateOf(where)!.value, 'here');
    });

    test('a condition reads a nested value of a path outside the form', () {
      final note = TextFieldDef('note', visibleWhen: eq('plan.kind', 'pro'));
      final s = form([
        note
      ], {
        'plan': {'kind': 'pro'},
      });
      expect(s.stateOf(note)!.visible, isTrue);
    });
  });

  group('rules read fields, not groups (decision 29)', () {
    test('a rule reading a group registered before it throws', () {
      final s = form([TextFieldDef('address.zipCode')]);
      expect(
        () => engine.register(
            s, TextFieldDef('note', visibleWhen: not(empty('address')))),
        throwsArgumentError,
      );
    });

    test('a group registered after a rule that reads it throws', () {
      final s =
          form([TextFieldDef('note', visibleWhen: not(empty('address')))]);
      expect(() => engine.register(s, TextFieldDef('address.zipCode')),
          throwsArgumentError);
    });

    test('a cross-field validator reading a group throws', () {
      expect(
        () => form([
          TextFieldDef('address.zipCode'),
          TextFieldDef('confirm',
              validators: [matches(TextFieldDef('address'))]),
        ]),
        throwsArgumentError,
      );
    });

    test('in one batch, whatever the order', () {
      expect(
        () => form([
          TextFieldDef('note', visibleWhen: not(empty('address'))),
          TextFieldDef('address.zipCode'),
        ]),
        throwsArgumentError,
      );
    });

    test('reading a field inside a group is fine', () {
      final note =
          TextFieldDef('note', visibleWhen: not(empty('address.zipCode')));
      var s = form([TextFieldDef('address.zipCode'), note]);
      expect(s.stateOf(note)!.visible, isFalse);
      s = engine.change(s, p('address.zipCode'), '01000');
      expect(s.stateOf(note)!.visible, isTrue);
    });

    test('a path that is gone stops being a group', () {
      var s = form([TextFieldDef('address.zipCode')]);
      s = engine.unregister(s, p('address.zipCode'));
      final note = TextFieldDef('note', visibleWhen: not(empty('address')));
      expect(engine.register(s, note).stateOf(note), isNotNull);
    });
  });

  group('a key is a field or a group, not both', () {
    test('a field inside a field throws', () {
      expect(
        () => form([TextFieldDef('address'), TextFieldDef('address.zipCode')]),
        throwsArgumentError,
      );
    });

    test('a field at a group path throws', () {
      expect(
        () => form([TextFieldDef('address.zipCode'), TextFieldDef('address')]),
        throwsArgumentError,
      );
    });

    test('a list item path throws until lists ship', () {
      expect(() => form([TextFieldDef('dependents[#1].name')]),
          throwsArgumentError);
      expect(() => form([TextFieldDef('dependents[0].name')]),
          throwsArgumentError);
    });

    test('a failed batch registers nothing', () {
      final before = form([TextFieldDef('name')]);
      expect(
        () => engine.registerAll(
            before, [TextFieldDef('address.zipCode'), TextFieldDef('address')]),
        throwsArgumentError,
      );
      expect(before.stateOf(TextFieldDef('address.zipCode')), isNull);
    });
  });

  group('catalog groups (0009 §1)', () {
    test('a group expands into fields with its key as prefix, nested', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'name', 'type': 'text'},
          {
            'key': 'address',
            'type': 'group',
            'fields': [
              {'key': 'zipCode', 'type': 'text', 'required': true},
              {
                'key': 'geo',
                'type': 'group',
                'fields': [
                  {'key': 'zone', 'type': 'text'},
                ],
              },
            ],
          },
          {'key': 'after', 'type': 'text'},
        ],
      });
      expect([for (final f in catalog.fields) '${f.path}'],
          ['name', 'address.zipCode', 'address.geo.zone', 'after']);
      expect(catalog.fields[1].required, isTrue);
      expect(catalog.issues, isEmpty);
    });

    test('conditions inside a group use full paths', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'address',
            'type': 'group',
            'fields': [
              {'key': 'country', 'type': 'text'},
              {
                'key': 'state',
                'type': 'text',
                'visibleWhen': {
                  'eq': ['address.country', 'BR'],
                },
              },
            ],
          },
        ],
      });
      var s = engine.registerAll(engine.initial(), catalog.fields);
      final state = catalog.fields[1];
      expect(s.stateOf(state)!.visible, isFalse);
      s = engine.change(s, p('address.country'), 'BR');
      expect(s.stateOf(state)!.visible, isTrue);
    });

    test('a rule on a group is skipped and reported', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'a', 'type': 'text'},
          {
            'key': 'address',
            'type': 'group',
            'visibleWhen': {
              'eq': ['a', 'x'],
            },
            'fields': [
              {'key': 'zipCode', 'type': 'text'},
            ],
          },
        ],
      });
      expect(catalog.fields.map((f) => '${f.path}'), ['a', 'address.zipCode']);
      expect(catalog.fields[1].visibleWhen, isNull);
      expect(catalog.issues, [
        CatalogIssue(CatalogIssueKind.ruleOnGroup, p('address'), 'visibleWhen'),
      ]);
    });

    test('a field reading a group is skipped and reported', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'note',
            'type': 'text',
            'visibleWhen': {
              'empty': ['address'],
            },
          },
          {
            'key': 'address',
            'type': 'group',
            'fields': [
              {'key': 'zipCode', 'type': 'text'},
            ],
          },
        ],
      });
      expect(catalog.fields.map((f) => '${f.path}'), ['address.zipCode']);
      expect(catalog.issues, [
        CatalogIssue(CatalogIssueKind.readsGroup, p('note'), p('address')),
      ]);
    });

    test('a key that is both a field and a group is malformed', () {
      expect(
        () => FormCatalog.fromJson({
          'fields': [
            {'key': 'address.zipCode', 'type': 'text'},
            {
              'key': 'address',
              'type': 'group',
              'fields': [
                {'key': 'zipCode', 'type': 'text'},
              ],
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => FormCatalog.fromJson({
          'fields': [
            {'key': 'address', 'type': 'text'},
            {'key': 'address.zipCode', 'type': 'text'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('a malformed key inside a group is a FormatException', () {
      for (final key in ['a.b', 'x[0]']) {
        expect(
          () => FormCatalog.fromJson({
            'fields': [
              {
                'key': 'g',
                'type': 'group',
                'fields': [
                  {'key': key, 'type': 'text'},
                ],
              },
            ],
          }),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => FormCatalog.fromJson({
          'fields': [
            {'key': 'dependents[#1].name', 'type': 'text'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('missing data reads nested data', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'address',
            'type': 'group',
            'fields': [
              {'key': 'street', 'type': 'text', 'required': true},
              {'key': 'zipCode', 'type': 'text', 'required': true},
            ],
          },
        ],
      });
      expect(
        catalog.missingKeys({
          'address': {'street': 'Rua A'},
        }),
        {p('address.zipCode')},
      );
    });
  });
}

/// A field whose JSON is an object, not a group.
final class _Place extends FieldDef<String> {
  _Place(super.key)
      : super(
          codec: FieldCodec<String>(
            encode: (v) => {'text': v},
            decode: (j) => (j as Map)['text'] as String,
          ),
        );

  @override
  String get type => 'place';
}
