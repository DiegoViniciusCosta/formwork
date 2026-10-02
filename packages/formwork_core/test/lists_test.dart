import 'dart:math';

import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide isIn, matches;

FieldPath p(String path) => FieldPath(path);

final dependents = ListFieldDef(
  'dependents',
  itemFields: (item) => [
    TextFieldDef('$item.name', required: true),
    NumberFieldDef('$item.age'),
  ],
  maxItems: 3,
);

void main() {
  const engine = FormEngine();

  FormSnapshot form(List<FieldDef<Object?>> defs,
          [Map<String, Object?> values = const {}]) =>
      engine.registerAll(engine.initial(initialValues: values), defs);

  List<String> ids(FormSnapshot s, [ListFieldDef? list]) =>
      s.valueOf(list ?? dependents)!;

  FieldPath item(FormSnapshot s, int index) =>
      dependents.itemPath(ids(s)[index]);

  FieldDef<Object?> nameAt(FormSnapshot s, int index) =>
      dependents.fieldsAt(ids(s)[index]).first;

  group('items (0009 §3 and §4)', () {
    test('a list starts empty, and addItem registers the item fields', () {
      var s = form([dependents]);
      expect(ids(s), isEmpty);
      s = engine.addItem(s, dependents.path, values: {'name': 'Ana'});
      expect(ids(s), hasLength(1));
      final name = nameAt(s, 0);
      expect(name.path, p('dependents[#${ids(s).single}].name'));
      expect(s.stateOf(name)!.value, 'Ana');
      expect(s.stateOf(dependents.fieldsAt(ids(s).single)[1])!.value, isNull);
    });

    test('ids come from a counter and are never reused', () {
      var s = form([dependents]);
      s = engine.addItem(s, dependents.path);
      final first = ids(s).single;
      s = engine.removeItem(s, item(s, 0));
      s = engine.addItem(s, dependents.path);
      expect(ids(s).single, isNot(first));
    });

    test('insert, remove and move keep every other item identical', () {
      var s = form([dependents]);
      for (final n in ['a', 'b', 'c']) {
        s = engine.addItem(s, dependents.path, values: {'name': n});
      }
      final b = s.stateOf(nameAt(s, 1));
      final c = s.stateOf(nameAt(s, 2));

      s = engine.removeItem(s, item(s, 0));
      expect(identical(s.stateOf(nameAt(s, 0)), b), isTrue);
      expect(identical(s.stateOf(nameAt(s, 1)), c), isTrue);

      s = engine.addItem(s, dependents.path, values: {'name': 'z'}, at: 0);
      expect(identical(s.stateOf(nameAt(s, 1)), b), isTrue);

      s = engine.moveItem(s, item(s, 0), 2);
      expect([for (var i = 0; i < 3; i++) s.stateOf(nameAt(s, i))!.value],
          ['b', 'c', 'z']);
      expect(identical(s.stateOf(nameAt(s, 0)), b), isTrue);
      expect(s.changedPaths, {dependents.path});
    });

    test('a removed item is forgotten', () {
      var s = form([dependents]);
      s = engine.addItem(s, dependents.path, values: {'name': 'Ana'});
      final name = nameAt(s, 0);
      s = engine.removeItem(s, item(s, 0));
      expect(s.stateOf(name), isNull);
      expect(s.payload(), {'dependents': []});
    });

    test('each operation touches the list, and dirty compares ids', () {
      var s = form([dependents]);
      expect(s.stateOf(dependents)!.dirty, isFalse);
      s = engine.addItem(s, dependents.path);
      expect(s.stateOf(dependents)!.touched, isTrue);
      expect(s.stateOf(dependents)!.dirty, isTrue);
      s = engine.removeItem(s, item(s, 0));
      expect(s.stateOf(dependents)!.dirty, isFalse);
    });

    test('change on a list throws', () {
      final s = form([dependents]);
      expect(
          () => engine.change(s, dependents.path, ['9']), throwsArgumentError);
    });

    test('item fields must be inside the item', () {
      final bad = ListFieldDef('bad', itemFields: (_) => [TextFieldDef('x')]);
      expect(() => engine.addItem(form([bad]), bad.path), throwsArgumentError);
    });

    test('an operation on something that is not a list throws', () {
      final s = form([TextFieldDef('name')]);
      expect(() => engine.addItem(s, p('name')), throwsArgumentError);
      expect(() => engine.removeItem(s, p('name[#1]')), throwsArgumentError);
    });

    test('duplicate item fields throw', () {
      final dup = ListFieldDef('d',
          itemFields: (i) => [TextFieldDef('$i.x'), TextFieldDef('$i.x')]);
      expect(() => engine.addItem(form([dup]), dup.path), throwsArgumentError);
      expect(
        () => FormCatalog.fromJson({
          'fields': [
            {
              'key': 'd',
              'type': 'list',
              'itemFields': [
                {'key': 'x', 'type': 'text'},
                {'key': 'x', 'type': 'text'},
              ],
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('a list where another kind of field was retired starts afresh', () {
      var s = form([TextFieldDef('l')], {'l': 'x'});
      s = engine.unregister(s, p('l'));
      final list = ListFieldDef('l', itemFields: (i) => [TextFieldDef('$i.y')]);
      s = engine.register(s, list);
      expect(s.valueOf(list), isEmpty);

      s = engine.addItem(s, list.path);
      s = engine.unregister(s, list.path);
      s = engine.register(s, TextFieldDef('l'));
      expect(s.valueOf(TextFieldDef('l')), 'x'); // its initial value again
      expect(s.undecodable, isEmpty);
    });

    test('initial data that is not an array is listed as undecodable', () {
      final s = form([dependents], {'dependents': 'oops'});
      expect(ids(s), isEmpty);
      expect(s.undecodable, {p('dependents'): 'oops'});
    });

    test('registering an item path directly still throws', () {
      expect(() => form([TextFieldDef('dependents[#1].name')]),
          throwsArgumentError);
    });
  });

  group('validation', () {
    test('required, minItems and maxItems judge the count', () {
      final list = ListFieldDef('l',
          itemFields: (i) => [TextFieldDef('$i.x')], minItems: 2, maxItems: 3);
      final required = ListFieldDef('r',
          required: true, itemFields: (i) => [TextFieldDef('$i.x')]);
      var s = form([list, required]);
      expect(s.stateOf(list)!.error,
          ValidationError('minItems', params: {'min': 2}));
      expect(s.stateOf(required)!.error!.code, 'required');
      for (var i = 0; i < 4; i++) {
        s = engine.addItem(s, list.path);
      }
      expect(s.stateOf(list)!.error,
          ValidationError('maxItems', params: {'max': 3}));
      s = engine.removeItem(s, list.itemPath(s.valueOf(list)!.first));
      expect(s.stateOf(list)!.error, isNull);
    });

    test('item errors count, and block submit', () {
      var s = form([dependents]);
      s = engine.addItem(s, dependents.path);
      expect(s.status.errorCount, 1);
      expect(engine.submit(s).payload, isNull);
      s = engine.change(s, nameAt(s, 0).path, 'Ana');
      expect(engine.submit(s).payload, isNotNull);
    });

    test('a hidden list hides its items, and a disabled one disables them', () {
      final list = ListFieldDef('l',
          visibleWhen: eq('show', 'yes'),
          enabledWhen: eq('edit', 'yes'),
          itemFields: (i) => [TextFieldDef('$i.x', required: true)]);
      var s = form([TextFieldDef('show'), TextFieldDef('edit'), list],
          {'show': 'yes', 'edit': 'yes'});
      s = engine.addItem(s, list.path);
      final x = list.fieldsAt(s.valueOf(list)!.single).single;
      expect(s.status.errorCount, 1);

      s = engine.change(s, p('show'), 'no');
      expect(s.stateOf(x)!.visible, isFalse);
      expect(s.status.errorCount, 0);
      expect(s.payload().containsKey('l'), isFalse);

      s = engine.change(s, p('show'), 'yes');
      s = engine.change(s, p('edit'), 'no');
      expect(s.stateOf(x)!.enabled, isFalse);
      expect(s.status.errorCount, 0);
    });

    test('item fields may read paths outside the list', () {
      final list = ListFieldDef('l',
          itemFields: (i) =>
              [TextFieldDef('$i.x', visibleWhen: eq('mode', 'full'))]);
      var s = form([TextFieldDef('mode'), list]);
      s = engine.addItem(s, list.path);
      final x = list.fieldsAt(s.valueOf(list)!.single).single;
      expect(s.stateOf(x)!.visible, isFalse);
      s = engine.change(s, p('mode'), 'full');
      expect(s.stateOf(x)!.visible, isTrue);
    });

    test('a rule reading a list throws (decision 29)', () {
      expect(
          () => form([
                dependents,
                TextFieldDef('x', visibleWhen: not(empty('dependents'))),
              ]),
          throwsArgumentError);
      expect(
          () => form([
                TextFieldDef('x', visibleWhen: not(empty('dependents'))),
                dependents,
              ]),
          throwsArgumentError);
    });
  });

  group('payload, initial values and order', () {
    test('the payload holds an array in item order', () {
      var s = form([TextFieldDef('owner'), dependents, TextFieldDef('after')],
          {'owner': 'Bia'});
      s = engine.addItem(s, dependents.path, values: {'name': 'a', 'age': 3});
      s = engine.addItem(s, dependents.path, values: {'name': 'b'}, at: 0);
      expect(s.payload(), {
        'owner': 'Bia',
        'dependents': [
          {'name': 'b', 'age': null},
          {'name': 'a', 'age': 3},
        ],
        'after': null,
      });
    });

    test('initial values with a list create its items', () {
      final s = form([
        dependents
      ], {
        'dependents': [
          {'name': 'a', 'age': 3},
          {'name': 'b'},
        ],
      });
      expect(ids(s), hasLength(2));
      expect(s.stateOf(nameAt(s, 1))!.value, 'b');
      expect(s.stateOf(dependents)!.dirty, isFalse);
      expect(s.payload(), {
        'dependents': [
          {'name': 'a', 'age': 3},
          {'name': 'b', 'age': null},
        ],
      });
    });

    test('item fields follow their list in visibleFields', () {
      var s = form([TextFieldDef('a'), dependents, TextFieldDef('b')]);
      s = engine.addItem(s, dependents.path);
      s = engine.addItem(s, dependents.path, at: 0);
      final first = dependents.fieldsAt(ids(s)[0]);
      final second = dependents.fieldsAt(ids(s)[1]);
      expect([
        for (final d in s.visibleFields) '${d.path}'
      ], [
        'a',
        'dependents',
        for (final d in [...first, ...second]) '${d.path}',
        'b',
      ]);
    });

    test('firstErrorPath follows item order', () {
      var s = form([dependents]);
      s = engine.addItem(s, dependents.path);
      s = engine.addItem(s, dependents.path, at: 0);
      s = engine.submit(s).snapshot;
      expect(s.firstErrorPath, nameAt(s, 0).path);
    });

    test('a list in a group nests', () {
      final list = ListFieldDef('family.kids',
          itemFields: (i) => [TextFieldDef('$i.name')]);
      var s = form([list]);
      s = engine.addItem(s, list.path, values: {'name': 'Ana'});
      expect(s.payload(), {
        'family': {
          'kids': [
            {'name': 'Ana'},
          ],
        },
      });
    });

    test('a group inside an item nests', () {
      final list = ListFieldDef('l',
          itemFields: (i) => [TextFieldDef('$i.contact.phone')]);
      var s = form([list]);
      s = engine.addItem(s, list.path, values: {
        'contact': {'phone': '1'},
      });
      expect(s.payload(), {
        'l': [
          {
            'contact': {'phone': '1'},
          },
        ],
      });
    });

    test('a list inside an item nests', () {
      final list = ListFieldDef('l',
          itemFields: (i) => [
                ListFieldDef('$i.tags',
                    itemFields: (t) => [TextFieldDef('$t.tag')]),
              ]);
      final s = form([
        list
      ], {
        'l': [
          {
            'tags': [
              {'tag': 'x'},
              {'tag': 'y'},
            ],
          },
        ],
      });
      expect(s.payload(), {
        'l': [
          {
            'tags': [
              {'tag': 'x'},
              {'tag': 'y'},
            ],
          },
        ],
      });
    });

    test('unregistering a list brings its items back with it', () {
      var s = form([dependents]);
      s = engine.addItem(s, dependents.path, values: {'name': 'Ana'});
      final name = nameAt(s, 0);
      s = engine.unregister(s, dependents.path);
      expect(s.stateOf(name), isNull);
      s = engine.register(s, dependents);
      expect(s.stateOf(name)!.value, 'Ana');
    });
  });

  group('server errors by index', () {
    FormSnapshot sending() {
      var s = form([
        dependents
      ], {
        'dependents': [
          {'name': 'a'},
          {'name': 'b'},
        ],
      });
      s = engine.submit(s).snapshot;
      return engine.startSubmitting(s);
    }

    test('land on the item at that index when the send started', () {
      var s = sending();
      final b = nameAt(s, 1);
      s = engine.moveItem(s, item(s, 1), 0); // b is first now
      s = engine.completeSubmit(
          s,
          ServerErrors(
              fields: {p('dependents[1].name'): ValidationError('x')}));
      expect(s.stateOf(b)!.error!.code, 'x');
      expect(s.stateOf(nameAt(s, 1))!.error, isNull);
    });

    test('an index with no item is discarded', () {
      final s = engine.completeSubmit(
          sending(),
          ServerErrors(
              fields: {p('dependents[5].name'): ValidationError('x')}));
      expect(s.status.errorCount, 0);
    });

    test('an item added during the send gets nothing', () {
      var s = sending();
      s = engine.removeItem(s, item(s, 1));
      s = engine.addItem(s, dependents.path);
      final added = nameAt(s, 1);
      s = engine.completeSubmit(
          s,
          ServerErrors(
              fields: {p('dependents[1].name'): ValidationError('x')}));
      expect(s.stateOf(added)!.error!.code, 'required'); // its own, local
    });

    test('an error on the list itself applies to the list', () {
      final s = engine.completeSubmit(sending(),
          ServerErrors(fields: {p('dependents'): ValidationError('tooMany')}));
      expect(s.stateOf(dependents)!.error!.code, 'tooMany');
    });
  });

  group('catalog lists', () {
    test('itemFields builds each item, and conditions read outside', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {'key': 'mode', 'type': 'text'},
          {
            'key': 'dependents',
            'type': 'list',
            'minItems': 1,
            'maxItems': 2,
            'itemFields': [
              {'key': 'name', 'type': 'text', 'required': true},
              {
                'key': 'note',
                'type': 'text',
                'visibleWhen': {
                  'eq': ['mode', 'full'],
                },
              },
            ],
          },
        ],
      });
      expect(catalog.issues, isEmpty);
      final list = catalog.fields[1] as ListFieldDef;
      expect(list.minItems, 1);
      expect(list.maxItems, 2);
      var s = engine.registerAll(engine.initial(), catalog.fields);
      s = engine.addItem(s, list.path, values: {'name': 'Ana'});
      final defs = list.fieldsAt(s.valueOf(list)!.single);
      expect(defs.map((d) => d.path.toString()),
          ['dependents[#1].name', 'dependents[#1].note']);
      expect(s.stateOf(defs[1])!.visible, isFalse);
    });

    test('an item field of an unknown type is reported once', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'l',
            'type': 'list',
            'itemFields': [
              {'key': 'x', 'type': 'nope'},
              {'key': 'y', 'type': 'text'},
            ],
          },
        ],
      });
      expect(catalog.issues, [
        CatalogIssue(CatalogIssueKind.unknownType, p('l[0].x'), 'nope'),
      ]);
      final list = catalog.fields.single as ListFieldDef;
      expect(list.fieldsAt('1').map((d) => '${d.path}'), ['l[#1].y']);
    });

    test('a field reading a list is skipped', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'l',
            'type': 'list',
            'itemFields': [
              {'key': 'y', 'type': 'text'},
            ],
          },
          {
            'key': 'x',
            'type': 'text',
            'visibleWhen': {
              'empty': ['l'],
            },
          },
        ],
      });
      expect(catalog.fields.map((f) => '${f.path}'), ['l']);
      expect(catalog.issues, [
        CatalogIssue(CatalogIssueKind.readsGroup, p('x'), p('l')),
      ]);
    });

    test('missing data asks a list as a whole, by its count', () {
      final catalog = FormCatalog.fromJson({
        'fields': [
          {
            'key': 'l',
            'type': 'list',
            'minItems': 1,
            'itemFields': [
              {'key': 'y', 'type': 'text', 'required': true},
            ],
          },
          {
            'key': 'opt',
            'type': 'list',
            'itemFields': [
              {'key': 'y', 'type': 'text'},
            ],
          },
        ],
      });
      expect(catalog.missingKeys({}), {p('l')});
      expect(
          catalog.missingKeys({
            'l': [
              {'y': ''},
            ],
          }),
          isEmpty);
    });
  });

  test('random operations equal building the same items from scratch', () {
    final random = Random(17);
    final list = ListFieldDef('l',
        maxItems: 4,
        itemFields: (i) => [
              TextFieldDef('$i.a', required: true, validators: [minLength(2)]),
              TextFieldDef('$i.b', visibleWhen: eq('mode', 'on')),
            ]);
    for (var round = 0; round < 100; round++) {
      var s = form([TextFieldDef('mode'), list]);
      for (var step = 0; step < 25; step++) {
        final items = s.valueOf(list)!;
        switch (random.nextInt(5)) {
          case 0:
            s = engine.addItem(s, list.path,
                values: {'a': _value(random)},
                at: random.nextInt(items.length + 1));
          case 1 when items.isNotEmpty:
            s = engine.removeItem(
                s, list.itemPath(items[random.nextInt(items.length)]));
          case 2 when items.isNotEmpty:
            s = engine.moveItem(
                s,
                list.itemPath(items[random.nextInt(items.length)]),
                random.nextInt(items.length));
          case 3 when items.isNotEmpty:
            final id = items[random.nextInt(items.length)];
            final field = list.fieldsAt(id)[random.nextInt(2)];
            s = engine.change(s, field.path, _value(random));
          default:
            s = engine.change(s, p('mode'), random.nextBool() ? 'on' : 'off');
        }

        // From scratch: the same items, added in order to a new form.
        final items2 = s.valueOf(list)!;
        var scratch = form([TextFieldDef('mode'), list],
            {'mode': s.valueOf(TextFieldDef('mode'))});
        for (final id in items2) {
          final defs = list.fieldsAt(id);
          scratch = engine.addItem(scratch, list.path, values: {
            'a': s.stateOf(defs[0])!.value,
            'b': s.stateOf(defs[1])!.value,
          });
        }
        final scratchIds = scratch.valueOf(list)!;
        for (var i = 0; i < items2.length; i++) {
          final mine = list.fieldsAt(items2[i]);
          final theirs = list.fieldsAt(scratchIds[i]);
          for (var f = 0; f < 2; f++) {
            final a = s.stateOf(mine[f])!;
            final b = scratch.stateOf(theirs[f])!;
            expect([a.value, a.visible, a.enabled, a.required, a.error],
                [b.value, b.visible, b.enabled, b.required, b.error]);
          }
        }
        expect(s.stateOf(list)!.error, scratch.stateOf(list)!.error);
        expect(s.status.errorCount, scratch.status.errorCount);
        expect(s.payload(), scratch.payload());
      }
    }
  });

  test('a change inside an item costs the same in a long list', () {
    int workFor(int size) {
      final counter = _Counter();
      final list = ListFieldDef('l',
          itemFields: (i) => [
                TextFieldDef('$i.x', validators: [counter])
              ]);
      var s = form([
        list
      ], {
        'l': [
          for (var i = 0; i < size; i++) {'x': 'v'},
        ],
      });
      counter.calls = 0;
      s = engine.change(s, list.fieldsAt(s.valueOf(list)![3]).single.path, 'w');
      return counter.calls + s.changedPaths.length;
    }

    expect(workFor(1000), workFor(10));
  });
}

Object? _value(Random random) => const [null, '', 'a', 'bc'][random.nextInt(4)];

final class _Counter extends Validator<String> {
  int calls = 0;

  @override
  ValidationError? validate(String value, _) {
    calls++;
    return null;
  }
}
