import 'field_path.dart';
import 'persistent_map.dart';

/// Thrown when registering a field would make its conditions depend on
/// themselves, for example `a` visible when `b` is, and `b` when `a` is
/// (design docs 0001 §5 and 0007 §4).
///
/// A cycle written in code is a programmer error. A JSON catalog does not
/// throw: the fields that close a cycle are skipped and reported.
final class CycleError extends Error {
  /// A cycle through [paths], which starts and ends with the same path.
  CycleError(List<FieldPath> paths) : paths = List.unmodifiable(paths);

  /// The paths around the cycle, each one read by the one before it; the
  /// first and last are the same.
  final List<FieldPath> paths;

  @override
  String toString() =>
      'CycleError: the conditions of these fields read each other: '
      '${paths.join(' → ')}';
}

/// Which fields read which paths (design doc 0001 §5): the reverse index
/// that lets a change recompute only the rules that read it.
///
/// Immutable and persistent: [add] and [remove] return a new graph and cost
/// what the field touches, plus the paths its conditions can reach when
/// looking for a cycle (0007 §4). Only conditions take part in cycles; a
/// cross-field validator only revalidates, and no chain follows it.
/// Internal: the package barrel exports only [CycleError].
final class DependencyGraph {
  /// A graph with no fields.
  const DependencyGraph.empty()
      : _reads = const PersistentMap.empty(),
        _conditionDependents = const PersistentMap.empty(),
        _validatorDependents = const PersistentMap.empty();

  const DependencyGraph._(
    this._reads,
    this._conditionDependents,
    this._validatorDependents,
  );

  /// Field -> what its rules read.
  final PersistentMap<FieldPath, _Reads> _reads;

  /// Path -> fields whose conditions read it, as a set.
  final PersistentMap<FieldPath, PersistentMap<FieldPath, bool>>
      _conditionDependents;

  /// Path -> fields whose validators read it, as a set.
  final PersistentMap<FieldPath, PersistentMap<FieldPath, bool>>
      _validatorDependents;

  /// The fields whose conditions read [path].
  Iterable<FieldPath> conditionDependents(FieldPath path) =>
      _conditionDependents[path]?.entries.map((e) => e.key) ?? const [];

  /// The fields whose validators read [path].
  Iterable<FieldPath> validatorDependents(FieldPath path) =>
      _validatorDependents[path]?.entries.map((e) => e.key) ?? const [];

  /// The paths the conditions of [field] read.
  Set<FieldPath> conditionReadsOf(FieldPath field) =>
      _reads[field]?.conditions ?? const {};

  /// This graph with [field]'s edges set to what its conditions and
  /// validators read, replacing any it had. Returns this same graph when
  /// nothing changed.
  ///
  /// Throws a [CycleError], and changes nothing, when [conditionReads]
  /// would close a cycle of conditions.
  DependencyGraph add(
    FieldPath field, {
    Set<FieldPath> conditionReads = const {},
    Set<FieldPath> validatorReads = const {},
  }) {
    final old = _reads[field];
    if (old != null &&
        _sameSet(old.conditions, conditionReads) &&
        _sameSet(old.validators, validatorReads)) {
      return this;
    }
    final base = remove(field);
    // Unchanged condition edges cannot close a cycle the graph did not have.
    if (old == null || !_sameSet(old.conditions, conditionReads)) {
      base._checkCycle(field, conditionReads);
    }

    final reads = _Reads(
      Set.unmodifiable(conditionReads),
      Set.unmodifiable(validatorReads),
    );
    return DependencyGraph._(
      base._reads.put(field, reads),
      _link(base._conditionDependents, reads.conditions, field),
      _link(base._validatorDependents, reads.validators, field),
    );
  }

  /// This graph without [field]'s own edges. Edges from fields that read
  /// [field] stay: they still depend on it. Returns this same graph when
  /// [field] has no edges.
  DependencyGraph remove(FieldPath field) {
    final old = _reads[field];
    if (old == null) return this;
    return DependencyGraph._(
      _reads.remove(field),
      _unlink(_conditionDependents, old.conditions, field),
      _unlink(_validatorDependents, old.validators, field),
    );
  }

  /// Throws when some path in [reads] reaches [field] through conditions.
  void _checkCycle(FieldPath field, Set<FieldPath> reads) {
    // A cycle through [field] needs some condition that reads it. Without
    // one, which is the case when fields register in order, there is
    // nothing to walk.
    if (!_conditionDependents.containsKey(field) && !reads.contains(field)) {
      return;
    }
    // Iterative depth-first walk over what conditions read, so a long chain
    // cannot overflow the stack. `cameFrom` marks what was seen, which keeps
    // the walk O(reachable nodes), and leads back along the cycle.
    final cameFrom = <FieldPath, FieldPath>{};
    final pending = <FieldPath>[];
    void visit(FieldPath next, FieldPath from) {
      if (cameFrom.containsKey(next)) return;
      cameFrom[next] = from;
      pending.add(next);
    }

    for (final read in reads) {
      visit(read, field);
    }
    while (pending.isNotEmpty) {
      final at = pending.removeLast();
      if (at == field) {
        final cycle = [field];
        for (var step = cameFrom[field]!;
            step != field;
            step = cameFrom[step]!) {
          cycle.add(step);
        }
        throw CycleError([...cycle, field].reversed.toList());
      }
      for (final next in conditionReadsOf(at)) {
        visit(next, at);
      }
    }
  }

  static PersistentMap<FieldPath, PersistentMap<FieldPath, bool>> _link(
    PersistentMap<FieldPath, PersistentMap<FieldPath, bool>> index,
    Set<FieldPath> reads,
    FieldPath field,
  ) {
    for (final read in reads) {
      index = index.put(
        read,
        (index[read] ?? const PersistentMap.empty()).put(field, true),
      );
    }
    return index;
  }

  static PersistentMap<FieldPath, PersistentMap<FieldPath, bool>> _unlink(
    PersistentMap<FieldPath, PersistentMap<FieldPath, bool>> index,
    Set<FieldPath> reads,
    FieldPath field,
  ) {
    for (final read in reads) {
      final fields = index[read]!.remove(field);
      index = fields.length == 0 ? index.remove(read) : index.put(read, fields);
    }
    return index;
  }
}

final class _Reads {
  const _Reads(this.conditions, this.validators);

  final Set<FieldPath> conditions;
  final Set<FieldPath> validators;
}

bool _sameSet(Set<FieldPath> a, Set<FieldPath> b) =>
    a.length == b.length && a.containsAll(b);
