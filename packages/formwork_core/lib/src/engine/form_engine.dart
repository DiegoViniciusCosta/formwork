import 'dart:collection';

import 'field_config.dart';
import 'validators.dart';

/// Immutable form state. Framework-agnostic: store it wherever you like
/// (a Cubit, a Riverpod Notifier, a ValueNotifier...).
class FormSnapshot {
  const FormSnapshot._({
    required this.values,
    required this.errors,
    required this.visibleFields,
    this.touched = const {},
    this.submitAttempted = false,
  });

  /// All known values, including user data that is not part of the form.
  final Map<String, Object?> values;

  /// Current errors of every visible field.
  final Map<String, String> errors;

  /// Visible fields in catalog order, computed by the engine so views don't
  /// recompute them on every build.
  final List<FieldConfig> visibleFields;

  /// Keys of fields the user has interacted with. Read-only.
  final Set<String> touched;

  /// Whether a submit was attempted.
  final bool submitAttempted;

  /// Whether every visible field is valid.
  bool get isValid => errors.isEmpty;

  /// Error to display for [key]: only after the user touched the field or
  /// attempted to submit.
  String? errorFor(String key) =>
      submitAttempted || touched.contains(key) ? errors[key] : null;

  FormSnapshot _copyWith({
    Map<String, Object?>? values,
    Map<String, String>? errors,
    List<FieldConfig>? visibleFields,
    Set<String>? touched,
    bool? submitAttempted,
  }) =>
      FormSnapshot._(
        values: values ?? this.values,
        errors: errors ?? this.errors,
        visibleFields: visibleFields ?? this.visibleFields,
        touched: touched ?? this.touched,
        submitAttempted: submitAttempted ?? this.submitAttempted,
      );
}

/// Result of [FormEngine.submit]: the next snapshot and, if valid, the
/// payload to send.
typedef SubmitResult = ({FormSnapshot snapshot, Map<String, Object?>? payload});

/// Pure form rules: takes a snapshot, returns a new one. Holds no state.
class FormEngine {
  /// Creates an engine for [config].
  FormEngine({required FormConfig config, ValidatorRegistry? validators})
      : this._(config, validators, _buildChains(config));

  FormEngine._(
    this.config,
    ValidatorRegistry? validators,
    Map<String, List<FieldConfig>> chains,
  )   : _validators =
            _buildValidators(config, validators ?? ValidatorRegistry()),
        _byKey = {for (final f in config.fields) f.key: f},
        _chains = chains,
        _dependents = _buildDependents(chains);

  /// The form being edited.
  final FormConfig config;

  final Map<String, FieldValidator?> _validators;
  final Map<String, FieldConfig> _byKey;

  /// Field key -> the field followed by every field its visibility goes
  /// through (its controller, the controller's controller...).
  final Map<String, List<FieldConfig>> _chains;

  /// Key -> fields whose visibility reads it, directly or through a chain.
  final Map<String, List<FieldConfig>> _dependents;

  /// Initial snapshot.
  ///
  /// [initialData] is what is already known about the user. It feeds
  /// visibility rules and prefills fields, but only fields of [config] end
  /// up in the payload.
  FormSnapshot initial([Map<String, Object?> initialData = const {}]) {
    final values = UnmodifiableMapView<String, Object?>({
      ...initialData,
      for (final f in config.fields)
        f.key: initialData[f.key] ?? f.initialValue,
    });
    final visible = _computeVisible(values);
    return FormSnapshot._(
      values: values,
      visibleFields: visible,
      errors: UnmodifiableMapView({
        for (final f in visible)
          if (_validate(f, values) case final String error) f.key: error,
      }),
    );
  }

