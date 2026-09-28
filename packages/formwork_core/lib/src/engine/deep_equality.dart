// Value equality for immutable data that holds collections. Internal: the
// package barrel does not export it.

/// A read-only copy of [value], all the way down through maps, lists and
/// sets.
Object? freeze(Object? value) => switch (value) {
      Map() => Map<Object?, Object?>.unmodifiable({
          for (final e in value.entries) e.key: freeze(e.value),
        }),
      List() => List<Object?>.unmodifiable(value.map(freeze)),
      Set() => Set<Object?>.unmodifiable(value.map(freeze)),
      _ => value,
    };

/// Whether [a] and [b] are equal, comparing maps, lists and sets by
/// content.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length &&
        a.every((x) => b.any((y) => deepEquals(x, y))) &&
        b.every((y) => a.any((x) => deepEquals(x, y)));
  }
  return a == b;
}

/// A hash consistent with [deepEquals].
int deepHash(Object? value) => switch (value) {
      Map() => Object.hashAllUnordered([
          for (final e in value.entries) Object.hash(e.key, deepHash(e.value)),
        ]),
      List() => Object.hashAll(value.map(deepHash)),
      Set() => Object.hashAllUnordered(value.map(deepHash)),
      _ => value.hashCode,
    };
