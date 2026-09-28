/// An immutable hash map that shares structure between versions: a hash
/// array mapped trie, as in Clojure's `PersistentHashMap` (design docs 0002
/// and 0007 §5).
///
/// [put] and [remove] return a new map and copy only the nodes on one
/// root-to-leaf path, at most seven arrays of up to 32 slots. Every other
/// node, and every other value, is shared with the previous version, which
/// stays valid. Internal: the package barrel does not export it.
final class PersistentMap<K extends Object, V> {
  /// An empty map.
  const PersistentMap.empty() : this._(null, 0);

  const PersistentMap._(this._root, this.length);

  final _Node? _root;

  /// The number of keys.
  final int length;

  /// The value for [key], or `null` when absent. See [containsKey] to tell
  /// a `null` value apart.
  V? operator [](K key) {
    final found = _find(key);
    return identical(found, _absent) ? null : found as V;
  }

  /// Whether [key] has a value, `null` included.
  bool containsKey(K key) => !identical(_find(key), _absent);

  Object? _find(K key) {
    final root = _root;
    return root == null ? _absent : root.get(key, _hash(key), 0);
  }

  /// This map with [key] set to [value]. Returns this same instance when
  /// [key] already holds an identical value.
  PersistentMap<K, V> put(K key, V value) {
    final added = _Flag();
    final root =
        (_root ?? _BitmapNode.empty).put(key, value, _hash(key), 0, added);
    if (identical(root, _root)) return this;
    return PersistentMap._(root, added.value ? length + 1 : length);
  }

  /// This map without [key]. Returns this same instance when [key] is
  /// absent.
  PersistentMap<K, V> remove(K key) {
    final root = _root;
    if (root == null) return this;
    final next = root.remove(key, _hash(key), 0);
    if (identical(next, root)) return this;
    return PersistentMap._(next, length - 1);
  }

  /// Every entry, in no particular order.
  Iterable<MapEntry<K, V>> get entries sync* {
    final root = _root;
    if (root == null) return;
    for (final (key, value) in root.entries()) {
      yield MapEntry(key as K, value as V);
    }
  }
}

/// Marks a missing key, so that a `null` value can be told apart.
const Object _absent = _Absent();

final class _Absent {
  const _Absent();
}

/// Set by `put` when a key was added rather than replaced.
final class _Flag {
  bool value = false;
}

/// 32 bits of the key's hash, five of them consumed per level.
int _hash(Object key) => key.hashCode & 0xffffffff;

int _bitCount(int i) {
  i = i - ((i >> 1) & 0x55555555);
  i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
  i = (i + (i >> 4)) & 0x0f0f0f0f;
  return (i + (i >> 8) + (i >> 16) + (i >> 24)) & 0x3f;
}

sealed class _Node {
  const _Node();

  /// The value for [key], or [_absent].
  Object? get(Object key, int hash, int shift);

  /// This node with [key] set, or this same node when nothing changed.
  _Node put(Object key, Object? value, int hash, int shift, _Flag added);

  /// This node without [key], this same node when [key] is absent, or
  /// `null` when nothing is left.
  _Node? remove(Object key, int hash, int shift);

  Iterable<(Object, Object?)> entries();
}

/// Up to 32 slots, one per 5-bit chunk of the hash at this level, stored
/// compactly: [bitmap] says which slots are used. [array] holds a pair per
/// used slot: a key and its value, or `null` and a child node.
final class _BitmapNode extends _Node {
  const _BitmapNode(this.bitmap, this.array);

  static const empty = _BitmapNode(0, []);

  final int bitmap;
  final List<Object?> array;

  int _index(int bit) => _bitCount(bitmap & (bit - 1));

  @override
  Object? get(Object key, int hash, int shift) {
    final bit = 1 << ((hash >> shift) & 31);
    if (bitmap & bit == 0) return _absent;
    final i = _index(bit);
    final k = array[2 * i];
    final v = array[2 * i + 1];
    if (k == null) return (v! as _Node).get(key, hash, shift + 5);
    return key == k ? v : _absent;
  }

