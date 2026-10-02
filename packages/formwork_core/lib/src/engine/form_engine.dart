import 'dart:collection';

import 'deep_equality.dart';
import 'dependency_graph.dart';
import 'field_def.dart';
import 'field_path.dart';
import 'field_state.dart';
import 'form_status.dart';
import 'list_field_def.dart';
import 'nested_json.dart';
import 'persistent_map.dart';
import 'server_errors.dart';
import 'validation_error.dart';

/// The state of a form at one moment: every registered field's
/// [FieldState], plus what the engine needs to apply the next change
/// (design docs 0001 §6 and 0007 §2).
///
/// Immutable. The engine returns a new snapshot for every change, and
/// every field whose state did not change keeps the identical [FieldState]
/// instance, so a view rebuilds a field if and only if its state is not
/// identical to the previous one. [changedPaths] lists the fields that did
/// change.
final class FormSnapshot {
  FormSnapshot._({
    required PersistentMap<FieldPath, _Entry> entries,
    required PersistentMap<int, FieldPath> order,
    required int nextSeq,
    required Map<FieldPath, Object?> data,
    required PersistentMap<FieldPath, _Retired> retired,
    required PersistentMap<FieldPath, Object?> undecodable,
    required DependencyGraph graph,
    required this.changedPaths,
    required this.status,
    required PersistentMap<FieldPath, bool> errored,
    required int dirtyCount,
    required PersistentMap<FieldPath, int> groups,
    required PersistentMap<FieldPath, List<FieldPath>> items,
    required PersistentMap<FieldPath, bool> lists,
    required int nextItemId,
    required Map<FieldPath, List<String>> sentItems,
    required int clock,
    required int submitStartedAt,
    required _VisibleList visible,
  })  : _entries = entries,
        _order = order,
        _nextSeq = nextSeq,
        _data = data,
        _retired = retired,
        _undecodable = undecodable,
        _graph = graph,
        _errored = errored,
        _dirtyCount = dirtyCount,
        _groups = groups,
        _items = items,
        _lists = lists,
        _nextItemId = nextItemId,
        _sentItems = sentItems,
        _clock = clock,
        _submitStartedAt = submitStartedAt,
        _visible = visible;

  /// Registered fields.
  final PersistentMap<FieldPath, _Entry> _entries;

  /// Registration order: sequence number -> path. Unregistering leaves a
  /// hole; replacing keeps the number.
  final PersistentMap<int, FieldPath> _order;
  final int _nextSeq;

  /// Values for paths that are not registered, from `initialValues` and
  /// from changes to them: user data that conditions can read.
  final Map<FieldPath, Object?> _data;

  /// Fields that were registered and then removed: their last value and
  /// generation. Dependents see them as inactive (design doc 0007 §2).
  final PersistentMap<FieldPath, _Retired> _retired;

  final PersistentMap<FieldPath, Object?> _undecodable;

  final DependencyGraph _graph;

  /// The paths of the fields with an error, as a set.
  final PersistentMap<FieldPath, bool> _errored;

  /// How many fields differ from their initial value.
  final int _dirtyCount;

  /// Group path -> how many registered fields it holds (design doc 0009
  /// §1). A path in here is a group, never a field.
  final PersistentMap<FieldPath, int> _groups;

  /// List item path -> the paths of its fields, in the order its list's
  /// `itemFields` returned them (design doc 0009 §3).
  final PersistentMap<FieldPath, List<FieldPath>> _items;

  /// The paths of the registered lists, as a set.
  final PersistentMap<FieldPath, bool> _lists;

  /// The last item id given; ids are never reused.
  final int _nextItemId;

  /// Each list's item ids when the current or last send started, to read
  /// server errors by index (design doc 0009 §4).
  final Map<FieldPath, List<String>> _sentItems;

  /// Counts registrations and the user's changes to fields, to tell which
  /// ones changed during a submit.
  final int _clock;

  /// [_clock] when the current or last send started.
  final int _submitStartedAt;

  final _VisibleList _visible;

  /// The facts about the whole form (design doc 0008 §1). The identical
  /// status is kept until one of them changes.
  final FormStatus status;

  /// The fields whose [FieldState] is not identical to the one in the
  /// previous snapshot: registered, replaced, changed or recomputed, and
  /// unregistered ones.
  final Set<FieldPath> changedPaths;

  /// The state of [def]'s field, or `null` when no field is registered at
  /// its path.
  FieldState? stateOf(FieldDef<Object?> def) => _entries[def.path]?.state;

  /// The value of [def]'s field, or `null` when it has none or is not
  /// registered.
  T? valueOf<T>(FieldDef<T> def) => _entries[def.path]?.state.value as T?;

  /// The definitions of the active fields, in registration order, with a
  /// list's item fields right after it, in item order. The identical list
  /// is returned until an active field is shown, hidden, registered,
  /// unregistered or replaced, or a visible list's items change.
  List<FieldDef<Object?>> get visibleFields => _visible.value ??=
      List.unmodifiable([for (final s in _activeStates()) s.def]);

