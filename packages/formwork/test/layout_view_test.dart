import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isIn, matches;
import 'package:formwork/formwork.dart';

/// A text field rendered as its path, counting builds.
final class Probe extends FieldDef<Object> {
  Probe(super.key, {super.visibleWhen})
      : super(codec: FieldCodec<Object>(encode: (v) => v, decode: (j) => j));

  @override
  String get type => 'probe';
}

final fieldBuilds = <String, int>{};
final nodeBuilds = <String, int>{};

FieldRegistry fields() => FieldRegistry()
  ..register('probe', (context, field) {
    final key = '${field.def.path}';
    fieldBuilds.update(key, (n) => n + 1, ifAbsent: () => 1);
    return Text('field $key');
  })
  ..register('list', (context, field) => Text('list ${field.def.path}'));

/// Section and row builders that count builds by title (or type).
LayoutRegistry layouts() {
  Widget counted(LayoutNode node, Widget child) {
    final name = (node['title'] as String?) ?? node.type;
    nodeBuilds.update(name, (n) => n + 1, ifAbsent: () => 1);
    return child;
  }

  return LayoutRegistry()
    ..register(
        'section',
        (context, node, children) => counted(
            node,
            Column(children: [
              Text('section ${node['title']}'),
              ...children,
            ])))
    ..register('row',
        (context, node, children) => counted(node, Row(children: children)));
}

/// The texts on screen, in order.
List<String> texts(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text))) text.data!,
    ];

class LaidOut extends FormDef {
  LaidOut(this.root);

  final LayoutNode root;
  final a = Probe('a');
  final b = Probe('b');
  late final c = Probe('c', visibleWhen: eq('a', 'show'));
  final d = Probe('d');
  final zip = Probe('address.zip');
  final city = Probe('address.city');

  @override
  List<FieldDef<Object?>> get fields => [a, b, c, d, zip, city];

  @override
  LayoutNode get layout => root;
}

void main() {
  setUp(() {
    fieldBuilds.clear();
    nodeBuilds.clear();
  });

  Future<FormController> pump(
    WidgetTester tester,
    FormDef form, {
    LayoutRegistry? layouts,
  }) async {
    final controller = FormController(form);
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: FormView(
          controller: controller,
          registry: fields(),
          layouts: layouts,
        ),
      ),
    ));
    return controller;
  }

  LayoutNode tree(List<Object> children) =>
      LayoutNode('root', children: children);

  testWidgets('renders sections and rows through the registry', (tester) async {
    await pump(
      tester,
      LaidOut(tree([
        SectionNode(title: 'One', children: [
          FieldPath('a'),
          RowNode(children: [FieldPath('b'), FieldPath('d')]),
        ]),
        FieldPath('address'),
      ])),
      layouts: layouts(),
    );
    expect(texts(tester), [
      'section One',
      'field a',
      'field b',
      'field d',
      'field address.zip',
      'field address.city',
    ]);
    expect(find.byType(Row), findsOneWidget);
  });

  testWidgets('without a registry every node is a column', (tester) async {
    await pump(
        tester,
        LaidOut(tree([
          SectionNode(title: 'One', children: [FieldPath('d'), FieldPath('a')]),
        ])));
    expect(texts(tester).take(2), ['field d', 'field a']);
  });

  testWidgets('a field the layout does not place renders at the end',
      (tester) async {
    await pump(tester, LaidOut(tree([FieldPath('d')])));
    expect(texts(tester), [
      'field d',
      'field a',
      'field b',
      'field address.zip',
      'field address.city',
    ]);
  });

  testWidgets('a key not in the form is skipped; a repeated one renders once',
      (tester) async {
    await pump(
        tester,
        LaidOut(tree([
          FieldPath('ghost'),
          FieldPath('b'),
          RowNode(children: [FieldPath('b'), FieldPath('a')]),
        ])));
    expect(texts(tester).take(2), ['field b', 'field a']);
    expect(find.text('field b'), findsOneWidget);
  });

  testWidgets('an unknown node type renders its children and is reported',
      (tester) async {
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    await pump(
      tester,
      LaidOut(tree([
        LayoutNode('card', children: [FieldPath('a')]),
      ])),
      layouts: layouts(),
    );
    FlutterError.onError = FlutterError.presentError;
    expect(texts(tester).first, 'field a');
    expect(errors.single, contains('card'));
  });

  testWidgets('a node whose children are all hidden is not rendered',
      (tester) async {
    final controller = await pump(
      tester,
      LaidOut(tree([
        SectionNode(title: 'Hidden', children: [FieldPath('c')]),
        FieldPath('a'),
      ])),
      layouts: layouts(),
    );
    expect(find.text('section Hidden'), findsNothing);
    controller.change(FieldPath('a'), 'show');
    await tester.pump();
    expect(find.text('section Hidden'), findsOneWidget);
  });

  testWidgets('SnapshotFormView with a layout follows a new spacing',
      (tester) async {
    const engine = FormEngine();
    final form = LaidOut(tree([FieldPath('a')]));
    final snapshot = engine.registerAll(engine.initial(), form.fields);
    final registry = fields();
    Widget view(double spacing) => MaterialApp(
          home: SingleChildScrollView(
            child: SnapshotFormView(
              snapshot: snapshot,
              onChanged: (_, __) {},
              registry: registry,
              layout: form.layout,
              spacing: spacing,
            ),
          ),
        );
    double gap() => tester
        .widget<Padding>(find
            .ancestor(of: find.text('field a'), matching: find.byType(Padding))
            .first)
        .padding
        .vertical;
    await tester.pumpWidget(view(16));
    expect(gap(), 16);
    await tester.pumpWidget(view(4));
    expect(gap(), 4);
  });

  testWidgets('a list places its item fields right after it', (tester) async {
    final list = ListFieldDef('l', itemFields: (i) => [Probe('$i.x')]);
    final form =
        _WithLayout([Probe('a'), list], tree([FieldPath('l'), FieldPath('a')]));
    final controller = await pump(tester, form);
    controller.addItem(list.path, values: {'x': 1});
    await tester.pump();
    expect(texts(tester), ['list l', 'field l[#1].x', 'field a']);
  });
}

class _WithLayout extends FormDef {
  _WithLayout(super.fields, this.root);

  final LayoutNode root;

  @override
  LayoutNode get layout => root;
}
