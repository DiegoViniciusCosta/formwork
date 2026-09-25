/// The address of a field: a key, a key inside a group, or a key inside a
/// list item (design doc 0001 §1).
///
/// List items are addressed by a stable id inside the engine
/// (`dependents[#k3f9].name`), so removing an item does not shift the paths
/// after it. The payload and server errors use indexes instead
/// (`dependents[0].name`): those are *serialized* paths, converted only at
/// the edges.
///
/// A key is any non-empty text without `.`, `[` or `]`, the characters
/// that separate segments. Two paths are equal when their canonical text is
/// equal, so a path works as a map key.
final class FieldPath {
  /// Parses [path], for example `address.zipCode` or
  /// `dependents[#k3f9].name`.
  ///
  /// Throws a [FormatException] when [path] is malformed.
  factory FieldPath(String path) => FieldPath._(_parse(path), path);

  FieldPath._(List<PathSegment> segments, this._text)
      : _segments = List.unmodifiable(segments);

  final List<PathSegment> _segments;
  final String _text;

  @override
  bool operator ==(Object other) => other is FieldPath && other._text == _text;

  @override
  int get hashCode => _text.hashCode;

  /// The canonical text of this path, which [FieldPath.new] parses back.
  @override
  String toString() => _text;

  static final _token = RegExp(
    r'([^.\[\]]+)|\[#([A-Za-z0-9_\-]+)\]|\[(0|[1-9]\d{0,9})\]',
  );

  static List<PathSegment> _parse(String path) {
    final segments = <PathSegment>[];
    var i = 0;
    // A path alternates: key, then an optional item, then '.' and a key.
    var expectKey = true;
    while (i < path.length) {
      final match = _token.matchAsPrefix(path, i);
      if (match == null) break;
      if (match.group(1) != null) {
        if (!expectKey) break;
        segments.add(KeySegment(match.group(1)!));
      } else {
        if (expectKey || segments.last is! KeySegment) break;
        segments.add(match.group(2) != null
            ? ItemSegment(match.group(2)!)
            : IndexSegment(int.parse(match.group(3)!)));
      }
      i = match.end;
      expectKey = false;
      if (i < path.length && path[i] == '.') {
        i++;
        expectKey = true;
      }
    }
    if (segments.isEmpty || i != path.length || expectKey) {
      throw FormatException('Malformed field path', path, i);
    }
    return segments;
  }
}

/// Engine-side operations on [FieldPath]. Not exported: the public API is
/// parsing, equality and the canonical text.
extension FieldPathSegments on FieldPath {
  /// The segments, from the outermost key to the field itself.
  List<PathSegment> get segments => _segments;

  /// The path of [key] inside this group or list item.
  FieldPath child(String key) {
    if (key.isEmpty || key.contains(RegExp(r'[.\[\]]'))) {
      throw ArgumentError.value(key, 'key', 'not a valid field key');
    }
    return FieldPath._([..._segments, KeySegment(key)], '$_text.$key');
  }

  /// The path of the list item with the stable [id] inside this list.
  FieldPath item(String id) {
    _checkList();
    if (!RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'not a valid item id');
    }
    return FieldPath._([..._segments, ItemSegment(id)], '$_text[#$id]');
  }

  /// The serialized path of the list item at [index] inside this list.
  FieldPath index(int index) {
    _checkList();
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must not be negative');
    }
    return FieldPath._([..._segments, IndexSegment(index)], '$_text[$index]');
  }

  /// The enclosing group or list item, or `null` for a top-level key.
  FieldPath? get parent {
    if (_segments.length == 1) return null;
    final cut = switch (_segments.last) {
      KeySegment(:final key) => key.length + 1,
      ItemSegment(:final id) => id.length + 3,
      IndexSegment(:final index) => '$index'.length + 2,
    };
    return FieldPath._(
      _segments.sublist(0, _segments.length - 1),
      _text.substring(0, _text.length - cut),
    );
  }

  /// Whether this path addresses list items by index, as in a payload or a
  /// server error, instead of by stable id.
  bool get isSerialized => _segments.any((s) => s is IndexSegment);

  void _checkList() {
    if (_segments.last is! KeySegment) {
      throw StateError('$_text is a list item, not a list');
    }
  }
}

/// One step of a [FieldPath].
sealed class PathSegment {
  /// Subclasses only.
  const PathSegment();
}

/// A field or group key: `address` in `address.zipCode`.
final class KeySegment extends PathSegment {
  /// A segment for [key].
  const KeySegment(this.key);

  /// The key, as written in the catalog.
  final String key;

  @override
  bool operator ==(Object other) => other is KeySegment && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// A list item addressed by its stable id: `[#k3f9]`.
final class ItemSegment extends PathSegment {
  /// A segment for the item with [id].
  const ItemSegment(this.id);

  /// The stable id, which survives inserts and removals.
  final String id;

  @override
  bool operator ==(Object other) => other is ItemSegment && other.id == id;

  @override
  int get hashCode => Object.hash(ItemSegment, id);

  @override
  String toString() => '[#$id]';
}

/// A list item addressed by its position, in serialized paths: `[0]`.
final class IndexSegment extends PathSegment {
  /// A segment for the item at [index].
  const IndexSegment(this.index);

  /// The position of the item in the list.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is IndexSegment && other.index == index;

  @override
  int get hashCode => Object.hash(IndexSegment, index);

  @override
  String toString() => '[$index]';
}
