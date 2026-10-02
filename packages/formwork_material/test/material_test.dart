import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

void main() {
  Future<FormController> pump(WidgetTester tester, FormDef form) async {
    final controller = FormController(form);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormView(
            controller: controller,
            registry: materialFieldRegistry(),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('text field reports changes and shows errors', (tester) async {
    final name = TextFieldDef('name', label: 'Name', required: true);
    final controller = await pump(tester, FormDef([name]));

    await tester.enterText(find.byType(TextField), 'Maria');
    expect(controller.value.valueOf(name), 'Maria');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('This field is required'), findsOneWidget);
  });

  testWidgets('number field parses what the user types', (tester) async {
    final income = NumberFieldDef('income');
    final controller = await pump(tester, FormDef([income]));

    await tester.enterText(find.byType(TextField), '1,5');
    expect(controller.value.valueOf(income), 1.5);
  });

  testWidgets('a password hides its text', (tester) async {
    await pump(tester, FormDef([TextFieldDef('secret', type: 'password')]));
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('dropdown lists the options and reports the choice',
      (tester) async {
    final state = ChoiceFieldDef<String>('state',
        label: 'State',
        options: [Option('SP', 'São Paulo'), Option('RJ', 'Rio')]);
    final controller = await pump(tester, FormDef([state]));

    await tester.tap(find.byType(DropdownButtonFormField<Object?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rio').last);
    await tester.pumpAndSettle();
    expect(controller.value.valueOf(state), 'RJ');
  });

  testWidgets('a required checkbox shows its error after submit',
      (tester) async {
    final terms = BoolFieldDef('terms', label: 'Accept', required: true);
    final controller = await pump(tester, FormDef([terms]));

    expect(controller.submit(), isNull);
    await tester.pump();
    expect(find.text('This field is required'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(controller.submit(), {'terms': true});
  });

  testWidgets('section and row builders lay out the fields', (tester) async {
    final a = TextFieldDef('a', label: 'A');
    final b = TextFieldDef('b', label: 'B');
    final c = TextFieldDef('c', label: 'C');
    final controller = FormController(_Laid([a, b, c]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FormView(
          controller: controller,
          registry: materialFieldRegistry(),
          layouts: materialLayoutRegistry(),
        ),
      ),
    ));
    expect(find.text('Personal'), findsOneWidget);
    expect(find.byType(Row), findsWidgets);
    final dy = [
      for (final l in ['A', 'B', 'C']) tester.getTopLeft(find.text(l)).dy
    ];
    expect(dy[1], dy[2]); // b and c share a row
    expect(dy[0], lessThan(dy[1]));
  });
}

class _Laid extends FormDef {
  _Laid(super.fields);

  @override
  late final LayoutNode layout = LayoutNode('root', children: [
    SectionNode(title: 'Personal', children: [
      FieldPath('a'),
      RowNode(children: [FieldPath('b'), FieldPath('c')]),
    ]),
  ]);
}
