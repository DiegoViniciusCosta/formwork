import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isIn, matches;
import 'package:formwork/formwork.dart';
import 'package:formwork/src/flutter/field_view.dart'
    show debugReportUnplacedFields;

/// A registry whose "probe" type counts builds per field, and keeps each
/// field's latest onChanged.
({
  FieldRegistry registry,
  Map<String, int> builds,
  Map<String, ValueChanged<Object?>> callbacks,
}) probeRegistry() {
  final builds = <String, int>{};
  final callbacks = <String, ValueChanged<Object?>>{};
  final registry = FieldRegistry()
    ..register('probe', (context, field) {
      final key = field.def.path.toString();
      builds.update(key, (n) => n + 1, ifAbsent: () => 1);
      callbacks[key] = field.onChanged;
      return const SizedBox(height: 1);
    });
  return (registry: registry, builds: builds, callbacks: callbacks);
}

/// A text field rendered by the "probe" builder.
final class Probe extends FieldDef<Object> {
  Probe(
    super.key, {
    super.required,
    super.initialValue,
    super.visibleWhen,
  }) : super(codec: FieldCodec<Object>(encode: (v) => v, decode: (j) => j));

  @override
  String get type => 'probe';
}

Future<FormController> pumpForm(
  WidgetTester tester,
  List<FieldDef<Object?>> fields,
  FieldRegistry registry,
) async {
  final controller = FormController(FormDef(fields));
  await tester.pumpWidget(
    MaterialApp(
      home: SingleChildScrollView(
        child: FormView(controller: controller, registry: registry),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('a change rebuilds only that field (200 fields)', (tester) async {
    final probe = probeRegistry();
    await pumpForm(
        tester,
        [for (var i = 0; i < 200; i++) Probe('f$i', required: true)],
        probe.registry);
    expect(probe.builds.length, 200);

    probe.builds.clear();
    probe.callbacks['f0']!('x');
    await tester.pump();

    expect(probe.builds, {'f0': 1});
  });

  test('a change notifies only the fields whose state changed (0006 §6)', () {
    final fields = [for (var i = 0; i < 1000; i++) Probe('f$i')];
    final controller = FormController(FormDef(fields));
    final notified = <String>[];
    for (final def in fields) {
      controller
          .fieldState(def)
          .addListener(() => notified.add(def.path.toString()));
    }
    var statusNotifications = 0;
    controller.status.addListener(() => statusNotifications++);

    controller.change(FieldPath('f7'), 'x');
    expect(notified, ['f7']);
    expect(statusNotifications, 1); // it became dirty

    notified.clear();
    controller.change(FieldPath('f7'), 'xy');
    expect(notified, ['f7']);
    expect(statusNotifications, 1); // still dirty: no new status
  });

  testWidgets('submit rebuilds only fields whose error became visible',
      (tester) async {
    final probe = probeRegistry();
    final controller = await pumpForm(
      tester,
      [
        Probe('ok', required: true, initialValue: 'a'),
        Probe('empty', required: true)
      ],
      probe.registry,
    );

    probe.builds.clear();
    controller.submit();
    await tester.pump();

    expect(probe.builds, {'empty': 1});
  });

  testWidgets('a dependent field appears without rebuilding the others',
      (tester) async {
    final probe = probeRegistry();
    await pumpForm(
      tester,
      [
        Probe('kind'),
        Probe('other'),
        Probe('dependent', visibleWhen: eq('kind', 'a')),
      ],
      probe.registry,
    );
    expect(probe.builds.keys, isNot(contains('dependent')));

    probe.builds.clear();
    probe.callbacks['kind']!('a');
    await tester.pump();

    expect(probe.builds, {'kind': 1, 'dependent': 1});
  });

  testWidgets('hiding a chain rebuilds only the field that changed',
      (tester) async {
    final probe = probeRegistry();
    await pumpForm(
      tester,
      [
        Probe('root', initialValue: true),
        Probe('other'),
        Probe('middle', initialValue: 'x', visibleWhen: eq('root', true)),
        Probe('leaf', visibleWhen: eq('middle', 'x')),
      ],
      probe.registry,
    );
    expect(probe.builds.keys, containsAll(['middle', 'leaf']));

    probe.builds.clear();
    probe.callbacks['root']!(false);
    await tester.pump();

    expect(probe.builds, {'root': 1});
  });

  testWidgets('an outside change rebuilds only its text field, once',
      (tester) async {
    final builds = <String, int>{};
    final registry = FieldRegistry()
      ..register(
        'text',
        (context, field) => TextControllerBinding<Object>(
          value: field.value,
          onChanged: field.onChanged,
          builder: (context, controller, onTextChanged) {
            final key = field.def.path.toString();
            builds.update(key, (n) => n + 1, ifAbsent: () => 1);
            return Material(
              child: TextField(
                controller: controller,
                onChanged: onTextChanged,
              ),
            );
          },
        ),
      );
    final controller = await pumpForm(
        tester,
        [
          for (final key in ['a', 'b', 'c']) TextFieldDef(key)
        ],
        registry);

    builds.clear();
    controller.change(FieldPath('b'), 'from outside');
    await tester.pump();

    expect(builds, {'b': 1});
    final texts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text);
    expect(texts, ['', 'from outside', '']);
  });

  testWidgets(
      'a parent rebuilding FormView with the same inputs builds '
      'no field', (tester) async {
    final probe = probeRegistry();
    final controller =
        FormController(FormDef([for (var i = 0; i < 20; i++) Probe('f$i')]));
    Widget app(int tick) => MaterialApp(
          home: Column(children: [
            Text('tick $tick'),
            FormView(controller: controller, registry: probe.registry),
          ]),
        );
    await tester.pumpWidget(app(0));
    probe.builds.clear();
    await tester.pumpWidget(app(1));
    expect(probe.builds, isEmpty);
  });

  testWidgets('a new localizer rebuilds every field once', (tester) async {
    final probe = probeRegistry();
    final controller = FormController(FormDef([Probe('a'), Probe('b')]));
    String other(ValidationError e, FieldDef<Object?>? f) => 'x';
    Widget app(ErrorLocalizer localizer) => MaterialApp(
          home: FormView(
            controller: controller,
            registry: probe.registry,
            localizer: localizer,
          ),
        );
    await tester.pumpWidget(app(englishErrorLocalizer));
    probe.builds.clear();
    await tester.pumpWidget(app(other));
    expect(probe.builds, {'a': 1, 'b': 1});
  });

  group('FieldView in a custom layout', () {
    late ({
      FieldRegistry registry,
      Map<String, int> builds,
      Map<String, ValueChanged<Object?>> callbacks,
    }) probe;
    late FormController controller;
    final a = Probe('a');
    final b = Probe('b');
    final shown = Probe('shown', visibleWhen: eq('a', 'on'));

    Future<void> pumpLayout(WidgetTester tester, Widget layout) async {
      probe = probeRegistry();
      controller = FormController(FormDef([a, b, shown]));
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: FormScope(
            controller: controller,
            registry: probe.registry,
            child: layout,
          ),
        ),
      ));
    }

    testWidgets('a FieldView rebuilds only its own field', (tester) async {
      await pumpLayout(
        tester,
        Column(children: [
          const Text('Heading'),
          FieldView(a),
          Row(children: [Expanded(child: FieldView(b))]),
          FieldView(shown),
        ]),
      );
      probe.builds.clear();
      probe.callbacks['b']!('typed');
      await tester.pump();
      expect(probe.builds, {'b': 1});
    });

    testWidgets('wrap builds nothing while the field is hidden',
        (tester) async {
      await pumpLayout(
        tester,
        Column(children: [
          FieldView(a),
          FieldView(b),
          FieldView(shown, wrap: (context, field) => Card(child: field)),
        ]),
      );
      expect(find.byType(Card), findsNothing);

      probe.callbacks['a']!('on');
      await tester.pump();
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('a per-view builder replaces the registry', (tester) async {
      await pumpLayout(
        tester,
        Column(children: [
          FieldView(a, builder: (context, field) => const Text('custom')),
          FieldView(b),
        ]),
      );
      expect(find.text('custom'), findsOneWidget);
      expect(probe.builds.keys, ['b']);
    });

    testWidgets('changing the scope enabled rebuilds every field once',
        (tester) async {
      Widget layout(bool enabled) => MaterialApp(
            home: FormScope(
              controller: controller,
              registry: probe.registry,
              enabled: enabled,
              child: Column(children: [FieldView(a), FieldView(b)]),
            ),
          );
      probe = probeRegistry();
      controller = FormController(FormDef([a, b]));
      await tester.pumpWidget(layout(true));
      probe.builds.clear();
      await tester.pumpWidget(layout(false));
      expect(probe.builds, {'a': 1, 'b': 1});
    });
  });

  group('debug checks, reported and not thrown', () {
    Future<List<String>> reported(
        WidgetTester tester, List<FieldDef<Object?>> form, Widget child) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError =
          (details) => errors.add(details.exceptionAsString());
      final probe = probeRegistry();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: FormScope(
            controller: FormController(FormDef(form)),
            registry: probe.registry,
            child: child,
          ),
        ),
      ));
      await tester.pump();
      FlutterError.onError = previous;
      return errors;
    }

    final a = Probe('a');
    final b = Probe('b');

    testWidgets('a FieldView for a field not in the form', (tester) async {
      final errors = await reported(
          tester, [a], Column(children: [FieldView(a), FieldView(b)]));
      expect(errors.single, contains('b is not a field of this form'));
    });

    testWidgets('a field placed twice', (tester) async {
      final errors = await reported(
          tester, [a], Column(children: [FieldView(a), FieldView(a)]));
      expect(errors.single, contains('a is shown by two FieldViews'));
    });

    testWidgets('a FieldView that switches to another field is recounted',
        (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString());
      final probe = probeRegistry();
      final controller = FormController(FormDef([a, b]));
      Widget app(FieldDef<Object?> first) => MaterialApp(
            home: Material(
              child: FormScope(
                controller: controller,
                registry: probe.registry,
                child: Column(children: [
                  FieldView(first, key: const ValueKey('slot')),
                  FieldView(b),
                ]),
              ),
            ),
          );
      await tester.pumpWidget(app(b)); // b twice for a moment
      await tester.pump();
      expect(
          errors.where((e) => e.contains('b is shown by two')), hasLength(1));

      errors.clear();
      await tester.pumpWidget(app(a)); // then a and b, once each
      debugReportUnplacedFields(controller);
      FlutterError.onError = previous;
      expect(errors, isEmpty);
    });

    testWidgets('a visible field that no FieldView shows', (tester) async {
      final errors =
          await reported(tester, [a, b], Column(children: [FieldView(a)]));
      expect(errors.single, contains('b is visible, but no FieldView'));
    });
  });

  testWidgets('SnapshotFormView rebuilds only the fields whose state changed',
      (tester) async {
    final probe = probeRegistry();
    const engine = FormEngine();
    var snapshot = engine.registerAll(
        engine.initial(), [for (var i = 0; i < 20; i++) Probe('f$i')]);

    Widget view() => MaterialApp(
          home: SingleChildScrollView(
            child: SnapshotFormView(
              snapshot: snapshot,
              onChanged: (path, value) {},
              registry: probe.registry,
            ),
          ),
        );
    await tester.pumpWidget(view());
    probe.builds.clear();

    snapshot = engine.change(snapshot, FieldPath('f3'), 'x');
    await tester.pumpWidget(view());
    expect(probe.builds, {'f3': 1});
  });
}