  /// The values of the active fields as JSON, through each field's codec,
  /// in registration order. Groups become nested objects and lists arrays
  /// of objects, in item order (design doc 0009 §2):
  /// `{'address': {'zipCode': ...}, 'dependents': [{'name': ...}]}`. A
  /// group with no active field is left out. Disabled fields are included:
  /// they are read-only data.
  Map<String, Object?> payload() => _json(_topStates(), null);

  /// Raw values that a registered field's codec could not decode, by path
  /// (decision 18 of design doc 0001). The field holds `null` instead. An
  /// entry leaves when its field gets a new value or is unregistered.
  Map<FieldPath, Object?> get undecodable =>
      Map.unmodifiable(Map.fromEntries(_undecodable.entries));

  /// The first field, in the order of [visibleFields], that shows an
  /// error: where a failed submit moves focus (design doc 0008 §4). `null`
  /// when none does. Costs the number of fields with an error, not the
  /// size of the form, plus, for an error inside a list item, the length
  /// of that list.
  FieldPath? get firstErrorPath {
    FieldPath? first;
    List<int>? best;
    for (final MapEntry(key: path) in _errored.entries) {
      final state = _entries[path]!.state;
      if (!state.touched && !status.submitAttempted) continue;
      final rank = _rank(path);
      if (best == null || _before(rank, best)) (first, best) = (path, rank);
    }
    return first;
  }

  /// Where [path] stands in [visibleFields]: its registration number, after
  /// its list's rank and its item's index when it is inside an item.
  List<int> _rank(FieldPath path) {
    final seq = _entries[path]!.seq;
    final owner = itemOf(path);
    if (owner == null) return [seq];
    final ids = _entries[owner.list]!.state.value as List<String>;
    return [..._rank(owner.list), ids.indexOf(owner.id), seq];
  }

  static bool _before(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.length < b.length;
  }

  Iterable<FieldState> _activeStates() sync* {
    for (final state in _topStates()) {
      yield state;
      yield* _itemStatesOf(state);
    }
  }

  /// The active fields outside any list item, in registration order.
  Iterable<FieldState> _topStates() sync* {
    for (var seq = 0; seq < _nextSeq; seq++) {
      final path = _order[seq];
      if (path == null || itemOf(path) != null) continue;
      final state = _entries[path]!.state;
      if (state.visible) yield state;
    }
  }

  /// The active fields of [list]'s items, in item order, nested lists
  /// included; none when [list] is not a list.
  Iterable<FieldState> _itemStatesOf(FieldState list) sync* {
    final def = list.def;
    if (def is! ListFieldDef) return;
    for (final id in list.value as List<String>) {
      for (final state in _itemStates(def.itemPath(id))) {
        yield state;
        yield* _itemStatesOf(state);
      }
    }
  }

  /// The active fields of the item at [item], in `itemFields` order.
  Iterable<FieldState> _itemStates(FieldPath item) sync* {
    for (final path in _items[item] ?? const <FieldPath>[]) {
      final state = _entries[path]?.state;
      if (state != null && state.visible) yield state;
    }
  }

  /// [states] as one JSON object, with paths taken relative to [base].
  Map<String, Object?> _json(Iterable<FieldState> states, FieldPath? base) =>
      nestJson([
        for (final s in states)
          (
            base == null
                ? s.def.path
                : FieldPath('${s.def.path}'.substring('$base'.length + 1)),
            switch (s.def) {
              final ListFieldDef list => [
                  for (final id in s.value as List<String>)
                    _json(_itemStates(list.itemPath(id)), list.itemPath(id)),
                ],
              final def => encodeFieldValue(def, s.value),
            },
          ),
      ]);
}

/// The result of [FormEngine.submit]: the next snapshot and, when the form
/// is valid, the payload to send.
typedef SubmitResult = ({FormSnapshot snapshot, Map<String, Object?>? payload});

/// Pure form rules: takes a snapshot and returns a new one. Holds no
/// state, not even the fields: definitions live in the snapshot, so they
/// can be registered and removed at any time (design doc 0007 §2).
final class FormEngine {
  /// The engine. It has no configuration.
  const FormEngine();

  /// A snapshot with no fields.
  ///
  /// [initialValues] is what is already known, keyed by path: it fills
  /// fields as they register, and conditions read the values of paths that
  /// no field registers. It takes the payload's shape: a field finds its
  /// value through nested objects, and a key given flat (`address.zipCode`)
  /// wins over a nested one (design doc 0009 §2).
  FormSnapshot initial({Map<String, Object?> initialValues = const {}}) =>
      FormSnapshot._(
        entries: const PersistentMap.empty(),
        order: const PersistentMap.empty(),
        nextSeq: 0,
        data: Map.unmodifiable(flattenJson(initialValues)),
        retired: const PersistentMap.empty(),
        undecodable: const PersistentMap.empty(),
        graph: const DependencyGraph.empty(),
        changedPaths: const {},
        status: const FormStatus(),
        errored: const PersistentMap.empty(),
        dirtyCount: 0,
        groups: const PersistentMap.empty(),
        items: const PersistentMap.empty(),
        lists: const PersistentMap.empty(),
        nextItemId: 0,
        sentItems: const {},
        clock: 0,
        submitStartedAt: 0,
        visible: _VisibleList(),
      );

