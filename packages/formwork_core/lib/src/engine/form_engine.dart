import 'dart:collection';

import 'deep_equality.dart';
import 'dependency_graph.dart';
import 'field_def.dart';
import 'field_path.dart';
import 'field_state.dart';
import 'form_status.dart';
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

  /// The definitions of the active fields, in registration order. The
  /// identical list is returned until an active field is shown, hidden,
  /// registered, unregistered or replaced.
  List<FieldDef<Object?>> get visibleFields => _visible.value ??=
      List.unmodifiable([for (final s in _activeStates()) s.def]);

  /// The values of the active fields as JSON, through each field's codec,
  /// keyed by path, in registration order. Disabled fields are included:
  /// they are read-only data.
  Map<String, Object?> payload() => {
        for (final s in _activeStates())
          s.def.path.toString(): encodeFieldValue(s.def, s.value),
      };

  /// Raw values that a registered field's codec could not decode, by path
  /// (decision 18 of design doc 0001). The field holds `null` instead. An
  /// entry leaves when its field gets a new value or is unregistered.
  Map<FieldPath, Object?> get undecodable =>
      Map.unmodifiable(Map.fromEntries(_undecodable.entries));

  /// The first field, in registration order, that shows an error: where a
  /// failed submit moves focus (design doc 0008 §4). `null` when none does.
  /// Costs the number of fields with an error, not the size of the form.
  FieldPath? get firstErrorPath {
    _Entry? first;
    for (final MapEntry(key: path) in _errored.entries) {
      final entry = _entries[path]!;
      final shown = entry.state.touched || status.submitAttempted;
      if (shown && (first == null || entry.seq < first.seq)) first = entry;
    }
    return first?.state.def.path;
  }

  Iterable<FieldState> _activeStates() sync* {
    for (var seq = 0; seq < _nextSeq; seq++) {
      final path = _order[seq];
      if (path == null) continue;
      final state = _entries[path]!.state;
      if (state.visible) yield state;
    }
  }
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
  /// no field registers.
  FormSnapshot initial({Map<String, Object?> initialValues = const {}}) =>
      FormSnapshot._(
        entries: const PersistentMap.empty(),
        order: const PersistentMap.empty(),
        nextSeq: 0,
        data: Map.unmodifiable({
          for (final e in initialValues.entries) FieldPath(e.key): e.value,
        }),
        retired: const PersistentMap.empty(),
        undecodable: const PersistentMap.empty(),
        graph: const DependencyGraph.empty(),
        changedPaths: const {},
        status: const FormStatus(),
        errored: const PersistentMap.empty(),
        dirtyCount: 0,
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
  /// each other, and an [ArgumentError] when two of [defs] share a key;
  /// nothing is registered then.
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
  /// recomputed. [value] is then of the field's type.
  ///
  /// A path no field registers is user data that conditions may read. Its
  /// [value] is JSON, as in `initialValues`, and a field that registers
  /// there later decodes it. A path whose field was unregistered keeps a
  /// value of that field's type, for when it comes back.
  ///
  /// Returns [s] when nothing changes.
  FormSnapshot change(FormSnapshot s, FieldPath path, Object? value) =>
      (_Transition(s)..change(path, value)).finish();

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

  void register(FieldDef<Object?> def) {
    final path = def.path;
    final old = entries[path];
    if (old != null && old.state.def == def) return;

    graph = graph.add(
      path,
      conditionReads: def.conditionReads,
      validatorReads: def.validatorReads,
    );

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
      return;
    }

    final gone = retired[path];
    final value = gone != null
        ? _recode(path, gone.def, def, gone.value)
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

  void unregister(FieldPath path) {
    final old = entries[path];
    if (old == null) return;
    entries = entries.remove(path);
    order = order.remove(old.seq);
    retired = retired.put(
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
    for (final MapEntry(key: path, value: error) in answer.fields.entries) {
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
        identical(undecodable, from._undecodable)) {
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

      final visible = _isActive(def);
      final enabled = def.enabledWhen?.evaluate(_valueAt) ?? true;
      final required =
          def.required || (def.requiredWhen?.evaluate(_valueAt) ?? false);
      // A local error wins: it describes the value on screen now.
      final error = visible && enabled
          ? validateField(def, state.value,
                  required: required, valueOf: _valueAt) ??
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