  /// Applies a change incrementally: only the changed field and its
  /// dependents are revalidated, and the visible list is recomputed only
  /// when some dependent's visibility actually flipped. When no error
  /// changed, the new snapshot shares the previous `errors` map.
  FormSnapshot change(FormSnapshot s, String key, Object? value) {
    // Copied once and wrapped, not copied again: nothing else can reach the
    // new map, so the view keeps the snapshot immutable.
    final values =
        UnmodifiableMapView<String, Object?>({...s.values, key: value});

    final dependents = _dependents[key] ?? const <FieldConfig>[];
    final visibilityChanged =
        dependents.any((d) => _isVisible(d, s.values) != _isVisible(d, values));
    final visible =
        visibilityChanged ? _computeVisible(values) : s.visibleFields;

    final recomputed = <String, String?>{
      for (final f in [
        if (_byKey[key] case final changed?) changed,
        ...dependents,
      ])
        f.key: _isVisible(f, values) ? _validate(f, values) : null,
    };
    final errorsChanged =
        recomputed.entries.any((e) => s.errors[e.key] != e.value);

    return s._copyWith(
      values: values,
      visibleFields: visible,
      errors: errorsChanged ? _withErrors(s.errors, recomputed) : s.errors,
      touched: s.touched.contains(key)
          ? s.touched
          : UnmodifiableSetView({...s.touched, key}),
    );
  }

  /// Marks the attempt (so every error becomes visible) and returns the
  /// payload when valid. Sending it asynchronously is up to the caller.
  SubmitResult submit(FormSnapshot s) {
    final next = s._copyWith(submitAttempted: true);
    return (snapshot: next, payload: next.isValid ? payloadOf(next) : null);
  }

  /// Visible fields of [s].
  List<FieldConfig> visibleFields(FormSnapshot s) => s.visibleFields;

  /// Values of the visible form fields only, ready for a PATCH.
  Map<String, Object?> payloadOf(FormSnapshot s) => {
        for (final f in s.visibleFields) f.key: s.values[f.key],
      };

  /// [errors] with [recomputed] applied: `null` removes a field's error.
  static Map<String, String> _withErrors(
    Map<String, String> errors,
    Map<String, String?> recomputed,
  ) {
    final next = {...errors};
    for (final MapEntry(:key, :value) in recomputed.entries) {
      value == null ? next.remove(key) : next[key] = value;
    }
    return UnmodifiableMapView(next);
  }

  String? _validate(FieldConfig f, Map<String, Object?> values) =>
      _validators[f.key]?.call(values[f.key]);

  List<FieldConfig> _computeVisible(Map<String, Object?> values) =>
      List.unmodifiable(config.fields.where((f) => _isVisible(f, values)));

  static Map<String, FieldValidator?> _buildValidators(
    FormConfig config,
    ValidatorRegistry registry,
  ) =>
      {for (final f in config.fields) f.key: registry.buildFor(f)};

  /// A field is visible when its own rule passes and so does every rule up
  /// its chain: a field hidden by its controller hides its dependents too.
  /// A controller outside this form is judged by its value only.
  bool _isVisible(FieldConfig f, Map<String, Object?> values) =>
      _chains[f.key]!.every((link) => link.isVisible(values));

  static Map<String, List<FieldConfig>> _buildChains(FormConfig config) {
    final byKey = {for (final f in config.fields) f.key: f};
    List<FieldConfig> chainOf(FieldConfig f) {
      final chain = <FieldConfig>[];
      final seen = <String>{};
      // `seen` stops a cycle (A reads B, B reads A) from looping forever.
      for (FieldConfig? link = f;
          link != null && seen.add(link.key);
          link = byKey[link.visibleWhen?.field]) {
        chain.add(link);
      }
      return chain;
    }

    return {for (final f in config.fields) f.key: chainOf(f)};
  }

  static Map<String, List<FieldConfig>> _buildDependents(
    Map<String, List<FieldConfig>> chains,
  ) {
    // Sets keep catalog order and drop the repeats a cycle produces.
    final map = <String, Set<FieldConfig>>{};
    for (final chain in chains.values) {
      for (final link in chain) {
        final controller = link.visibleWhen?.field;
        if (controller != null) (map[controller] ??= {}).add(chain.first);
      }
    }
    return {for (final e in map.entries) e.key: e.value.toList()};
  }
}