  @override
  _Node put(Object key, Object? value, int hash, int shift, _Flag added) {
    final bit = 1 << ((hash >> shift) & 31);
    final i = _index(bit);
    if (bitmap & bit == 0) {
      added.value = true;
      return _BitmapNode(bitmap | bit, [
        ...array.sublist(0, 2 * i),
        key,
        value,
        ...array.sublist(2 * i),
      ]);
    }
    final k = array[2 * i];
    final v = array[2 * i + 1];
    if (k == null) {
      final child = v! as _Node;
      final next = child.put(key, value, hash, shift + 5, added);
      return identical(next, child) ? this : _replace(i, null, next);
    }
    if (key == k) return identical(value, v) ? this : _replace(i, k, value);
    added.value = true;
    return _replace(
      i,
      null,
      _pair(shift + 5, k, v, _hash(k), key, value, hash),
    );
  }

  @override
  _Node? remove(Object key, int hash, int shift) {
    final bit = 1 << ((hash >> shift) & 31);
    if (bitmap & bit == 0) return this;
    final i = _index(bit);
    final k = array[2 * i];
    final v = array[2 * i + 1];
    if (k == null) {
      final child = v! as _Node;
      final next = child.remove(key, hash, shift + 5);
      if (identical(next, child)) return this;
      return next == null ? _without(bit, i) : _replace(i, null, next);
    }
    return key == k ? _without(bit, i) : this;
  }

  _Node _replace(int i, Object? key, Object? value) => _BitmapNode(
      bitmap,
      List.of(array)
        ..[2 * i] = key
        ..[2 * i + 1] = value);

  _Node? _without(int bit, int i) {
    if (bitmap == bit) return null;
    return _BitmapNode(
      bitmap ^ bit,
      [...array.sublist(0, 2 * i), ...array.sublist(2 * i + 2)],
    );
  }

  @override
  Iterable<(Object, Object?)> entries() sync* {
    for (var i = 0; i < array.length; i += 2) {
      final k = array[i];
      if (k == null) {
        yield* (array[i + 1]! as _Node).entries();
      } else {
        yield (k, array[i + 1]);
      }
    }
  }
}

/// Keys whose 32-bit hashes are all equal, in a flat list of pairs.
final class _CollisionNode extends _Node {
  const _CollisionNode(this.hash, this.array);

  final int hash;
  final List<Object?> array;

  int _find(Object key) {
    for (var i = 0; i < array.length; i += 2) {
      if (array[i] == key) return i;
    }
    return -1;
  }

  @override
  Object? get(Object key, int hash, int shift) {
    if (hash != this.hash) return _absent;
    final i = _find(key);
    return i < 0 ? _absent : array[i + 1];
  }

  @override
  _Node put(Object key, Object? value, int hash, int shift, _Flag added) {
    if (hash != this.hash) {
      // A different hash reached this level: nest this node one level down
      // in a bitmap node, which then tells the two hashes apart.
      final bit = 1 << ((this.hash >> shift) & 31);
      return _BitmapNode(bit, [null, this]).put(key, value, hash, shift, added);
    }
    final i = _find(key);
    if (i < 0) {
      added.value = true;
      return _CollisionNode(hash, [...array, key, value]);
    }
    if (identical(array[i + 1], value)) return this;
    return _CollisionNode(hash, List.of(array)..[i + 1] = value);
  }

  @override
  _Node? remove(Object key, int hash, int shift) {
    if (hash != this.hash) return this;
    final i = _find(key);
    if (i < 0) return this;
    if (array.length == 2) return null;
    return _CollisionNode(
      hash,
      [...array.sublist(0, i), ...array.sublist(i + 2)],
    );
  }

  @override
  Iterable<(Object, Object?)> entries() sync* {
    for (var i = 0; i < array.length; i += 2) {
      yield (array[i]!, array[i + 1]);
    }
  }
}

/// A node holding two keys that met at [shift].
_Node _pair(
  int shift,
  Object k1,
  Object? v1,
  int h1,
  Object k2,
  Object? v2,
  int h2,
) {
  if (h1 == h2) return _CollisionNode(h1, [k1, v1, k2, v2]);
  final ignored = _Flag();
  return _BitmapNode.empty
      .put(k1, v1, h1, shift, ignored)
      .put(k2, v2, h2, shift, ignored);
}