  /// [s] with [def] registered. See [registerAll].
  FormSnapshot register(FormSnapshot s, FieldDef<Object?> def) =>
      registerAll(s, [def]);

  /// [s] with every one of [defs] registered, in order.
  ///
  /// - A new field takes its value from an earlier registration at the
  ///   same path, else from the initial values, else from
  ///   [FieldDef.initialValue]. It goes after every registered field.
  /// - A field registered again with an equal definition changes nothing.
  ///   When every definition is equal, [s] itself is returned.
  /// - A different definition replaces the old one, keeping the value and
  ///   the position, and moves the field's generation.
  ///
  /// Initial values arrive as JSON and are decoded by each field's codec
  /// as it registers; see [FormSnapshot.undecodable].
  ///
  /// Throws a [CycleError] when the conditions of the fields would read
  /// each other. Throws an [ArgumentError] when two of [defs] share a key,
  /// when a key is both a field and a group (`address` and
  /// `address.zipCode`), or when a rule reads a group instead of a field
  /// (decision 29 of design doc 0001), and when a key addresses a list
  /// item, until lists ship (design doc 0009 §3). Nothing is registered
  /// then.
  FormSnapshot registerAll(
    FormSnapshot s,
    Iterable<FieldDef<Object?>> defs,
  ) {
    final t = _Transition(s);
    final seen = <FieldPath>{};
    for (final def in defs) {
      if (!seen.add(def.path)) {
        throw ArgumentError.value(def.path.toString(), 'defs', 'Duplicate key');
      }
      t.register(def);
    }
    return t.finish();
  }

  /// [s] without the field at [path]. Returns [s] when nothing is
  /// registered there.
  ///
  /// The value is kept, so the field finds it if it registers again. The
  /// fields whose visibility reads it become inactive, exactly as when it
  /// is hidden.
  FormSnapshot unregister(FormSnapshot s, FieldPath path) =>
      (_Transition(s)..unregister(path)).finish();

  /// [s] with the value at [path] set to [value].
  ///
  /// For a registered field this marks it touched, updates `dirty`, and
  /// revalidates it and every field whose rules read it; nothing else is
  /// recomputed. [value] is then of the field's type. A list changes only
  /// through [addItem], [removeItem] and [moveItem]: `change` throws an
  /// [ArgumentError] for it.
  ///
  /// A path no field registers is user data that conditions may read. Its
  /// [value] is JSON, as in `initialValues`, and a field that registers
  /// there later decodes it. A path whose field was unregistered keeps a
  /// value of that field's type, for when it comes back.
  ///
  /// Returns [s] when nothing changes.
  FormSnapshot change(FormSnapshot s, FieldPath path, Object? value) =>
      (_Transition(s)..change(path, value)).finish();

  /// [s] with a new item in the list at [list], at the end or at index
  /// [at] (design doc 0009 §4). Its fields register with [values], JSON in
  /// the payload's shape, keyed by their path inside the item. The new id
  /// is in the list's value, at that index.
  ///
  /// Counts as a change of the list: it is touched, and revalidated. Going
  /// past `maxItems` is allowed, and gives the `maxItems` error. Throws an
  /// [ArgumentError] when no list is registered at [list], and a
  /// [RangeError] when [at] is outside the list.
  FormSnapshot addItem(
    FormSnapshot s,
    FieldPath list, {
    Map<String, Object?> values = const {},
    int? at,
  }) =>
      (_Transition(s)..addItem(list, values, at)).finish();

  /// [s] without the list item at [item], such as `dependents[#3]`
  /// (`ListFieldDef.itemPath`). Its fields are forgotten: their values do
  /// not come back. Throws an [ArgumentError] when there is no such item.
  FormSnapshot removeItem(FormSnapshot s, FieldPath item) =>
      (_Transition(s)..removeItem(item)).finish();

  /// [s] with the list item at [item] moved to index [to]. The item's
  /// fields keep their identical states; only the list changes. Throws an
  /// [ArgumentError] when there is no such item, and a [RangeError] when
  /// [to] is outside the list.
  FormSnapshot moveItem(FormSnapshot s, FieldPath item, int to) =>
      (_Transition(s)..moveItem(item, to)).finish();

  /// Marks a submit attempt and returns the payload when the form is valid
  /// (design docs 0004 and 0008 §2). Sending it is up to the caller.
  ///
  /// The first attempt shows every field's error: those fields get new
  /// states, so their views rebuild. While `status.submitting`, returns
  /// [s] itself and no payload, which guards against a double tap.
  SubmitResult submit(FormSnapshot s) {
    if (s.status.submitting) return (snapshot: s, payload: null);
    final next = (_Transition(s)..submit()).finish();
    return (
      snapshot: next,
      payload: next.status.isValid ? next.payload() : null,
    );
  }

  /// Marks a send as started, after [submit] returned a payload (design
  /// doc 0008 §2): `status.submitting` becomes true, and the form error
  /// and outcome of the previous send are cleared.
  FormSnapshot startSubmitting(FormSnapshot s) =>
      (_Transition(s)..startSubmitting()).finish();

