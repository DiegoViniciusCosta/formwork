import 'package:formwork_core/formwork_core.dart';
// copyWith is engine-side, not exported.
import 'package:formwork_core/src/engine/field_state.dart';
import 'package:test/test.dart';

void main() {
  final def = _TextDef('name');

  group('FieldState', () {
    test('starts empty: no value, no error, visible and enabled', () {
      final state = FieldState(def: def);
      expect(state.value, isNull);
      expect(state.error, isNull);
      expect(state.visible, isTrue);
      expect(state.enabled, isTrue);
      expect(state.required, isFalse);
      expect(state.touched, isFalse);
      expect(state.dirty, isFalse);
      expect(state.validating, isFalse);
      expect(state.generation, 0);
    });

    test('copyWith changes only what it is given', () {
      final state = FieldState(def: def, value: 'Ana', required: true);
      final next = state.copyWith(touched: true);
      expect(next.value, 'Ana');
      expect(next.required, isTrue);
      expect(next.touched, isTrue);
    });

    test('copyWith can clear the value and the error', () {
      final state = FieldState(
        def: def,
        value: 'Ana',
        error: ValidationError('minLength', params: {'min': 5}),
      );
      final next = state.copyWith(value: null, clearError: true);
      expect(next.value, isNull);
      expect(next.error, isNull);
    });

    test('carries its definition, which copyWith can replace', () {
      final other = _TextDef('name');
      expect(FieldState(def: def).def, same(def));
      expect(FieldState(def: def).copyWith(def: other).def, same(other));
    });

    test('copyWith moves the generation', () {
      expect(FieldState(def: def).copyWith(generation: 3).generation, 3);
    });

    test('copyWith returns a new instance: identity means "changed"', () {
      final state = FieldState(def: def, value: 'Ana');
      expect(identical(state.copyWith(value: 'Ana'), state), isFalse);
    });

    test('is compared by identity, not by value', () {
      // The engine keeps unchanged states identical, and views rebuild on
      // identity (0001 §6). Two equal-looking states are still two states.
      expect(FieldState(def: def, value: 1) == FieldState(def: def, value: 1),
          isFalse);
    });
  });
}

final class _TextDef extends FieldDef<String> {
  _TextDef(super.key);

  @override
  String get type => 'text';
}
