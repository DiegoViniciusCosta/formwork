import 'dart:math';

import 'package:formwork_core/formwork_core.dart' hide FormEngine, FormSnapshot;
import 'package:formwork_core/src/engine/engine.dart';
import 'package:test/test.dart' hide isIn;

FieldPath p(String path) => FieldPath(path);

void main() {
  const engine = FormEngine();

  FormSnapshot form(List<FieldDef<Object?>> defs,
          [Map<String, Object?> values = const {}]) =>
      engine.registerAll(engine.initial(initialValues: values), defs);

  group('registration', () {
    test('a registered field takes its initial value, then its default', () {
      final s = form([
        _Text('name', initialValue: 'default'),
        _Text('city', initialValue: 'default'),
      ], {
        'name': 'Ana',
      });
      expect(s.valueOf(_Text('name')), 'Ana');
      expect(s.valueOf(_Text('city')), 'default');
    });

    test('visible fields and the payload follow registration order', () {
      final s = form([_Text('b'), _Text('a'), _Text('c')]);
      expect(s.visibleFields.map((d) => d.path), [p('b'), p('a'), p('c')]);
      expect(s.payload().keys, ['b', 'a', 'c']);
    });

    test('a later register appends', () {
      final s = engine.register(form([_Text('b'), _Text('a')]), _Text('c'));
      expect(s.payload().keys, ['b', 'a', 'c']);
    });

    test('an equal definition returns the identical snapshot', () {
      final s = form([_Text('name', required: true)]);
      expect(identical(engine.register(s, _Text('name', required: true)), s),
          isTrue);
    });

    test('a definition without value equality is replaced', () {
      final def = _NoEquality('rating');
      final s = form([def]);
      final next = engine.register(s, _NoEquality('rating'));
      expect(identical(next, s), isFalse);
      expect(next.changedPaths, {p('rating')});
    });

    test('replacing keeps value and position, and revalidates', () {
      var s = form([_Text('a'), _Text('name'), _Text('b')]);
      s = engine.change(s, p('name'), 'Al');
      final state = s.stateOf(_Text('name'))!;

      s = engine.register(s, _Text('name', validators: [_MinLength(3)]));
      final replaced = s.stateOf(_Text('name'))!;
      expect(replaced.value, 'Al');
      expect(replaced.error, ValidationError('minLength', params: {'min': 3}));
      expect(replaced.generation, state.generation + 1);
      expect(s.payload().keys, ['a', 'name', 'b']);
      expect(s.changedPaths, {p('name')});
    });

    test('a replaced definition reaches the visible list and the payload', () {
      var s = form([_Text('a')]);
      expect(s.visibleFields.single.required, isFalse);
      s = engine.register(s, _Text('a', required: true));
      expect(s.visibleFields.single.required, isTrue);
    });

    test('registering a field changes only it and the fields reading it', () {
      var s = form([
        _Text('x'),
        _Text('reads', visibleWhen: eq('status', 'on')),
        _Text('other'),
      ]);
      final before = s;
      s = engine.register(s, _Text('status', initialValue: 'on'));
      expect(s.changedPaths, {p('status'), p('reads')});
      expect(
          identical(s.stateOf(_Text('x')), before.stateOf(_Text('x'))), isTrue);
    });

    test('a cycle in the middle of a batch registers nothing', () {
      final s = form([_Text('a', visibleWhen: eq('b', 'x'))]);
      expect(
        () => engine.registerAll(s, [
          _Text('c'),
          _Text('b', visibleWhen: eq('a', 'y')),
          _Text('d'),
        ]),
        throwsA(isA<CycleError>()),
      );
      expect(s.stateOf(_Text('c')), isNull);
      expect(s.stateOf(_Text('b')), isNull);
    });

    test('a cycle of conditions throws and registers nothing', () {
      final s = form([_Text('a', visibleWhen: eq('b', 'x'))]);
      expect(
        () => engine.register(s, _Text('b', visibleWhen: eq('a', 'y'))),
        throwsA(isA<CycleError>()),
      );
    });

    test('validators that read each other are allowed', () {
      final s = form([
        _Text('password', validators: [_Matches('confirm')]),
        _Text('confirm', validators: [_Matches('password')]),
      ]);
      expect(s.visibleFields, hasLength(2));
    });
  });

  group('unregistering', () {
    test('the field leaves validation and the payload', () {
      var s = form([_Text('a', required: true), _Text('b')]);
      expect(s.status.isValid, isFalse);
      s = engine.unregister(s, p('a'));
      expect(s.status.isValid, isTrue);
      expect(s.payload().keys, ['b']);
      expect(s.stateOf(_Text('a')), isNull);
      expect(s.changedPaths, {p('a')});
    });

    test('its dependents become inactive, as when it is hidden', () {
      var s = form([
        _Text('status'),
        _Text('spouse', visibleWhen: eq('status', 'married')),
      ], {
        'status': 'married',
      });
      expect(s.stateOf(_Text('spouse'))!.visible, isTrue);
      s = engine.unregister(s, p('status'));
      expect(s.stateOf(_Text('spouse'))!.visible, isFalse);
    });

    test('fields reading it through enabledWhen and validators recompute', () {
      var s = form([
        _Text('mode'),
        _Text('edit', enabledWhen: eq('mode', 'on')),
        _Text('confirm', validators: [_Matches('mode')]),
      ], {
        'mode': 'on',
        'confirm': 'on',
      });
      expect(s.stateOf(_Text('edit'))!.enabled, isTrue);
      s = engine.change(s, p('mode'), 'off');
      expect(s.stateOf(_Text('confirm'))!.error, ValidationError('matches'));

      s = engine.unregister(s, p('mode'));
      // Still read by value: only visibility follows the chain.
      expect(s.stateOf(_Text('edit'))!.enabled, isFalse);
      s = engine.change(s, p('mode'), 'on');
      expect(s.stateOf(_Text('edit'))!.enabled, isTrue);
      expect(s.stateOf(_Text('confirm'))!.error, isNull);
    });

    test('a change while unregistered is what the field finds back', () {
      var s = form([_Text('x'), _Text('y', enabledWhen: eq('x', 'on'))]);
      s = engine.change(s, p('x'), 'on');
      s = engine.unregister(s, p('x'));
      s = engine.change(s, p('x'), 'off');
      expect(s.stateOf(_Text('y'))!.enabled, isFalse);
      s = engine.register(s, _Text('x'));
      expect(s.valueOf(_Text('x')), 'off');
    });

    test('a field that comes back keeps touched and its dirty baseline', () {
      var s = form([_Text('a')], {'a': 'start'});
      s = engine.change(s, p('a'), 'edited');
      s = engine.register(engine.unregister(s, p('a')), _Text('a'));
      final state = s.stateOf(_Text('a'))!;
      expect(state.touched, isTrue);
      expect(state.dirty, isTrue);
      s = engine.change(s, p('a'), 'start');
      expect(s.stateOf(_Text('a'))!.dirty, isFalse);
    });

    test('a null set on an unknown path is what a later field finds', () {
      var s = form([_Text('a')]);
      s = engine.change(s, p('later'), null);
      s = engine.register(s, _Text('later', initialValue: 'default'));
      expect(s.valueOf(_Text('later')), isNull);
    });

    test('its value survives unregister and register again', () {
      var s = form([_Text('a')]);
      s = engine.change(s, p('a'), 'kept');
      s = engine.unregister(s, p('a'));
      s = engine.register(s, _Text('a'));
      expect(s.valueOf(_Text('a')), 'kept');
    });

    test('registering again moves the generation past the old one', () {
      var s = form([_Text('a')]);
      final before = s.stateOf(_Text('a'))!.generation;
      s = engine.register(engine.unregister(s, p('a')), _Text('a'));
      expect(s.stateOf(_Text('a'))!.generation, greaterThan(before));
    });

    test('unregistering an absent path returns the identical snapshot', () {
      final s = form([_Text('a')]);
      expect(identical(engine.unregister(s, p('x')), s), isTrue);
    });
  });

  group('conditions', () {
    test('hiding a field hides the fields whose visibility reads it', () {
      final defs = [
        _Text('hasCar'),
        _Text('carType', visibleWhen: eq('hasCar', 'yes')),
        _Text('plate', visibleWhen: eq('carType', 'car')),
      ];
      var s = form(defs, {'hasCar': 'yes', 'carType': 'car'});
      expect(s.stateOf(_Text('plate'))!.visible, isTrue);

      s = engine.change(s, p('hasCar'), 'no');
      expect(s.stateOf(_Text('carType'))!.visible, isFalse);
      expect(s.stateOf(_Text('plate'))!.visible, isFalse);
      expect(s.payload().keys, ['hasCar']);
    });

    test('a path outside the form is judged by its value only', () {
      var s = form([_Text('spouse', visibleWhen: eq('status', 'married'))],
          {'status': 'married'});
      expect(s.stateOf(_Text('spouse'))!.visible, isTrue);
      s = engine.change(s, p('status'), 'single');
      expect(s.stateOf(_Text('spouse'))!.visible, isFalse);
    });

    test('required or requiredWhen: either makes the field required', () {
      var s = form([
        _Text('always', required: true),
        _Text('when', requiredWhen: eq('kind', 'company')),
        _Text('both', required: true, requiredWhen: eq('kind', 'company')),
      ]);
      expect(s.stateOf(_Text('always'))!.error, ValidationError('required'));
      expect(s.stateOf(_Text('when'))!.required, isFalse);
      expect(s.stateOf(_Text('both'))!.required, isTrue);

      s = engine.change(s, p('kind'), 'company');
      expect(s.stateOf(_Text('when'))!.error, ValidationError('required'));
    });

    test('a disabled field stays in the payload and is not validated', () {
      final s = form([
        _Text('cpf', required: true, enabledWhen: eq('editable', true)),
      ], {
        'editable': false,
      });
      final state = s.stateOf(_Text('cpf'))!;
      expect(state.enabled, isFalse);
      expect(state.error, isNull);
      expect(s.status.isValid, isTrue);
      expect(s.payload().keys, ['cpf']);
    });
  });

  group('validation', () {
    test('validators skip empty values; only required judges them', () {
      var s = form([
        _Text('name', validators: [_MinLength(3)])
      ]);
      expect(s.stateOf(_Text('name'))!.error, isNull);
      s = engine.change(s, p('name'), 'Al');
      expect(s.stateOf(_Text('name'))!.error,
          ValidationError('minLength', params: {'min': 3}));
    });

    test('a cross-field validator revalidates when what it reads changes', () {
      var s = form([
        _Text('password'),
        _Text('confirm', validators: [_Matches('password')]),
      ]);
      s = engine.change(s, p('password'), 'secret');
      s = engine.change(s, p('confirm'), 'secret');
      expect(s.stateOf(_Text('confirm'))!.error, isNull);

      s = engine.change(s, p('password'), 'other');
      expect(s.stateOf(_Text('confirm'))!.error, ValidationError('matches'));
      expect(s.changedPaths, {p('password'), p('confirm')});
    });
  });

  group('changes', () {
    test('a change marks the field touched and dirty', () {
      var s = form([_Text('name')], {'name': 'Ana'});
      expect(s.stateOf(_Text('name'))!.touched, isFalse);
      s = engine.change(s, p('name'), 'Bia');
      expect(s.stateOf(_Text('name'))!.touched, isTrue);
      expect(s.stateOf(_Text('name'))!.dirty, isTrue);
      s = engine.change(s, p('name'), 'Ana');
      expect(s.stateOf(_Text('name'))!.dirty, isFalse);
    });

    test('untouched fields keep the identical state', () {
      final defs = [for (var i = 0; i < 20; i++) _Text('f$i', required: true)];
      final before = form(defs);
      final after = engine.change(before, p('f7'), 'x');
      expect(after.changedPaths, {p('f7')});
      for (final def in defs) {
        if (def.path == p('f7')) continue;
        expect(identical(after.stateOf(def), before.stateOf(def)), isTrue);
      }
    });

    test('the visible list is identical until the active set changes', () {
      var s = form([
        _Text('a'),
        _Text('b', visibleWhen: eq('a', 'show')),
      ]);
      final list = s.visibleFields;
      s = engine.change(s, p('a'), 'typing');
      expect(identical(s.visibleFields, list), isTrue);
      s = engine.change(s, p('a'), 'show');
      expect(s.visibleFields.map((d) => d.path), [p('a'), p('b')]);
    });

    test('a change never alters the previous snapshot', () {
      final before = form([_Text('a', required: true)]);
      engine.change(before, p('a'), 'x');
      expect(before.stateOf(_Text('a'))!.value, isNull);
      expect(before.status.isValid, isFalse);
    });

    test('setting the same value again returns the identical snapshot', () {
      final s = engine.change(form([_Text('a')]), p('a'), 'x');
      expect(identical(engine.change(s, p('a'), 'x'), s), isTrue);
    });
  });

  group('status and submit', () {
    test('the status counts errors and dirty fields', () {
      var s = form([_Text('a', required: true), _Text('b')]);
      expect(s.status, const FormStatus(errorCount: 1));
      s = engine.change(s, p('b'), 'x');
      expect(s.status, const FormStatus(errorCount: 1, dirty: true));
      s = engine.change(s, p('a'), 'y');
      expect(s.status.isValid, isTrue);
    });

    test('the status stays identical while its facts do not change', () {
      var s = form([_Text('a')]);
      s = engine.change(s, p('a'), 'x');
      final status = s.status;
      s = engine.change(s, p('a'), 'xy');
      expect(identical(s.status, status), isTrue);
    });

    test('submit returns the payload only when valid', () {
      var s = form([_Text('a', required: true)]);
      var result = engine.submit(s);
      expect(result.payload, isNull);
      expect(result.snapshot.status.submitAttempted, isTrue);

      s = engine.change(result.snapshot, p('a'), 'x');
      result = engine.submit(s);
      expect(result.payload, {'a': 'x'});
      expect(result.snapshot.status.submitCount, 2);
    });

    test('the first attempt gives new states to the fields with an error', () {
      final s = form([
        _Text('bad', required: true),
        _Text('fine'),
        _Text('hidden', required: true, visibleWhen: eq('x', 'y')),
      ]);
      final first = engine.submit(s).snapshot;
      expect(first.changedPaths, {p('bad')});
      expect(identical(first.stateOf(_Text('fine')), s.stateOf(_Text('fine'))),
          isTrue);

      final second = engine.submit(first).snapshot;
      expect(second.changedPaths, isEmpty);
    });
  });

  test('registering one by one in any order equals registering all at once',
      () {
    final random = Random(7);
    for (var round = 0; round < 200; round++) {
      final defs = _randomForm(random);
      final values = _randomValues(random);
      final all = form(defs, values);

      final shuffled = [...defs]..shuffle(random);
      var one = engine.initial(initialValues: values);
      for (final def in shuffled) {
        one = engine.register(one, def);
      }
      for (final def in defs) {
        _expectSameState(one.stateOf(def)!, all.stateOf(def)!, '$def');
      }
      expect(one.status.errorCount, all.status.errorCount);
    }
  });

  test('incremental changes equal computing the form from scratch', () {
    final random = Random(11);
    for (var round = 0; round < 150; round++) {
      final defs = _randomForm(random);
      final values = _randomValues(random);
      var s = form(defs, values);
      // What the form holds, fields and user data alike.
      final known = {...values};
      for (var step = 0; step < 30; step++) {
        // Some steps unregister a field, change a value meanwhile and
        // register the field again: churn must not change the outcome.
        final churn =
            random.nextInt(4) == 0 ? defs[random.nextInt(defs.length)] : null;
        if (churn != null) s = engine.unregister(s, churn.path);

        final path = 'f${random.nextInt(defs.length + 2)}';
        final value = _randomValue(random);
        s = engine.change(s, p(path), value);
        known[path] = value;

        if (churn != null) s = engine.register(s, churn);

        final scratch = form(defs, {
          ...known,
          for (final def in defs) def.path.toString(): s.stateOf(def)!.value,
        });
        for (final def in defs) {
          _expectSameState(s.stateOf(def)!, scratch.stateOf(def)!, '$def');
        }
        expect(s.status.errorCount, scratch.status.errorCount);
        // Registering again appends, so compare the payload as a map.
        expect(s.payload(), equals(scratch.payload()));
      }
    }
  });

  test('work per change does not grow with the form (PRINCIPLES.md §2)', () {
    int workFor(int size) {
      final counter = _Counter();
      final defs = [
        for (var i = 0; i < size; i++)
          _Text('f$i', required: true, validators: [counter]),
        _Text('toggle'),
        _Text('shown', visibleWhen: eq('toggle', 'on'), validators: [counter]),
      ];
      var s = form(defs, {for (var i = 0; i < size; i++) 'f$i': 'x'});
      counter.calls = 0;
      s = engine.change(s, p('f3'), 'typed');
      s = engine.change(s, p('toggle'), 'on');
      return counter.calls + s.changedPaths.length;
    }

    expect(workFor(10000), workFor(10));
  });
}

