import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide isIn, matches;

FieldPath p(String path) => FieldPath(path);

List<Object> shape(LayoutChild child) => switch (child) {
      LayoutField(:final path) => ['$path'],
      LayoutNode(:final type, :final children) => [
          type,
          for (final c in children) shape(c),
        ],
    };

Map<String, Object?> catalogWith(List<Object?> layout) => {
      'fields': [
        {'key': 'fullName', 'type': 'text'},
        {'key': 'income', 'type': 'number'},
        {'key': 'maritalStatus', 'type': 'text'},
        {'key': 'spouseName', 'type': 'text'},
        {'key': 'weird', 'type': 'nope'},
        {
          'key': 'address',
          'type': 'group',
          'fields': [
            {'key': 'zipCode', 'type': 'text'},
          ],
        },
      ],
      'layout': layout,
    };

void main() {
  group('the model (0006 §5)', () {
    test('children take fields, paths and nodes', () {
      final name = TextFieldDef('name');
      final root = LayoutNode('root', children: [
        SectionNode(title: 'Personal', children: [
          name,
          RowNode(children: [p('a'), p('b')]),
        ]),
        p('c'),
      ]);
      expect(shape(root), [
        'root',
        [
          'section',
          ['name'],
          [
            'row',
            ['a'],
            ['b'],
          ],
        ],
        ['c'],
      ]);
      expect((root.children.first as LayoutNode)['title'], 'Personal');
      expect((root.children.first as SectionNode).title, 'Personal');
    });

    test('any other child throws', () {
      expect(() => RowNode(children: ['name']), throwsArgumentError);
    });

    test('a form has no layout unless it says so', () {
      expect(FormDef([TextFieldDef('a')]).layout, isNull);
    });
  });

  group('catalog layout', () {
    test('is read into a root node, with each node props', () {
      final catalog = FormCatalog.fromJson(catalogWith([
        {
          'type': 'section',
          'title': 'Personal data',
          'children': [
            'fullName',
            {
              'type': 'row',
              'children': ['income', 'maritalStatus'],
            },
          ],
        },
        'spouseName',
        {
          'type': 'card',
          'elevation': 2,
          'children': ['address'],
        },
      ]));
      final root = catalog.layout!;
      expect(shape(root), [
        'root',
        [
          'section',
          ['fullName'],
          [
            'row',
            ['income'],
            ['maritalStatus'],
          ],
        ],
        ['spouseName'],
        [
          'card',
          ['address'],
        ],
      ]);
      expect((root.children[0] as LayoutNode)['title'], 'Personal data');
      expect((root.children[2] as LayoutNode)['elevation'], 2);
      expect(catalog.layoutIssues, isEmpty);
    });

    test('no layout key means no layout', () {
      final json = catalogWith([])..remove('layout');
      expect(FormCatalog.fromJson(json).layout, isNull);
    });

    test('a malformed node is skipped and reported', () {
      final catalog = FormCatalog.fromJson(catalogWith([
        {'type': 'section'},
        {'type': 'row', 'children': 'income'},
        {
          'children': ['income']
        },
        {
          'type': 'section',
          'children': ['fullName', 7],
        },
      ]));
      expect(shape(catalog.layout!), [
        'root',
        [
          'section',
          ['fullName'],
        ],
      ]);
      expect([
        for (final i in catalog.layoutIssues) (i.kind, i.location)
      ], [
        (LayoutIssueKind.malformedNode, 'layout[0]'),
        (LayoutIssueKind.malformedNode, 'layout[1]'),
        (LayoutIssueKind.malformedNode, 'layout[2]'),
        (LayoutIssueKind.malformedNode, 'layout[3].children[1]'),
      ]);
    });

    test('a repeated key is reported and kept at its first place', () {
      final catalog = FormCatalog.fromJson(catalogWith([
        'income',
        {
          'type': 'row',
          'children': ['income', 'fullName'],
        },
      ]));
      expect(shape(catalog.layout!), [
        'root',
        ['income'],
        [
          'row',
          ['fullName'],
        ],
      ]);
      expect(catalog.layoutIssues, [
        LayoutIssue(
            LayoutIssueKind.repeatedKey, 'layout[1].children[0]', 'income'),
      ]);
    });

    test('a key not in the catalog is reported; one dropped is not', () {
      final catalog = FormCatalog.fromJson(
          catalogWith(['ghost', 'weird', 'address.zipCode', 'bad..key']));
      expect(shape(catalog.layout!), [
        'root',
        ['weird'], // kept: the views skip it, silently
        ['address.zipCode'],
      ]);
      expect(catalog.layoutIssues, [
        LayoutIssue(LayoutIssueKind.unknownKey, 'layout[0]', 'ghost'),
        LayoutIssue(LayoutIssueKind.unknownKey, 'layout[3]', 'bad..key'),
      ]);
    });

    test('a layout that is not a list is reported, and there is none', () {
      final json = catalogWith([])..['layout'] = {'type': 'section'};
      final catalog = FormCatalog.fromJson(json);
      expect(catalog.layout, isNull);
      expect(catalog.layoutIssues.single.kind, LayoutIssueKind.malformedNode);
    });

    test('onlyMissing keeps the layout', () {
      final catalog = FormCatalog.fromJson(catalogWith(['fullName']));
      expect(catalog.onlyMissing(const {}).layout, same(catalog.layout));
    });
  });
}
