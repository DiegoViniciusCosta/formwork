import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide isIn, matches;
import 'package:formwork/formwork.dart';

final email = TextFieldDef('email', required: true);
final name = TextFieldDef('name', required: true);

/// A text builder that wires the field's focus node, and counts builds.
FieldRegistry textRegistry(Map<String, int> builds) => FieldRegistry()
  ..register(
    'text',
    (context, field) {
      final key = field.def.path.toString();
      builds.update(key, (n) => n + 1, ifAbsent: () => 1);
      return TextControllerBinding<Object>(
        value: field.value,
        onChanged: field.onChanged,
        builder: (context, controller, onTextChanged) => TextField(
          key: ValueKey('input $key'),
          controller: controller,
          focusNode: field.focusNode,
          onChanged: onTextChanged,
        ),
      );
    },
  );

Future<FormController> pumpForm(WidgetTester tester, List<FieldDef<Object?>> f,
    {Map<String, int>? builds, Widget Function(Widget form)? around}) async {
  final controller = FormController(FormDef(f));
  final form =
      FormView(controller: controller, registry: textRegistry(builds ?? {}));
  await tester.pumpWidget(MaterialApp(
    home: Material(child: around?.call(form) ?? form),
  ));
  return controller;
}

FocusNode? focusedNode() => FocusManager.instance.primaryFocus;

bool isFocused(WidgetTester tester, String key) => tester
    .widget<TextField>(find.byKey(ValueKey('input $key')))
    .focusNode!
    .hasFocus;

void main() {
  group('submitTo', () {
    testWidgets('a valid form is sent and accepted', (tester) async {
      final controller = await pumpForm(tester, [email]);
      controller.change(email.path, 'a@b.co');
      Map<String, Object?>? sent;
      final outcome = await controller.submitTo((payload) async {
        sent = payload;
        expect(controller.value.status.submitting, isTrue);
        return null;
      });
      expect(sent, {'email': 'a@b.co'});
      expect(outcome, SubmitOutcome.accepted);
      expect(controller.value.status.submitting, isFalse);
    });

    testWidgets('an invalid form is not sent, and focuses the first error',
        (tester) async {
      final controller = await pumpForm(tester, [email, name]);
      var sent = false;
      final outcome = await controller.submitTo((_) async {
        sent = true;
        return null;
      });
      await tester.pump();
      expect(outcome, isNull);
      expect(sent, isFalse);
      expect(isFocused(tester, 'email'), isTrue);
    });

    testWidgets('a rejection applies server errors and focuses the field',
        (tester) async {
      final controller = await pumpForm(tester, [email, name]);
      controller
        ..change(email.path, 'a@b.co')
        ..change(name.path, 'Ana');
      final outcome = await controller.submitTo((_) async =>
          ServerErrors(fields: {name.path: ValidationError('taken')}));
      await tester.pump();
      expect(outcome, SubmitOutcome.rejected);
      expect(isFocused(tester, 'name'), isTrue);
      expect(controller.value.stateOf(name)!.error!.source, ErrorSource.server);
    });

    testWidgets('a send that throws is abandoned, and the error rethrown',
        (tester) async {
      final controller = await pumpForm(tester, [email]);
      controller.change(email.path, 'a@b.co');
      await expectLater(
        controller.submitTo((_) async => throw const SocketLikeError()),
        throwsA(isA<SocketLikeError>()),
      );
      expect(controller.value.status.submitting, isFalse);
      expect(controller.value.status.lastSubmit, SubmitOutcome.abandoned);
    });

    testWidgets('a second tap while sending sends nothing', (tester) async {
      final controller = await pumpForm(tester, [email]);
      controller.change(email.path, 'a@b.co');
      final answer = Completer<ServerErrors?>();
      var sends = 0;
      final first = controller.submitTo((_) {
        sends++;
        return answer.future;
      });
      expect(await controller.submitTo((_) async => null), isNull);
      answer.complete(null);
      expect(await first, SubmitOutcome.accepted);
      expect(sends, 1);
    });
  });

  group('FormFocus', () {
    testWidgets('scrolls to the first error by default, and not when asked',
        (tester) async {
      // A focusable field that is not text: text inputs scroll themselves
      // into view when they get focus.
      final registry = FieldRegistry()
        ..register(
          'text',
          (context, field) => Focus(
            focusNode: field.focusNode,
            child: const SizedBox(height: 100),
          ),
        );
      final controller = FormController(FormDef([
        for (var i = 0; i < 30; i++) TextFieldDef('f$i', initialValue: 'ok'),
        email,
      ]));
      await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
          child: FormView(controller: controller, registry: registry),
        ),
      ));
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;

      controller.submit();
      controller.focus.requestFirstError(controller.value, scroll: false);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(focusedNode()?.debugLabel, 'email');

      controller.focus.requestFirstError(controller.value);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
    });

    testWidgets('an unmounted field with an error is skipped', (tester) async {
      final controller = FormController(FormDef([email, name]));
      // Expected: email is visible and placed nowhere (0006 §4).
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: FormScope(
            controller: controller,
            registry: textRegistry({}),
            child: FieldView(name), // email is never placed
          ),
        ),
      ));
      await tester.pump();
      controller.submit();
      expect(controller.focus.requestFirstError(controller.value), isTrue);
      await tester.pump();
      expect(isFocused(tester, 'name'), isTrue);
      FlutterError.onError = FlutterError.presentError;
    });

    testWidgets('no mounted field in error: false, and a debug report',
        (tester) async {
      final controller = FormController(FormDef([email]));
      final errors = <String>[];
      FlutterError.onError = (d) => errors.add(d.exceptionAsString());
      controller.submit();
      expect(controller.focus.requestFirstError(controller.value), isFalse);
      FlutterError.onError = FlutterError.presentError;
      expect(errors.single, contains('No field with an error is mounted'));
    });

    testWidgets('a form error alone moves no focus', (tester) async {
      final controller = await pumpForm(tester, [email]);
      controller.change(email.path, 'a@b.co');
      await controller.submitTo(
          (_) async => ServerErrors(form: ValidationError('wrongPassword')));
      await tester.pump();
      expect(isFocused(tester, 'email'), isFalse);
      expect(controller.value.status.formError, isNotNull);
    });

    testWidgets('SnapshotFormView with a standalone FormFocus', (tester) async {
      const engine = FormEngine();
      final focus = FormFocus();
      var snapshot = engine.registerAll(engine.initial(), [email, name]);
      snapshot = engine.change(snapshot, email.path, 'a@b.co');
      snapshot = engine.submit(snapshot).snapshot;
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: SnapshotFormView(
            snapshot: snapshot,
            onChanged: (_, __) {},
            registry: textRegistry({}),
            focus: focus,
          ),
        ),
      ));
      expect(focus.requestFirstError(snapshot), isTrue);
      await tester.pump();
      expect(isFocused(tester, 'name'), isTrue);
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