  /// Records the server's [answer] and ends the send.
  ///
  /// `null` or an empty answer is `accepted`. Otherwise it is `rejected`,
  /// and the errors apply with `source: server`: the form error to
  /// `status.formError`, each field error to its field until the field
  /// changes or unregisters. An error for a field the user changed, or
  /// that registered, since [startSubmitting] may describe another value,
  /// and is discarded. So is an error for a path no field registers: the
  /// app handles unknown keys when it builds the answer.
  FormSnapshot completeSubmit(FormSnapshot s, ServerErrors? answer) =>
      (_Transition(s)..completeSubmit(answer)).finish();

  /// Ends a send that got no answer, such as a network error, a timeout
  /// or a cancel: `status.lastSubmit` becomes `abandoned`, and nothing is
  /// applied.
  FormSnapshot abandonSubmit(FormSnapshot s) =>
      (_Transition(s)..abandonSubmit()).finish();
}

/// A registered field: its state, registration order and the value it had
/// when it registered, which `dirty` compares with.
final class _Entry {
  const _Entry(
    this.state,
    this.seq,
    this.initial, {
    this.serverError,
    this.changedAt = 0,
  });

  final FieldState state;
  final int seq;
  final Object? initial;

  /// The server's error for this field, until the field changes (design
  /// doc 0008 §2).
  final ValidationError? serverError;

  /// The snapshot clock when the field registered or the user last
  /// changed it.
  final int changedAt;

  _Entry withState(FieldState state) => _Entry(state, seq, initial,
      serverError: serverError, changedAt: changedAt);
}

/// What an unregistered field leaves behind, for when it comes back.
final class _Retired {
  const _Retired(
    this.def,
    this.value,
    this.generation,
    this.initial, {
    required this.touched,
  });

  /// The definition the value was decoded with.
  final FieldDef<Object?> def;
  final Object? value;
  final int generation;
  final Object? initial;
  final bool touched;
}

/// The visible list, built on first read and shared by every snapshot that
/// has the same active fields with the same definitions. A cache of a pure
/// function of the snapshot: every transition that shows, hides,
/// registers, unregisters or replaces an active field starts a new one
/// (`activeSetChanged`).
final class _VisibleList {
  List<FieldDef<Object?>>? value;
}

/// One engine call: working copies of the snapshot's persistent parts, and
/// the fields left to recompute. Lives only inside that call.
final class _Transition {
  _Transition(this.from)
      : entries = from._entries,
        order = from._order,
        nextSeq = from._nextSeq,
        data = from._data,
        retired = from._retired,
        undecodable = from._undecodable,
        graph = from._graph,
        errored = from._errored,
        dirtyCount = from._dirtyCount,
        groups = from._groups,
        items = from._items,
        lists = from._lists,
        nextItemId = from._nextItemId,
        sentItems = from._sentItems,
        clock = from._clock,
        submitStartedAt = from._submitStartedAt,
        submitCount = from.status.submitCount,
        formError = from.status.formError,
        submitting = from.status.submitting,
        lastSubmit = from.status.lastSubmit;

  final FormSnapshot from;
  PersistentMap<FieldPath, _Entry> entries;
  PersistentMap<int, FieldPath> order;
  int nextSeq;
  Map<FieldPath, Object?> data;
  PersistentMap<FieldPath, _Retired> retired;
  PersistentMap<FieldPath, Object?> undecodable;
  DependencyGraph graph;
  PersistentMap<FieldPath, bool> errored;
  int dirtyCount;
  PersistentMap<FieldPath, int> groups;
  PersistentMap<FieldPath, List<FieldPath>> items;
  PersistentMap<FieldPath, bool> lists;
  int nextItemId;
  Map<FieldPath, List<String>> sentItems;
  int clock;
  int submitStartedAt;
  int submitCount;
  ValidationError? formError;
  bool submitting;
  SubmitOutcome? lastSubmit;

  final changed = <FieldPath>{};
  bool activeSetChanged = false;

  /// Fields to recompute, each at most once in the queue at a time.
  final pending = Queue<FieldPath>();
  final queued = <FieldPath>{};

