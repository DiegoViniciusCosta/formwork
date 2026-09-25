// FieldPath's segments and path builders are engine-side, not exported.
import 'package:formwork_core/src/engine/field_path.dart';
import 'package:test/test.dart';

void main() {
  group('FieldPath', () {
    test('a plain key is a one-segment path', () {
      final path = FieldPath('spouseName');
      expect(path.segments, [const KeySegment('spouseName')]);
      expect(path.toString(), 'spouseName');
    });

    test('a group path has one key per level', () {
      final path = FieldPath('address.zipCode');
      expect(path.segments, [
        const KeySegment('address'),
        const KeySegment('zipCode'),
      ]);
    });

    test('a list item is addressed by a stable id', () {
      final path = FieldPath('dependents[#k3f9].name');
      expect(path.segments, [
        const KeySegment('dependents'),
        const ItemSegment('k3f9'),
        const KeySegment('name'),
      ]);
      expect(path.toString(), 'dependents[#k3f9].name');
    });

    test('a serialized path addresses a list item by index', () {
      final path = FieldPath('dependents[0].name');
      expect(path.segments[1], const IndexSegment(0));
      expect(path.isSerialized, isTrue);
      expect(FieldPath('dependents[#k3f9].name').isSerialized, isFalse);
    });

    test('paths built from segments equal parsed paths', () {
      final built = FieldPath('dependents').item('k3f9').child('name');
      expect(built, FieldPath('dependents[#k3f9].name'));
      expect(built.hashCode, FieldPath('dependents[#k3f9].name').hashCode);
      expect(FieldPath('dependents').index(2).child('name'),
          FieldPath('dependents[2].name'));
    });

    test('different paths are not equal', () {
      expect(FieldPath('a.b'), isNot(FieldPath('a')));
      expect(FieldPath('list[#a]'), isNot(FieldPath('list[0]')));
    });

    test('parent drops the last segment', () {
      expect(FieldPath('dependents[#k3f9].name').parent,
          FieldPath('dependents[#k3f9]'));
      expect(FieldPath('name').parent, isNull);
    });

    for (final malformed in [
      '',
      '.a',
      'a.',
      'a..b',
      '[0]',
      'a[#]',
      'a[x]',
      'a[-1]',
      'a[0',
      'a]',
      'a[#k].',
      'a[007]',
      'a[0][#x]',
      'a[#x][0]',
      'a[99999999999]',
    ]) {
      test('rejects the malformed path "$malformed"', () {
        expect(() => FieldPath(malformed), throwsFormatException);
      });
    }

    test('rejects keys and ids that cannot round-trip', () {
      expect(() => FieldPath('a').child('b.c'), throwsArgumentError);
      expect(() => FieldPath('a').child(''), throwsArgumentError);
      expect(() => FieldPath('a').item('x]'), throwsArgumentError);
      expect(() => FieldPath('a').index(-1), throwsArgumentError);
    });

    test('an item is not a list: it has no items of its own', () {
      expect(() => FieldPath('a[#x]').item('y'), throwsStateError);
      expect(() => FieldPath('a[0]').index(1), throwsStateError);
    });

    test('accepts any key without separators, as catalogs do today', () {
      expect(FieldPath('first name').toString(), 'first name');
      expect(FieldPath('2fa-code.é').segments.length, 2);
    });

    test('parent works on item and index segments', () {
      expect(FieldPath('list[#abc]').parent, FieldPath('list'));
      expect(FieldPath('list[12].name').parent!.parent, FieldPath('list'));
    });

    test('a built path round-trips through its text', () {
      final built = FieldPath('a')
          .child('b')
          .item('x_1')
          .child('c')
          .parent!
          .parent!
          .index(10)
          .child('d');
      expect(FieldPath(built.toString()), built);
      expect(FieldPath(built.toString()).segments, built.segments);
    });
  });
}
