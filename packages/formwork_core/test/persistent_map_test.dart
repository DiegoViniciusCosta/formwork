import 'dart:math';

import 'package:formwork_core/formwork_core.dart';
import 'package:formwork_core/src/engine/persistent_map.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentMap', () {
    test('starts empty', () {
      final map = PersistentMap<FieldPath, int>.empty();
      expect(map.length, 0);
      expect(map[FieldPath('a')], isNull);
      expect(map.containsKey(FieldPath('a')), isFalse);
      expect(map.entries, isEmpty);
    });

    test('put returns a new map and leaves the previous one intact', () {
      final empty = PersistentMap<FieldPath, int>.empty();
      final one = empty.put(FieldPath('a'), 1);
      final two = one.put(FieldPath('a'), 2);

      expect(empty.length, 0);
      expect(one[FieldPath('a')], 1);
      expect(two[FieldPath('a')], 2);
      expect(two.length, 1);
    });

    test('putting the identical value returns the identical map', () {
      final value = Object();
      final map = PersistentMap<FieldPath, Object>.empty()
          .put(FieldPath('a'), value)
          .put(FieldPath('b'), Object());
      expect(identical(map.put(FieldPath('a'), value), map), isTrue);
    });

    test('removing an absent key returns the identical map', () {
      final map = PersistentMap<FieldPath, int>.empty().put(FieldPath('a'), 1);
      expect(identical(map.remove(FieldPath('b')), map), isTrue);
    });

    test('tells a null value apart from a missing key', () {
      final map =
          PersistentMap<FieldPath, int?>.empty().put(FieldPath('a'), null);
      expect(map.containsKey(FieldPath('a')), isTrue);
      expect(map.length, 1);
    });

    test('keys with the same hash stay distinct', () {
      var map = PersistentMap<_Key, int>.empty();
      for (var i = 0; i < 5; i++) {
        map = map.put(_Key(i, hash: 7), i);
      }
      map = map.put(_Key(99, hash: 7 | 1 << 20), 99);

      expect(map.length, 6);
      for (var i = 0; i < 5; i++) {
        expect(map[_Key(i, hash: 7)], i);
      }
      expect(map[_Key(99, hash: 7 | 1 << 20)], 99);

      final three = map[_Key(3, hash: 7)]!;
      expect(identical(map.put(_Key(3, hash: 7), three), map), isTrue);

      map = map.remove(_Key(2, hash: 7));
      expect(map.length, 5);
      expect(map.containsKey(_Key(2, hash: 7)), isFalse);
      expect(map[_Key(3, hash: 7)], 3);
    });

    test('a change shares every untouched value with the previous map', () {
      var map = PersistentMap<FieldPath, List<int>>.empty();
      for (var i = 0; i < 1000; i++) {
        map = map.put(FieldPath('f$i'), [i]);
      }
      final next = map.put(FieldPath('f500'), [-1]);
      for (var i = 0; i < 1000; i++) {
        if (i == 500) continue;
        expect(
            identical(next[FieldPath('f$i')], map[FieldPath('f$i')]), isTrue);
      }
    });

    for (final (name, keyOf) in <(String, _Key Function(int))>[
      ('spread hashes', (i) => _Key(i, hash: i * 2654435761)),
      ('many collisions', (i) => _Key(i, hash: i % 7)),
      ('hashes that differ only in high bits', (i) => _Key(i, hash: i << 25)),
    ]) {
      test('behaves like a Map over random operations: $name', () {
        final random = Random(42);
        var map = PersistentMap<_Key, int>.empty();
        final reference = <_Key, int>{};
        final history = <(PersistentMap<_Key, int>, Map<_Key, int>)>[];

        for (var step = 0; step < 5000; step++) {
          final key = keyOf(random.nextInt(300));
          if (random.nextInt(3) == 0) {
            map = map.remove(key);
            reference.remove(key);
          } else {
            final value = random.nextInt(1000);
            map = map.put(key, value);
            reference[key] = value;
          }
          if (step % 500 == 0) history.add((map, Map.of(reference)));

          expect(map.length, reference.length);
          expect(map[key], reference[key]);
          expect(map.containsKey(key), reference.containsKey(key));
          if (map[key] case final value?) {
            expect(identical(map.put(key, value), map), isTrue);
          }
        }

        expect(Map.fromEntries(map.entries), reference);
        // Old versions are untouched by every later change.
        for (final (old, expected) in history) {
          expect(Map.fromEntries(old.entries), expected);
        }
      });
    }
  });
}

/// A key with a chosen hash, to force collisions and deep tries.
final class _Key {
  _Key(this.id, {required int hash}) : _hash = hash;

  final int id;
  final int _hash;

  @override
  bool operator ==(Object other) => other is _Key && other.id == id;

  @override
  int get hashCode => _hash;

  @override
  String toString() => 'k$id';
}