  /// Registers [def]. [item] is true for a list item's field, which only
  /// the engine registers. [json], when [hasJson], is its value, before
  /// any initial value.
  void register(
    FieldDef<Object?> def, {
    bool item = false,
    bool hasJson = false,
    Object? json,
  }) {
    final path = def.path;
    final old = entries[path];
    if (old != null && old.state.def == def) return;
    if (!item && path.segments.any((s) => s is! KeySegment)) {
      throw ArgumentError.value('$path', 'defs',
          'A list item: its list registers it (design doc 0009 §3)');
    }
    if (old != null &&
        (old.state.def is ListFieldDef) != (def is ListFieldDef)) {
      throw ArgumentError.value('$path', 'defs', 'A list stays a list');
    }

    graph = graph.add(
      path,
      conditionReads: def.conditionReads,
      validatorReads: def.validatorReads,
    );
    if (old == null) _enterGroups(path);
    for (final read in {...def.conditionReads, ...def.validatorReads}) {
      if (groups.containsKey(read) || lists.containsKey(read)) {
        throw ArgumentError.value('$path', 'defs',
            'Its rules read $read as a whole; rules read fields (0001, 29)');
      }
    }
    if (old == null &&
        def is ListFieldDef &&
        (graph.conditionDependents(path).isNotEmpty ||
            graph.validatorDependents(path).isNotEmpty)) {
      throw ArgumentError.value('$path', 'defs',
          'A rule reads this list; rules read fields (0001, 29)');
    }

    if (old != null) {
      final from = old.state.def;
      // An undecodable value was null from registration on, so it was
      // also the initial value: a second chance applies to both.
      final secondChance = undecodable.containsKey(path) && old.initial == null;
      final value = _recode(path, from, def, old.state.value);
      final initial =
          secondChance ? value : _recode(null, from, def, old.initial);
      _put(
        path,
        _Entry(
          old.state.copyWith(
            def: def,
            value: value,
            dirty: !deepEquals(value, initial),
            generation: old.state.generation + 1,
          ),
          old.seq,
          initial,
          serverError: old.serverError,
          changedAt: old.changedAt,
        ),
        old.state,
      );
      // The visible list holds definitions: a new one must reach it.
      if (old.state.visible) activeSetChanged = true;
      _enqueue(path);
      // A new codec can change the value, which its readers see.
      _enqueueReaders(path);
      if (def is ListFieldDef) {
        for (final id in old.state.value as List<String>) {
          _syncItem(def, id);
        }
      }
      return;
    }

    var gone = retired[path];
    if (gone != null && (gone.def is ListFieldDef) != (def is ListFieldDef)) {
      // A list does not come back as another kind of field, nor the
      // reverse: start afresh.
      retired = retired.remove(path);
      gone = null;
    }
    if (def is ListFieldDef) {
      return _registerList(def, gone, hasJson ? json : data[path]);
    }
    final value = gone != null
        ? _recode(path, gone.def, def, gone.value)
        : hasJson
            ? _decode(path, def, json)
            : data.containsKey(path)
                ? _decode(path, def, data[path])
                : def.initialValue;
    retired = retired.remove(path);
    final seq = nextSeq++;
    order = order.put(seq, path);
    final initial =
        gone != null ? _recode(null, gone.def, def, gone.initial) : value;
    // Starts hidden and without error; recomputing sets the real state. A
    // field that comes back finds itself as it was: value, touched, dirty.
    final state = FieldState(
      def: def,
      value: value,
      visible: false,
      touched: gone?.touched ?? false,
      dirty: !deepEquals(value, initial),
      generation: (gone?.generation ?? 0) + 1,
    );
    // Registering counts as a change: an answer to a send that started
    // before it may describe another value (design doc 0008 §2).
    _put(path, _Entry(state, seq, initial, changedAt: ++clock), null);
    _enqueue(path);
    _enqueueReaders(path);
  }

  /// Registers a new list: its items come back with it when it was
  /// unregistered, and are read from [json] (a JSON array) otherwise.
  void _registerList(ListFieldDef def, _Retired? gone, Object? json) {
    final path = def.path;
    if (gone == null && json != null && json is! List) {
      // Not an array: listed like any value the engine cannot read.
      undecodable = undecodable.put(path, json);
    }
    final elements = gone != null
        ? const []
        : json is List
            ? json
            : const [];
    final ids = gone != null
        ? gone.value as List<String>
        : List<String>.unmodifiable([
            for (var i = 0; i < elements.length; i++) '${++nextItemId}',
          ]);
    final initial = gone != null ? gone.initial : ids;
    retired = retired.remove(path);
    lists = lists.put(path, true);
    final seq = nextSeq++;
    order = order.put(seq, path);
    final state = FieldState(
      def: def,
      value: ids,
      visible: false,
      touched: gone?.touched ?? false,
      dirty: !deepEquals(ids, initial),
      generation: (gone?.generation ?? 0) + 1,
    );
    _put(path, _Entry(state, seq, initial, changedAt: ++clock), null);
    _enqueue(path);
    for (var i = 0; i < ids.length; i++) {
      _addItemFields(def, ids[i], i < elements.length ? elements[i] : null);
    }
  }

  /// Registers the fields of [list]'s item [id], with [values] (a JSON
  /// object keyed by path inside the item) before any other value.
  void _addItemFields(ListFieldDef list, String id, Object? values) {
    final item = list.itemPath(id);
    final flat = values is Map
        ? flattenJson({
            for (final MapEntry(:key, :value) in values.entries)
              if (key is String) key: value,
          })
        : const <FieldPath, Object?>{};
    final paths = <FieldPath>[];
    for (final def in list.fieldsAt(id)) {
      final inside = _inside(item, def.path);
      _once(paths, def.path);
      register(def,
          item: true, hasJson: flat.containsKey(inside), json: flat[inside]);
      paths.add(def.path);
    }
    items = items.put(item, List.unmodifiable(paths));
  }

