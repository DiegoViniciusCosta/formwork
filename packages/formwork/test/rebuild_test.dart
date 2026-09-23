import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formwork/formwork.dart';

/// Registry with a "probe" type that counts builds per field.
({
  FieldRegistry registry,
  Map<String, int> builds,
  Map<String, ValueChanged<Object?>> callbacks,
}) probeRegistry() {
  final builds = <String, int>{};
  final callbacks = <String, ValueChanged<Object?>>{};
  final registry = FieldRegistry()
    ..register('probe', (context, field, ctx) {
      builds.update(field.key, (n) => n + 1, ifAbsent: () => 1);
      callbacks[field.key] = ctx.onChanged;
      return const SizedBox(height: 1);
    });
  return (registry: registry, builds: builds, callbacks: callbacks);
}

Future<DynamicFormController> pumpForm(
  WidgetTester tester,
  FormConfig config,
  FieldRegistry registry,
) async {
  final controller = DynamicFormController(FormEngine(config: config));
  await tester.pumpWidget(
    MaterialApp(
      home: SingleChildScrollView(
        child: DynamicForm(controller: controller, registry: registry),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('a change rebuilds only that field (200 fields)', (tester) async {
    final probe = probeRegistry();
    final config = FormConfig.fromMap({
      'fields': [
        for (var i = 0; i < 200; i++)
          {'key': 'f$i', 'type': 'probe', 'required': true},
      ],
    });
    await pumpForm(tester, config, probe.registry);
    expect(probe.builds.length, 200);

    probe.builds.clear();
    probe.callbacks['f0']!('x');
    await tester.pump();

    expect(probe.builds, {'f0': 1});
  });

  testWidgets('submit rebuilds only fields whose error became visible',
      (tester) async {
    final probe = probeRegistry();
    final config = FormConfig.fromMap({
      'fields': [
        {'key': 'ok', 'type': 'probe', 'required': true, 'initialValue': 'a'},
        {'key': 'empty', 'type': 'probe', 'required': true},
      ],
    });
    final controller = await pumpForm(tester, config, probe.registry);

    probe.builds.clear();
    controller.submit();
    await tester.pump();

    expect(probe.builds, {'empty': 1});
  });

  testWidgets('a dependent field appears without rebuilding the others',
      (tester) async {
    final probe = probeRegistry();
    final config = FormConfig.fromMap({
      'fields': [
        {'key': 'kind', 'type': 'probe'},
        {'key': 'other', 'type': 'probe'},
        {
          'key': 'dependent',
          'type': 'probe',
          'visibleWhen': {'field': 'kind', 'equals': 'a'},
        },
      ],
    });
    await pumpForm(tester, config, probe.registry);
    expect(probe.builds.keys, isNot(contains('dependent')));

    probe.builds.clear();
    probe.callbacks['kind']!('a');
    await tester.pump();

    expect(probe.builds, {'kind': 1, 'dependent': 1});
  });

  testWidgets('hiding a chain rebuilds only the field that changed',
      (tester) async {
    final probe = probeRegistry();
    final config = FormConfig.fromMap({
      'fields': [
        {'key': 'root', 'type': 'probe', 'initialValue': true},
        {'key': 'other', 'type': 'probe'},
        {
          'key': 'middle',
          'type': 'probe',
          'initialValue': 'x',
          'visibleWhen': {'field': 'root', 'equals': true},
        },
        {
          'key': 'leaf',
          'type': 'probe',
          'visibleWhen': {'field': 'middle', 'equals': 'x'},
        },
      ],
    });
    await pumpForm(tester, config, probe.registry);
    expect(probe.builds.keys, containsAll(['middle', 'leaf']));

    probe.builds.clear();
    probe.callbacks['root']!(false);
    await tester.pump();

    expect(probe.builds, {'root': 1});
  });
}