void _expectSameState(FieldState a, FieldState b, String reason) {
  expect(a.value, b.value, reason: '$reason value');
  expect(a.visible, b.visible, reason: '$reason visible');
  expect(a.enabled, b.enabled, reason: '$reason enabled');
  expect(a.required, b.required, reason: '$reason required');
  expect(a.error, b.error, reason: '$reason error');
}

/// A random acyclic form: each field's conditions read earlier fields or
/// two paths outside the form.
List<FieldDef<Object?>> _randomForm(Random random) {
  final size = 2 + random.nextInt(8);
  Condition? maybe(int i) {
    if (random.nextInt(3) != 0) return null;
    final read = random.nextInt(i + 2);
    // Paths f{size} and f{size + 1} are never registered: user data.
    final path = read < i ? 'f$read' : 'f${size + read - i}';
    return switch (random.nextInt(3)) {
      0 => eq(path, _randomValue(random)),
      1 => not(empty(path)),
      _ => any([eq(path, 'a'), eq(path, 'b')]),
    };
  }

  return [
    for (var i = 0; i < size; i++)
      _Text(
        'f$i',
        required: random.nextBool(),
        visibleWhen: maybe(i),
        enabledWhen: maybe(i),
        requiredWhen: maybe(i),
        validators: [
          if (random.nextBool()) _MinLength(2),
          if (i > 0 && random.nextBool()) _Matches('f${random.nextInt(i)}'),
        ],
      ),
  ];
}

