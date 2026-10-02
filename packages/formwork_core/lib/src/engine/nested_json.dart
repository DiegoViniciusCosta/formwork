import 'field_path.dart';

/// Values keyed by path, from data in the payload's shape (design doc 0009
/// §2): each key as given, plus every value inside a nested object at the
/// path that reaches it, so `{'address': {'zipCode': '01000'}}` also holds
/// `address.zipCode`. A key given flat wins over a nested one, and a
/// deeper key over a shallower one. Engine-side; not exported.
Map<FieldPath, Object?> flattenJson(Map<String, Object?> data) {
  final result = {for (final e in data.entries) FieldPath(e.key): e.value};
  // The deepest sources first, so each one fills only what is still free.
  final sources = result.entries.toList()
    ..sort((a, b) => b.key.segments.length - a.key.segments.length);
  for (final MapEntry(key: path, :value) in sources) {
    _spread(result, path, value);
  }
  return result;
}

final _key = RegExp(r'^[^.\[\]]+$');

void _spread(Map<FieldPath, Object?> into, FieldPath path, Object? value) {
  if (value is! Map) return;
  for (final MapEntry(:key, value: child) in value.entries) {
    if (key is! String || !_key.hasMatch(key)) continue;
    final childPath = path.child(key);
    if (into.containsKey(childPath)) continue;
    into[childPath] = child;
    _spread(into, childPath, child);
  }
}

/// The payload's shape for [values] keyed by path, in their order: groups
/// become objects (design doc 0009 §2). Engine-side; not exported.
Map<String, Object?> nestJson(Iterable<(FieldPath, Object?)> values) {
  final result = <String, Object?>{};
  for (final (path, value) in values) {
    var into = result;
    final segments = path.segments;
    for (var i = 0; i < segments.length - 1; i++) {
      final key = (segments[i] as KeySegment).key;
      into = into.putIfAbsent(key, () => <String, Object?>{})
          as Map<String, Object?>;
    }
    into[(segments.last as KeySegment).key] = value;
  }
  return result;
}
