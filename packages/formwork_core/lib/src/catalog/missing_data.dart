import '../engine/field_def.dart';
import '../engine/field_path.dart';
import 'form_catalog.dart';

/// Profile completion: ask only what is still missing (design doc 0003).
///
/// A recipe on top of the catalog, not part of the engine: it narrows the
/// form the engine receives.
extension MissingData on FormCatalog {
  /// The paths of the fields the user still has to answer. Hides nothing:
  /// use it to highlight missing fields in the whole form, or narrow the
  /// form with [onlyMissing].
  ///
  /// A field is missing when its value in [data] (JSON, as the engine's
  /// `initialValues`) fails the field's own rules:
  /// - required and empty, or a value its codec cannot decode: missing;
  /// - filled but invalid, such as a malformed e-mail: missing;
  /// - optional and empty, or disabled, whatever its value: not missing.
  ///
  /// A field with `visibleWhen` counts only when it is relevant: when a
  /// field its condition reads is also missing, the rule is resolved on
  /// screen; otherwise it is evaluated now. Every field the condition
  /// reads must be relevant too, so a hidden field hides what hangs below
  /// it.
  Set<FieldPath> missingKeys(Map<String, Object?> data) =>
      _MissingData(this, data).missing;

  /// This catalog narrowed to the fields the user still has to answer: the
  /// [missingKeys], plus the known fields that link two of them, in catalog
  /// order.
  ///
  /// A known field K is kept when some chain of `visibleWhen` reads runs
  /// from a missing field, through K, to another missing field (design doc
  /// 0003, decided after acceptance). The engine then sees the whole chain,
  /// and hiding its top also hides its bottom. Pass the same [data] to the
  /// engine as `initialValues`, and K shows its stored value.
  FormCatalog onlyMissing(Map<String, Object?> data) {
    final result = _MissingData(this, data);
    final keep = {...result.missing, ...result.links()};
    return narrowCatalog(this, keep);
  }
}

/// One [MissingData] computation over a catalog and its data.
final class _MissingData {
  _MissingData(this.catalog, Map<String, Object?> data)
      : data = {for (final e in data.entries) FieldPath(e.key): e.value} {
    for (final def in catalog.fields) {
      byPath[def.path] = def;
      final (value, ok) = decodeFieldValue(def, this.data[def.path]);
      values[def.path] = value;
      if (!ok) undecodable.add(def.path);
    }
    for (final def in catalog.fields) {
      if (_fails(def)) pending.add(def.path);
    }
    missing = {
      for (final def in catalog.fields)
        if (pending.contains(def.path) && _relevant(def, {def.path})) def.path,
    };
  }

  final FormCatalog catalog;
  final Map<FieldPath, Object?> data;
  final byPath = <FieldPath, FieldDef<Object?>>{};
  final values = <FieldPath, Object?>{};
  final undecodable = <FieldPath>{};
  final pending = <FieldPath>{};
  late final Set<FieldPath> missing;

  /// A field's decoded value, or the raw data of a path outside the form.
  Object? valueOf(FieldPath path) =>
      byPath.containsKey(path) ? values[path] : data[path];

  bool _fails(FieldDef<Object?> def) {
    // A disabled field is read-only data: the user cannot answer it.
    if (!(def.enabledWhen?.evaluate(valueOf) ?? true)) return false;
    if (undecodable.contains(def.path)) return true;
    final required =
        def.required || (def.requiredWhen?.evaluate(valueOf) ?? false);
    return validateField(def, values[def.path],
            required: required, valueOf: valueOf) !=
        null;
  }

  /// Whether [def] would be shown to this user; `seen` stops a cycle among
  /// known fields from looping.
  bool _relevant(FieldDef<Object?> def, Set<FieldPath> seen) {
    final condition = def.visibleWhen;
    if (condition == null) return true;
    final reads = condition.reads;
    if (!reads.any(pending.contains) && !condition.evaluate(valueOf)) {
      return false;
    }
    for (final read in reads) {
      final reader = byPath[read];
      if (reader == null || !seen.add(read)) continue;
      if (!_relevant(reader, seen)) return false;
    }
    return true;
  }

  /// The known fields on a chain of `visibleWhen` reads between two
  /// missing fields: reachable from a missing field and reaching one,
  /// through known fields only.
  Set<FieldPath> links() {
    Set<FieldPath> reachable(Iterable<FieldPath> Function(FieldPath) next) {
      final found = <FieldPath>{};
      final pendingWalk = [...missing];
      while (pendingWalk.isNotEmpty) {
        for (final other in next(pendingWalk.removeLast())) {
          if (!byPath.containsKey(other) || missing.contains(other)) continue;
          if (found.add(other)) pendingWalk.add(other);
        }
      }
      return found;
    }

    Iterable<FieldPath> reads(FieldPath path) =>
        byPath[path]?.visibleWhen?.reads ?? const {};
    final readers = <FieldPath, List<FieldPath>>{};
    for (final def in catalog.fields) {
      for (final read in reads(def.path)) {
        (readers[read] ??= []).add(def.path);
      }
    }

    // Known fields a missing field reads, through known fields, and known
    // fields that read a missing one: a link is both.
    final readByMissing = reachable(reads);
    final readingMissing = reachable((path) => readers[path] ?? const []);
    return readByMissing.intersection(readingMissing);
  }
}