  /// Registers what [list] now returns for item [id], and forgets the
  /// fields it no longer returns.
  void _syncItem(ListFieldDef list, String id) {
    final item = list.itemPath(id);
    final before = items[item] ?? const <FieldPath>[];
    final paths = <FieldPath>[];
    for (final def in list.fieldsAt(id)) {
      _inside(item, def.path);
      _once(paths, def.path);
      register(def, item: true);
      paths.add(def.path);
    }
    for (final path in before) {
      if (!paths.contains(path)) unregister(path, forget: true);
    }
    items = items.put(item, List.unmodifiable(paths));
  }

  /// Throws when `itemFields` returned [path] twice.
  static void _once(List<FieldPath> paths, FieldPath path) {
    if (paths.contains(path)) {
      throw ArgumentError.value('$path', 'itemFields', 'Duplicate key');
    }
  }

  /// [path] relative to [item], which must hold it.
  static FieldPath _inside(FieldPath item, FieldPath path) {
    final prefix = '$item.';
    final text = '$path';
    if (!text.startsWith(prefix)) {
      throw ArgumentError.value(text, 'itemFields', 'Not inside $item');
    }
    return FieldPath(text.substring(prefix.length));
  }

  /// Records a new field at [path] in its groups, after checking that
  /// [path] is not a group, is not inside a field, and is not inside a
  /// group some rule reads.
  void _enterGroups(FieldPath path) {
    if (groups.containsKey(path)) {
      throw ArgumentError.value('$path', 'defs', 'A group, not a field');
    }
    for (final group in groupsOf(path)) {
      if (entries.containsKey(group)) {
        throw ArgumentError.value('$path', 'defs', 'Inside the field $group');
      }
      if (graph.conditionDependents(group).isNotEmpty ||
          graph.validatorDependents(group).isNotEmpty) {
        throw ArgumentError.value('$path', 'defs',
            'Makes $group a group, which a rule reads (0001, 29)');
      }
      groups = groups.put(group, (groups[group] ?? 0) + 1);
    }
  }

  /// Unregisters the field at [path], and a list's items with it. When
  /// [forget], nothing is kept for a later registration.
  void unregister(FieldPath path, {bool forget = false}) {
    final old = entries[path];
    if (old == null) return;
    final def = old.state.def;
    if (def is ListFieldDef) {
      for (final id in old.state.value as List<String>) {
        final item = def.itemPath(id);
        for (final field in items[item] ?? const <FieldPath>[]) {
          unregister(field, forget: forget);
        }
        items = items.remove(item);
      }
      lists = lists.remove(path);
    }
    for (final group in groupsOf(path)) {
      final count = groups[group]! - 1;
      groups = count == 0 ? groups.remove(group) : groups.put(group, count);
    }
    entries = entries.remove(path);
    order = order.remove(old.seq);
    retired = forget
        ? retired.remove(path)
        : retired.put(
            path,
            _Retired(
              old.state.def,
              old.state.value,
              old.state.generation,
              old.initial,
              touched: old.state.touched,
            ),
          );
    graph = graph.remove(path);
    undecodable = undecodable.remove(path);
    errored = errored.remove(path);
    if (old.state.dirty) dirtyCount--;
    if (old.state.visible) activeSetChanged = true;
    changed.add(path);
    _enqueueReaders(path);
  }

  void change(FieldPath path, Object? value) {
    final old = entries[path];
    if (old == null) {
      // A removed field's value is what it finds when it comes back, and
      // what its readers see meanwhile; anything else is user data. An
      // explicit null is a value too: it wins over `initialValue` later.
      if (retired[path] case final gone?) {
        if (deepEquals(gone.value, value)) return;
        retired = retired.put(
          path,
          _Retired(
            gone.def,
            value,
            gone.generation,
            gone.initial,
            touched: gone.touched,
          ),
        );
      } else {
        if (data.containsKey(path) && deepEquals(data[path], value)) return;
        data = Map.unmodifiable({...data, path: value});
      }
      _enqueueReaders(path);
      return;
    }
    final state = old.state;
    if (state.def is ListFieldDef) {
      throw ArgumentError.value(
          '$path', 'path', 'A list: use addItem, removeItem or moveItem');
    }
    if (state.touched && deepEquals(state.value, value)) return;
    undecodable = undecodable.remove(path);
    _put(
      path,
      _Entry(
        state.copyWith(
          value: value,
          touched: true,
          dirty: !deepEquals(value, old.initial),
        ),
        old.seq,
        old.initial,
        changedAt: ++clock,
      ),
      state,
    );
    _enqueue(path);
    _enqueueReaders(path);
  }

  void addItem(FieldPath list, Object? values, int? at) {
    final def = _listAt(list);
    final ids = [...entries[list]!.state.value as List<String>];
    final index = at ?? ids.length;
    RangeError.checkValueInInterval(index, 0, ids.length, 'at');
    final id = '${++nextItemId}';
    ids.insert(index, id);
    _addItemFields(def, id, values);
    _setItems(list, ids);
  }

  void removeItem(FieldPath item) {
    final (list, id) = _itemParts(item);
    final ids = [...entries[list]!.state.value as List<String>]..remove(id);
    for (final field in items[item] ?? const <FieldPath>[]) {
      unregister(field, forget: true);
    }
    items = items.remove(item);
    _setItems(list, ids);
  }

