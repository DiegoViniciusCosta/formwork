import 'package:formwork_core/formwork_core.dart' hide FormEngine, FormSnapshot;
import 'package:formwork_core/src/engine/engine.dart';
import 'package:test/test.dart' hide isIn, matches;

enum MaritalStatus { single, married }

final isoDate = FieldCodec<DateTime>(
  encode: (date) => date.toIso8601String(),
  decode: (json) => DateTime.parse(json as String),
);

final class DateFieldDef extends FieldDef<DateTime> {
  DateFieldDef(super.key, {super.codec});

  @override
  String get type => 'date';
}

class ProfileForm extends FormDef {
  final fullName =
      TextFieldDef('fullName', required: true, validators: [minLength(3)]);
  final income = NumberFieldDef('income', validators: [min(1000)]);
  final maritalStatus = ChoiceFieldDef<MaritalStatus>('maritalStatus',
      options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
  late final spouseName = TextFieldDef('spouseName',
      required: true, visibleWhen: maritalStatus.equals(MaritalStatus.married));
  final password = TextFieldDef('password', validators: [minLength(8)]);
  late final confirm = TextFieldDef('confirm', validators: [matches(password)]);

  @override
  List<FieldDef<Object?>> get fields =>
      [fullName, income, maritalStatus, spouseName, password, confirm];
}

class CyclicForm extends FormDef {
  late final TextFieldDef a = TextFieldDef('a', visibleWhen: b.equals('x'));
  late final TextFieldDef b = TextFieldDef('b', visibleWhen: a.equals('y'));

  @override
  List<FieldDef<Object?>> get fields => [a, b];
}

void main() {
  const engine = FormEngine();
  FieldPath p(String path) => FieldPath(path);

  group('definitions compare by value', () {
    test('built-in definitions with equal parameters are equal', () {
      TextFieldDef make() => TextFieldDef('name',
          label: 'Name',
          required: true,
          validators: [minLength(3), pattern('^[A-Z]')],
          visibleWhen: eq('kind', 'person'),
          extra: {
            'mask': ['###']
          },
          messages: {'required': 'Tell us your name'});
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(TextFieldDef('name', label: 'Name')));
    });

    test('a different validator parameter makes a different definition', () {
      expect(TextFieldDef('a', validators: [minLength(3)]),
          isNot(TextFieldDef('a', validators: [minLength(4)])));
      expect(NumberFieldDef('a', validators: [min(1)]),
          isNot(NumberFieldDef('a', validators: [max(1)])));
    });

    test('choice fields compare their options', () {
      ChoiceFieldDef<String> make(String label) =>
          ChoiceFieldDef('c', options: [Option('a', label)]);
      expect(make('A'), make('A'));
      expect(make('A'), isNot(make('B')));
    });

    test('an equal definition registers again for free', () {
      final s = engine.register(engine.initial(), ProfileForm().income);
      expect(identical(engine.register(s, ProfileForm().income), s), isTrue);
    });
  });

  group('conditions from fields', () {
    final form = ProfileForm();

    test('equals builds the same condition as eq', () {
      expect(form.maritalStatus.equals(MaritalStatus.married),
          eq('maritalStatus', MaritalStatus.married));
      expect(form.income.isIn([1, 2]), isIn('income', [1, 2]));
    });

    test('number fields add comparisons', () {
      expect(form.income.greaterThan(10), gt('income', 10));
      expect(form.income.greaterThanOrEqualTo(10), gte('income', 10));
      expect(form.income.lessThan(10), lt('income', 10));
      expect(form.income.lessThanOrEqualTo(10), lte('income', 10));
    });
  });

