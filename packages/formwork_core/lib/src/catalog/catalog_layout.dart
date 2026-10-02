import '../engine/deep_equality.dart';
import '../engine/field_path.dart';
import '../engine/layout_node.dart';

/// What the tolerance rule skipped in a catalog's `layout` (design doc 0006
/// §5).
enum LayoutIssueKind {
  /// A node without a text `type` or a `children` list, or a child that is
  /// neither a key nor an object; it is skipped, and its fields render at
  /// the end.
  malformedNode,

  /// A key placed a second time; it stays at its first place.
  repeatedKey,

  /// A key the catalog does not define; it is skipped.
  unknownKey,
}

/// Something the tolerance rule skipped in a catalog's `layout`. A node has
/// no path, so it is located by its place in the JSON, such as
/// `layout[0].children[1]`.
final class LayoutIssue {
  /// An issue of [kind] at [location].
  const LayoutIssue(this.kind, this.location, [this.detail]);

  /// What was skipped.
  final LayoutIssueKind kind;

  /// Where, in the catalog's `layout`.
  final String location;

  /// The key, or the JSON that was skipped.
  final Object? detail;

  @override
  bool operator ==(Object other) =>
      other is LayoutIssue &&
      other.kind == kind &&
      other.location == location &&
      deepEquals(other.detail, detail);

  @override
  int get hashCode => Object.hash(kind, location, deepHash(detail));

  @override
  String toString() => 'LayoutIssue(${kind.name}, $location'
      '${detail == null ? '' : ', $detail'})';
}

/// Reads a catalog's `layout` [json] into a root node, keeping the keys in
/// [known] and reporting what it skips. Catalog-side; not exported.
(LayoutNode?, List<LayoutIssue>) readLayout(
  Object? json,
  Set<FieldPath> known,
) {
  final reader = _LayoutReader(known);
  if (json == null) return (null, reader.issues);
  if (json is! List) {
    reader.issues
        .add(LayoutIssue(LayoutIssueKind.malformedNode, 'layout', json));
    return (null, reader.issues);
  }
  final root = LayoutNode('root', children: reader.children(json, 'layout'));
  return (root, reader.issues);
}

/// One [readLayout] call.
final class _LayoutReader {
  _LayoutReader(this.known);

  final Set<FieldPath> known;
  final issues = <LayoutIssue>[];
  final placed = <FieldPath>{};

  List<Object> children(List<Object?> entries, String at) => [
        for (var i = 0; i < entries.length; i++)
          if (child(entries[i], '$at[$i]') case final read?) read,
      ];

  Object? child(Object? entry, String at) {
    switch (entry) {
      case final String key:
        final FieldPath path;
        try {
          path = FieldPath(key);
        } on FormatException {
          return _skip(LayoutIssueKind.unknownKey, at, key);
        }
        if (!known.contains(path)) {
          return _skip(LayoutIssueKind.unknownKey, at, key);
        }
        if (!placed.add(path)) {
          return _skip(LayoutIssueKind.repeatedKey, at, key);
        }
        return path;
      case {'type': final String type, 'children': final List<Object?> list}:
        return LayoutNode(
          type,
          children: children(list, '$at.children'),
          props: {
            for (final MapEntry(:key, :value) in entry.entries)
              if (key is String && key != 'type' && key != 'children')
                key: value,
          },
        );
      default:
        return _skip(LayoutIssueKind.malformedNode, at, entry);
    }
  }

  Null _skip(LayoutIssueKind kind, String at, Object? detail) {
    issues.add(LayoutIssue(kind, at, detail));
    return null;
  }
}