  void moveItem(FieldPath item, int to) {
    final (list, id) = _itemParts(item);
    final ids = [...entries[list]!.state.value as List<String>];
    RangeError.checkValueInInterval(to, 0, ids.length - 1, 'to');
    if (ids.indexOf(id) == to) return;
    ids
      ..remove(id)
      ..insert(to, id);
    _setItems(list, ids);
  }

  ListFieldDef _listAt(FieldPath path) => switch (entries[path]?.state.def) {
        final ListFieldDef def => def,
        _ => throw ArgumentError.value('$path', 'list', 'No list there'),
      };

  /// The list and the id of the existing item at [item].
  (FieldPath, String) _itemParts(FieldPath item) {
    final list = item.parent;
    if (item.segments.last case ItemSegment(:final id) when list != null) {
      final ids = entries[list]?.state.value;
      if (entries[list]?.state.def is ListFieldDef &&
          (ids as List<String>).contains(id)) {
        return (list, id);
      }
    }
    throw ArgumentError.value('$item', 'item', 'No list item there');
  }

  /// Gives the list at [list] the item [ids]: a change of the list.
  void _setItems(FieldPath list, List<String> ids) {
    final old = entries[list]!;
    final state = old.state;
    final value = List<String>.unmodifiable(ids);
    _put(
      list,
      _Entry(
        state.copyWith(
          value: value,
          touched: true,
          dirty: !deepEquals(value, old.initial),
        ),
        old.seq,
        old.initial,
        changedAt: ++clock,
      ),
      state,
    );
    // The order of the visible fields follows the items.
    if (state.visible) activeSetChanged = true;
    _enqueue(list);
  }

  void submit() {
    submitCount++;
    if (submitCount > 1) return;
    // The first attempt shows every error: a new state tells each of
    // those fields' views, and nobody else.
    for (final MapEntry(key: path) in errored.entries) {
      final entry = entries[path]!;
      _put(path, entry.withState(entry.state.copyWith()), entry.state);
    }
  }

  void startSubmitting() {
    sentItems = Map.unmodifiable({
      for (final MapEntry(key: list) in lists.entries)
        list: entries[list]!.state.value as List<String>,
    });
    submitting = true;
    submitStartedAt = clock;
    formError = null;
    lastSubmit = null;
  }

  void completeSubmit(ServerErrors? answer) {
    submitting = false;
    if (answer == null || answer.isEmpty) {
      lastSubmit = SubmitOutcome.accepted;
      return;
    }
    lastSubmit = SubmitOutcome.rejected;
    formError = answer.form?.asServer();
    for (final MapEntry(key: sent, value: error) in answer.fields.entries) {
      final path = sent.isSerialized ? _atSend(sent) : sent;
      if (path == null) continue;
      final entry = entries[path];
      // No field to show it: the app handles unknown keys in its sender.
      if (entry == null) continue;
      if (entry.changedAt <= submitStartedAt) {
        entries = entries.put(
          path,
          _Entry(entry.state, entry.seq, entry.initial,
              serverError: error.asServer(), changedAt: entry.changedAt),
        );
        _enqueue(path);
      }
    }
  }

  /// [path], read by index, with the ids its lists had when the send
  /// started; `null` when an index had no item then.
  FieldPath? _atSend(FieldPath path) {
    FieldPath? at;
    for (final segment in path.segments) {
      switch (segment) {
        case KeySegment(:final key):
          at = at == null ? FieldPath(key) : at.child(key);
        case ItemSegment(:final id):
          at = at!.item(id);
        case IndexSegment(:final index):
          final ids = sentItems[at];
          if (ids == null || index >= ids.length) return null;
          at = at!.item(ids[index]);
      }
    }
    return at;
  }

  void abandonSubmit() {
    submitting = false;
    lastSubmit = SubmitOutcome.abandoned;
  }

  FormSnapshot finish() {
    _settle();
    final status = _status();
    if (changed.isEmpty &&
        identical(status, from.status) &&
        identical(data, from._data) &&
        identical(retired, from._retired) &&
        identical(undecodable, from._undecodable) &&
        identical(groups, from._groups) &&
        identical(items, from._items)) {
      return from;
    }
    return FormSnapshot._(
      entries: entries,
      order: order,
      nextSeq: nextSeq,
      data: data,
      retired: retired,
      undecodable: undecodable,
      graph: graph,
      changedPaths: Set.unmodifiable(changed),
      status: status,
      errored: errored,
      dirtyCount: dirtyCount,
      groups: groups,
      items: items,
      lists: lists,
      nextItemId: nextItemId,
      sentItems: sentItems,
      clock: clock,
      submitStartedAt: submitStartedAt,
      visible: activeSetChanged ? _VisibleList() : from._visible,
    );
  }