  group('codecs', () {
    test('an enum round-trips through initial values and the payload', () {
      final form = ProfileForm();
      var s = engine.registerAll(
        engine.initial(initialValues: {'maritalStatus': 'married'}),
        form.fields,
      );
      expect(s.valueOf(form.maritalStatus), MaritalStatus.married);
      expect(s.stateOf(form.spouseName)!.visible, isTrue);
      expect(s.payload()['maritalStatus'], 'married');

      s = engine.change(s, form.maritalStatus.path, MaritalStatus.single);
      expect(s.payload()['maritalStatus'], 'single');
      expect(s.payload().containsKey('spouseName'), isFalse);
    });

    test('a value no option matches becomes null and is listed', () {
      final form = ProfileForm();
      var s = engine.registerAll(
        engine.initial(initialValues: {'maritalStatus': 'widowed'}),
        form.fields,
      );
      expect(s.valueOf(form.maritalStatus), isNull);
      expect(s.undecodable, {p('maritalStatus'): 'widowed'});

      s = engine.change(s, form.maritalStatus.path, MaritalStatus.single);
      expect(s.undecodable, isEmpty);
    });

    test('a number field rejects text from the server', () {
      final s = engine.register(
        engine.initial(initialValues: {'income': '1500'}),
        NumberFieldDef('income'),
      );
      expect(s.valueOf(NumberFieldDef('income')), isNull);
      expect(s.undecodable, {p('income'): '1500'});
    });

    test('a custom type decodes through its codec', () {
      final birth = DateFieldDef('birth', codec: isoDate);
      final s = engine.register(
        engine.initial(initialValues: {'birth': '2000-01-02T00:00:00.000'}),
        birth,
      );
      expect(s.valueOf(birth), DateTime(2000, 1, 2));
      expect(s.payload()['birth'], '2000-01-02T00:00:00.000');
    });

    test('replacing a codec updates the fields that read the value', () {
      final spouse = TextFieldDef('spouse',
          visibleWhen: eq('status', MaritalStatus.married));
      final both = ChoiceFieldDef<MaritalStatus>('status',
          options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
      final onlySingle = ChoiceFieldDef<MaritalStatus>('status',
          options: [Option(MaritalStatus.single, 'Single')]);

      var s = engine.registerAll(
        engine.initial(initialValues: {'status': 'married'}),
        [both, spouse],
      );
      expect(s.stateOf(spouse)!.visible, isTrue);
      s = engine.register(s, onlySingle);
      expect(s.stateOf(spouse)!.visible, isFalse);
      expect(s.changedPaths, containsAll([p('status'), p('spouse')]));
    });

    test('a value that did not decode gets a second chance with a new codec',
        () {
      final onlySingle = ChoiceFieldDef<MaritalStatus>('status',
          options: [Option(MaritalStatus.single, 'Single')]);
      final both = ChoiceFieldDef<MaritalStatus>('status',
          options: [for (final s in MaritalStatus.values) Option(s, s.name)]);

      var s = engine.register(
        engine.initial(initialValues: {'status': 'married'}),
        onlySingle,
      );
      expect(s.undecodable, {p('status'): 'married'});
      s = engine.register(s, both);
      expect(s.valueOf(both), MaritalStatus.married);
      expect(s.undecodable, isEmpty);
      expect(s.stateOf(both)!.dirty, isFalse);

      // The decoded value is also the baseline dirty compares with.
      s = engine.change(s, p('status'), MaritalStatus.single);
      s = engine.change(s, p('status'), MaritalStatus.married);
      expect(s.stateOf(both)!.dirty, isFalse);
    });

    test('unregistering a field drops it from undecodable', () {
      var s = engine.register(
        engine.initial(initialValues: {'income': 'lots'}),
        NumberFieldDef('income'),
      );
      expect(s.undecodable, isNotEmpty);
      s = engine.unregister(s, p('income'));
      expect(s.undecodable, isEmpty);
    });

    test('user data set on a path is JSON, decoded when a field registers', () {
      final status = ChoiceFieldDef<MaritalStatus>('status',
          options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
      var s = engine.change(engine.initial(), p('status'), 'married');
      s = engine.register(s, status);
      expect(s.valueOf(status), MaritalStatus.married);
    });

    test('an option of a non-JSON type needs json:', () {
      expect(() => Option(DateTime(2000), 'Y2K'), throwsArgumentError);
      expect(Option(DateTime(2000), 'Y2K', json: '2000').json, '2000');
    });

    test('codec equality is symmetric', () {
      final numField = NumberFieldDef('a');
      final intField = _IntDef('a');
      expect(
          numField.codec == intField.codec, intField.codec == numField.codec);
      expect(numField.codec, isNot(intField.codec));
    });

    test('a field whose type is not JSON and has no codec throws, always', () {
      expect(() => DateFieldDef('birth'), throwsArgumentError);
    });

    test('a replacement with another codec decodes the value again', () {
      final byName = ChoiceFieldDef<MaritalStatus>('status',
          options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
      final relabelled = ChoiceFieldDef<MaritalStatus>('status', options: [
        Option(MaritalStatus.single, 'Single'),
        Option(MaritalStatus.married, 'Married'),
      ]);
      final onlySingle = ChoiceFieldDef<MaritalStatus>('status',
          options: [Option(MaritalStatus.single, 'Single')]);

      var s = engine.register(
        engine.initial(initialValues: {'status': 'married'}),
        byName,
      );
      // Encoded by the old codec ("married"), decoded by the new one.
      s = engine.register(s, relabelled);
      expect(s.valueOf(relabelled), MaritalStatus.married);
      expect(s.undecodable, isEmpty);

      s = engine.register(s, onlySingle);
      expect(s.valueOf(onlySingle), isNull);
      expect(s.undecodable, {p('status'): 'married'});
    });
  });

  group('built-in validators', () {
    FieldState stateAfter(FieldDef<Object?> def, Object? value) => engine
        .change(engine.register(engine.initial(), def), def.path, value)
        .stateOf(def)!;

    test('return error codes with their parameters', () {
      expect(
          stateAfter(TextFieldDef('a', validators: [minLength(3)]), 'ab').error,
          ValidationError('minLength', params: {'min': 3}));
      expect(
          stateAfter(TextFieldDef('a', validators: [maxLength(2)]), 'abc')
              .error,
          ValidationError('maxLength', params: {'max': 2}));
      expect(
          stateAfter(TextFieldDef('a', validators: [pattern(r'^\d+$')]), 'x')
              .error,
          ValidationError('pattern', params: {'pattern': r'^\d+$'}));
      expect(stateAfter(TextFieldDef('a', validators: [email()]), 'x@y').error,
          ValidationError('email'));
      expect(stateAfter(NumberFieldDef('a', validators: [min(10)]), 9).error,
          ValidationError('min', params: {'min': 10}));
      expect(stateAfter(NumberFieldDef('a', validators: [max(10)]), 11).error,
          ValidationError('max', params: {'max': 10}));
    });

    test('accept valid values', () {
      expect(
          stateAfter(TextFieldDef('a', validators: [email()]), 'a@b.co').error,
          isNull);
      expect(stateAfter(NumberFieldDef('a', validators: [min(10)]), 10).error,
          isNull);
    });

    test('matches follows the field it reads', () {
      final form = ProfileForm();
      var s = engine.registerAll(engine.initial(), form.fields);
      s = engine.change(s, form.password.path, 'secret123');
      s = engine.change(s, form.confirm.path, 'secret12');
      expect(s.stateOf(form.confirm)!.error,
          ValidationError('matches', params: {'field': 'password'}));
      s = engine.change(s, form.password.path, 'secret12');
      expect(s.stateOf(form.confirm)!.error, isNull);
    });

    test('compare by value', () {
      expect(minLength(3), minLength(3));
      expect(minLength(3), isNot(maxLength(3)));
      expect(matches(TextFieldDef('p')), matches(TextFieldDef('p')));
      expect(email(), email());
    });
  });

  group('forms', () {
    test('a form class registers its fields in order', () {
      final form = ProfileForm();
      final s = engine.registerAll(engine.initial(), form.fields);
      expect(s.visibleFields.map((d) => d.path.toString()),
          ['fullName', 'income', 'maritalStatus', 'password', 'confirm']);
    });

    test('FormDef([...]) still works for forms built as a list', () {
      final form = FormDef([TextFieldDef('a'), TextFieldDef('b')]);
      expect(form.fields.map((d) => d.path), [p('a'), p('b')]);
    });

    test('a duplicated key throws when the form is registered', () {
      final form = FormDef([TextFieldDef('a'), NumberFieldDef('a')]);
      expect(() => engine.registerAll(engine.initial(), form.fields),
          throwsArgumentError);
    });

    test('fields whose conditions read each other fail when built', () {
      expect(() => CyclicForm().fields, throwsA(isA<StackOverflowError>()));
    });

    test('a field keeps its per-code message overrides', () {
      final def = TextFieldDef('a', messages: {'required': 'Needed'});
      expect(def.messages, {'required': 'Needed'});
    });
  });
}

final class _IntDef extends FieldDef<int> {
  _IntDef(super.key);

  @override
  String get type => 'int';
}
