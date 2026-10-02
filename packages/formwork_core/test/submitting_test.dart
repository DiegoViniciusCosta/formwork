import 'dart:math';

import 'package:formwork_core/formwork_core.dart';
import 'package:test/test.dart' hide matches;

const engine = FormEngine();

FieldPath p(String path) => FieldPath(path);

final email = TextFieldDef('email', required: true);
final name = TextFieldDef('name');
final form = [email, name];

FormSnapshot filled() => engine.registerAll(
    engine.initial(initialValues: {'email': 'a@b.co', 'name': 'Ana'}), form);

FormSnapshot sending() {
  final (:snapshot, :payload) = engine.submit(filled());
  expect(payload, isNotNull);
  return engine.startSubmitting(snapshot);
}

void main() {
  group('status', () {
    test('typing in a valid field keeps the identical status', () {
      var s = engine.change(filled(), p('name'), 'Anna');
      final status = s.status;
      s = engine.change(s, p('name'), 'Annah');
      expect(identical(s.status, status), isTrue);
    });

    test('errorCount matches a full count after random changes', () {
      final random = Random(3);
      final defs = [
        for (var i = 0; i < 12; i++)
          TextFieldDef('f$i',
              required: random.nextBool(),
              validators: [if (random.nextBool()) minLength(2)],
              visibleWhen: i > 0 && random.nextBool()
                  ? eq('f${random.nextInt(i)}', 'x')
                  : null),
      ];
      var s = engine.registerAll(engine.initial(), defs);
      for (var step = 0; step < 300; step++) {
        s = engine.change(s, p('f${random.nextInt(12)}'),
            const [null, '', 'x', 'xy'][random.nextInt(4)]);
        final full = defs.where((d) => s.stateOf(d)!.error != null).length;
        expect(s.status.errorCount, full);
      }
    });
  });

  group('submitting', () {
    test('a submit while sending returns the identical snapshot, no payload',
        () {
      final s = sending();
      final result = engine.submit(s);
      expect(identical(result.snapshot, s), isTrue);
      expect(result.payload, isNull);
    });

    test('startSubmitting marks the send and clears the last outcome', () {
      var s = sending();
      s = engine.completeSubmit(
          s, ServerErrors(form: ValidationError('wrongPassword')));
      expect(s.status.formError, isNotNull);

      s = engine.startSubmitting(engine.submit(s).snapshot);
      expect(s.status.submitting, isTrue);
      expect(s.status.formError, isNull);
      expect(s.status.lastSubmit, isNull);
    });

    test('no answer, or an empty one, is accepted', () {
      expect(engine.completeSubmit(sending(), null).status.lastSubmit,
          SubmitOutcome.accepted);
      final s = engine.completeSubmit(sending(), ServerErrors());
      expect(s.status.lastSubmit, SubmitOutcome.accepted);
      expect(s.status.submitting, isFalse);
    });

    test('field errors are rejected and applied as server errors', () {
      final s = engine.completeSubmit(
        sending(),
        ServerErrors(fields: {p('email'): ValidationError('taken')}),
      );
      expect(s.status.lastSubmit, SubmitOutcome.rejected);
      expect(s.stateOf(email)!.error,
          ValidationError('taken', source: ErrorSource.server));
      expect(s.status.errorCount, 1);
      expect(s.firstErrorPath, p('email'));
    });

    test('a server error clears when its field changes', () {
      var s = engine.completeSubmit(
        sending(),
        ServerErrors(fields: {p('email'): ValidationError('taken')}),
      );
      s = engine.change(s, p('email'), 'other@b.co');
      expect(s.stateOf(email)!.error, isNull);
      expect(s.status.isValid, isTrue);
    });

    test('a server error survives a change to another field it reads', () {
      final confirm = TextFieldDef('confirm', validators: [matches(name)]);
      var s = engine.registerAll(
          engine.initial(initialValues: {'name': 'x', 'confirm': 'x'}),
          [name, confirm]);
      s = engine.startSubmitting(engine.submit(s).snapshot);
      s = engine.completeSubmit(
          s, ServerErrors(fields: {p('confirm'): ValidationError('taken')}));
      s = engine.change(s, p('name'), 'x'); // same value, confirm revalidates
      expect(s.stateOf(confirm)!.error!.code, 'taken');
    });

    test('an error for a field changed during the send is discarded', () {
      var s = sending();
      s = engine.change(s, p('email'), 'new@b.co');
      s = engine.completeSubmit(
          s, ServerErrors(fields: {p('email'): ValidationError('taken')}));
      expect(s.stateOf(email)!.error, isNull);
      expect(s.status.lastSubmit, SubmitOutcome.rejected);
    });

    test('an error for an unregistered path is discarded', () {
      final phone = TextFieldDef('phone');
      var s = engine.completeSubmit(sending(),
          ServerErrors(fields: {p('phone'): ValidationError('bad')}));
      expect(s.status.lastSubmit, SubmitOutcome.rejected);
      expect(s.status.errorCount, 0);

      s = engine.register(s, phone);
      expect(s.stateOf(phone)!.error, isNull);
    });

    test('the form error does not count and does not block the next submit',
        () {
      final s = engine.completeSubmit(
          sending(), ServerErrors(form: ValidationError('wrongPassword')));
      expect(s.status.formError,
          ValidationError('wrongPassword', source: ErrorSource.server));
      expect(s.status.errorCount, 0);
      expect(engine.submit(s).payload, isNotNull);
    });

    test('abandonSubmit applies nothing', () {
      final s = engine.abandonSubmit(sending());
      expect(s.status.lastSubmit, SubmitOutcome.abandoned);
      expect(s.status.submitting, isFalse);
      expect(s.status.errorCount, 0);
    });
  });

  group('race-free, whatever happens to the field during the send', () {
    ServerErrors taken() =>
        ServerErrors(fields: {p('email'): ValidationError('taken')});

    test('changed, unregistered and registered again: discarded', () {
      var s = sending();
      s = engine.change(s, p('email'), 'new@b.co');
      s = engine.register(engine.unregister(s, p('email')), email);
      s = engine.completeSubmit(s, taken());
      expect(s.stateOf(email)!.error, isNull);
    });

    test('changed, then unregistered when the answer comes: discarded', () {
      var s = sending();
      s = engine.change(s, p('email'), 'new@b.co');
      s = engine.completeSubmit(engine.unregister(s, p('email')), taken());
      s = engine.register(s, email);
      expect(s.stateOf(email)!.error, isNull);
    });

    test('unregistered and registered again during the send: discarded', () {
      var s = engine.unregister(sending(), p('email'));
      s = engine.register(s, email); // its value may not be the one sent
      s = engine.completeSubmit(s, taken());
      expect(s.stateOf(email)!.error, isNull);
    });

    test('a field that unregisters drops its server error (decision 27)', () {
      var s = engine.completeSubmit(sending(), taken());
      expect(s.stateOf(email)!.error!.code, 'taken');
      s = engine.register(engine.unregister(s, p('email')), email);
      expect(s.stateOf(email)!.error, isNull);
    });

    test('a local error wins over the server one (decision 27)', () {
      final short = TextFieldDef('email', validators: [minLength(100)]);
      var s = engine.register(
          engine.initial(initialValues: {'email': 'a@b.co'}), short);
      s = engine.startSubmitting(engine.submit(s).snapshot);
      s = engine.completeSubmit(s, taken());
      expect(s.stateOf(short)!.error!.code, 'minLength');
    });
  });

  group('firstErrorPath', () {
    test('follows registration order among errors that show', () {
      final a = TextFieldDef('a', required: true);
      final b = TextFieldDef('b', required: true);
      var s = engine.registerAll(engine.initial(), [a, b]);
      expect(s.firstErrorPath, isNull); // nothing shown yet

      s = engine.change(s, p('b'), '');
      expect(s.firstErrorPath, p('b')); // b touched and in error

      s = engine.submit(s).snapshot;
      expect(s.firstErrorPath, p('a'));
    });
  });
}