Map<String, Object?> _randomValues(Random random) => {
      for (var i = 0; i < 10; i++)
        if (random.nextBool()) 'f$i': _randomValue(random),
    };

Object? _randomValue(Random random) =>
    const [null, '', 'a', 'b', 'abc'][random.nextInt(5)];

final class _Text extends FieldDef<String> {
  _Text(
    super.key, {
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.validators,
    super.initialValue,
  });

  @override
  String get type => 'text';

  @override
  bool operator ==(Object other) =>
      other is _Text &&
      other.path == path &&
      other.required == required &&
      other.visibleWhen == visibleWhen &&
      other.enabledWhen == enabledWhen &&
      other.requiredWhen == requiredWhen &&
      other.initialValue == initialValue &&
      _sameList(other.validators, validators);

  @override
  int get hashCode => Object.hash(path, required, visibleWhen, enabledWhen,
      requiredWhen, initialValue, Object.hashAll(validators));
}

bool _sameList(List<Object?> a, List<Object?> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

final class _NoEquality extends FieldDef<int> {
  _NoEquality(super.key);

  @override
  String get type => 'rating';
}

final class _MinLength extends Validator<String> {
  const _MinLength(this.min);

  final int min;

  @override
  ValidationError? validate(String value, _) => value.length < min
      ? ValidationError('minLength', params: {'min': min})
      : null;

  @override
  bool operator ==(Object other) => other is _MinLength && other.min == min;

  @override
  int get hashCode => min.hashCode;
}

final class _Matches extends Validator<String> {
  _Matches(String other) : other = FieldPath(other);

  final FieldPath other;

  @override
  Set<FieldPath> get reads => {other};

  @override
  ValidationError? validate(
          String value, Object? Function(FieldPath path) valueOf) =>
      value == valueOf(other) ? null : ValidationError('matches');

  @override
  bool operator ==(Object o) => o is _Matches && o.other == other;

  @override
  int get hashCode => other.hashCode;
}

/// Counts validator calls; shared by every field of a form.
final class _Counter extends Validator<String> {
  int calls = 0;

  @override
  ValidationError? validate(String value, _) {
    calls++;
    return null;
  }
}
