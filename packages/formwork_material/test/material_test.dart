import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

void main() {
  testWidgets('text field reports changes and shows errors', (tester) async {
    final config = FormConfig.fromMap({
      'fields': [
        {'key': 'name', 'type': 'text', 'label': 'Name', 'required': true},
      ],
    });
    final controller = DynamicFormController(FormEngine(config: config));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynamicForm(
            controller: controller,
            registry: materialFieldRegistry(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Maria');
    expect(controller.value.values['name'], 'Maria');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('This field is required'), findsOneWidget);
  });
}