  /// Recomputes queued fields until nothing else changes. Conditions are
  /// acyclic, so this ends; a field is queued again only when something it
  /// reads changed.
  void _settle() {
    while (pending.isNotEmpty) {
      final path = pending.removeFirst();
      queued.remove(path);
      final entry = entries[path];
      if (entry == null) continue;
      final state = entry.state;
      final def = state.def;

      final owner = itemOf(path);
      final list = owner == null ? null : entries[owner.list]?.state;
      final visible = (list?.visible ?? true) && _isActive(def);
      final enabled = (list?.enabled ?? true) &&
          (def.enabledWhen?.evaluate(_valueAt) ?? true);
      final required =
          def.required || (def.requiredWhen?.evaluate(_valueAt) ?? false);
      // A local error wins: it describes the value on screen now.
      final error = visible && enabled
          ? validateField(def, state.value,
                  required: required, valueOf: _valueAt) ??
              (def is ListFieldDef
                  ? itemCountError(def, (state.value as List).length)
                  : null) ??
              entry.serverError
          : null;

      if (visible == state.visible &&
          enabled == state.enabled &&
          required == state.required &&
          error == state.error) {
        continue;
      }
      final next = state.copyWith(
        visible: visible,
        enabled: enabled,
        required: required,
        error: error,
        clearError: error == null,
      );
      _put(path, entry.withState(next), state);
      if (visible != state.visible) {
        for (final reader in graph.conditionDependents(path)) {
          _enqueue(reader);
        }
      }
      // A list's items follow its visibility and enablement.
      if (def is ListFieldDef &&
          (visible != state.visible || enabled != state.enabled)) {
        for (final id in next.value as List<String>) {
          for (final field in items[def.itemPath(id)] ?? const <FieldPath>[]) {
            _enqueue(field);
          }
        }
      }
    }
  }

  /// Whether [def]'s visibility passes and every field it reads is active.
  /// A path no field ever registered is user data, judged by value only.
  bool _isActive(FieldDef<Object?> def) {
    final condition = def.visibleWhen;
    if (condition == null) return true;
    for (final read in condition.reads) {
      final entry = entries[read];
      if (entry != null ? !entry.state.visible : retired.containsKey(read)) {
        return false;
      }
    }
    return condition.evaluate(_valueAt);
  }

  /// [json] decoded by [def]'s codec. A value it rejects becomes `null`
  /// and is listed in `undecodable` under [path].
  Object? _decode(FieldPath path, FieldDef<Object?> def, Object? json) {
    final (value, ok) = decodeFieldValue(def, json);
    undecodable = ok ? undecodable.remove(path) : undecodable.put(path, json);
    return value;
  }

  /// [value], decoded by [from], converted for [to]: encoded with the old
  /// codec and decoded with the new one when they differ (design doc 0007
  /// §2). A failure is listed under [path], unless [path] is `null`.
  Object? _recode(
    FieldPath? path,
    FieldDef<Object?> from,
    FieldDef<Object?> to,
    Object? value,
  ) {
    if (from.codec == to.codec) return value;
    if (value == null) {
      // A raw value the old codec rejected gets a second chance.
      if (path != null && undecodable.containsKey(path)) {
        return _decode(path, to, undecodable[path]);
      }
      return null;
    }
    Object? json;
    try {
      json = encodeFieldValue(from, value);
    } on Object {
      json = value;
    }
    final (decoded, ok) = decodeFieldValue(to, json);
    if (path != null) {
      undecodable = ok ? undecodable.remove(path) : undecodable.put(path, json);
    }
    return decoded;
  }

  Object? _valueAt(FieldPath path) {
    if (entries[path] case final entry?) return entry.state.value;
    if (retired[path] case final gone?) return gone.value;
    return data[path];
  }

  /// The status after this transition: the identical one when nothing in
  /// it changed.
  FormStatus _status() {
    final old = from.status;
    final next = FormStatus(
      errorCount: errored.length,
      formError: formError,
      submitCount: submitCount,
      submitting: submitting,
      lastSubmit: lastSubmit,
      validating: old.validating,
      dirty: dirtyCount > 0,
    );
    return next == old ? old : next;
  }

  /// Stores [entry], keeping the error set, dirty count and change
  /// tracking in step with the state it replaces ([old], `null` for a new
  /// field).
  void _put(FieldPath path, _Entry entry, FieldState? old) {
    entries = entries.put(path, entry);
    changed.add(path);
    final state = entry.state;
    if ((old?.error != null) != (state.error != null)) {
      errored =
          state.error != null ? errored.put(path, true) : errored.remove(path);
    }
    if ((old?.dirty ?? false) != state.dirty) {
      dirtyCount += state.dirty ? 1 : -1;
    }
    if ((old?.visible ?? false) != state.visible) activeSetChanged = true;
  }

  void _enqueue(FieldPath path) {
    if (queued.add(path)) pending.add(path);
  }

  /// Queues every field whose conditions or validators read [path].
  void _enqueueReaders(FieldPath path) {
    for (final reader in graph.conditionDependents(path)) {
      _enqueue(reader);
    }
    for (final reader in graph.validatorDependents(path)) {
      _enqueue(reader);
    }
  }
}

extension on ValidationError {
  /// This error, marked as the server's.
  ValidationError asServer() => source == ErrorSource.server
      ? this
      : ValidationError(code, params: params, source: ErrorSource.server);
}
