import '../engine/condition.dart';
import '../engine/deep_equality.dart';
import '../engine/dependency_graph.dart';
import '../engine/field_def.dart';
import '../engine/field_defs.dart';
import '../engine/field_path.dart';
import '../engine/form_def.dart';
import 'condition_registry.dart';
import 'validator_registry.dart';

/// What a [CatalogIssue] is about.
enum CatalogIssueKind {
  /// A field of a type no factory builds; the field is skipped.
  unknownType,

  /// A validator of an unknown type, or one that does not accept the
  /// field's value type; the validator is skipped.
  unknownValidator,

  /// A condition with an unknown operator; the condition is dropped.
  unknownOperator,

  /// A condition operand that the codec of the field it reads rejects; the
  /// condition is dropped.
  undecodableOperand,

  /// An `initialValue` that the field's codec rejects; it is ignored.
  undecodableValue,

  /// A field whose conditions would close a cycle; the field is skipped.
  cycle,
}

/// Something the tolerance rule skipped while reading a catalog: the
/// catalog may come from a server newer than the app, so it is reported
/// instead of thrown (design docs 0001 §3 and 0007 §4).
final class CatalogIssue {
  /// An issue of [kind] at [path].
  const CatalogIssue(this.kind, this.path, [this.detail]);

  /// What was skipped.
  final CatalogIssueKind kind;

  /// The field it happened in.
  final FieldPath path;

  /// The unknown name, the rejected value, or the paths of a cycle.
  final Object? detail;

  @override
  bool operator ==(Object other) =>
      other is CatalogIssue &&
      other.kind == kind &&
      other.path == path &&
      deepEquals(other.detail, detail);

  @override
  int get hashCode => Object.hash(kind, path, deepHash(detail));

  @override
  String toString() => 'CatalogIssue(${kind.name}, $path'
      '${detail == null ? '' : ', $detail'})';
}

/// Builds a field definition from one entry of a catalog's `fields`.
typedef FieldTypeFactory = FieldDef<Object?> Function(FieldJson field);

/// The field factories of a catalog, by `"type"` (design doc 0006 §2).
///
/// Built-in types: `text`, with its variants `email` and `password`,
/// `number`, `checkbox` and `dropdown`. A custom
/// type registers a factory that builds its definition from a [FieldJson].
class FieldTypeRegistry {
  final Map<String, FieldTypeFactory> _custom = {};

  /// Registers or replaces a type, a built-in one included.
  void register(String type, FieldTypeFactory factory) =>
      _custom[type] = factory;

  FieldTypeFactory? _factory(String type) => _custom[type] ?? _builtIns[type];
}

/// One entry of a catalog's `fields`, with the parts every field shares
/// already read, for a [FieldTypeFactory].
final class FieldJson {
  FieldJson._(
    this.json,
    this._reader,
    this._specs, {
    required this.key,
    required this.visibleWhen,
    required this.enabledWhen,
    required this.requiredWhen,
    required this.initialValue,
  });

  /// The raw entry, read-only, for the keys specific to a type.
  final Map<String, Object?> json;

  final _Reader _reader;
  final List<Map<String, Object?>> _specs;
  final Map<Type, List<Validator<Object?>>> _validators = {};

  /// The field's key and payload key.
  final String key;

  /// The `label`, if any.
  String? get label => _text('label');

  /// The `hint`, if any.
  String? get hint => _text('hint');

  /// Whether `required` is true, or a `required` validator is listed.
  bool get required =>
      json['required'] == true ||
      _specs.any((spec) => spec['type'] == 'required');

  /// The decoded `visibleWhen`, or `null`.
  final Condition? visibleWhen;

  /// The decoded `enabledWhen`, or `null`.
  final Condition? enabledWhen;

  /// The decoded `requiredWhen`, or `null`.
  final Condition? requiredWhen;

  /// The `initialValue`, decoded by the field's codec; `null` when absent
  /// or when the codec rejects it (reported).
  final Object? initialValue;

  /// The `validators` for a field holding [T]. Unknown ones, and ones that
  /// do not accept every [T], are skipped and reported, once.
  List<Validator<T>> validators<T>() =>
      (_validators[T] ??= List<Validator<T>>.unmodifiable([
        for (final spec in _specs)
          if (spec['type'] != 'required')
            if (_reader.validator<T>(key, spec) case final validator?)
              validator,
      ])) as List<Validator<T>>;

  /// Message overrides by error code, from each validator's `message`.
  Map<String, String> get messages => {
        for (final spec in _specs)
          if (spec['message'] case final String message)
            spec['type']! as String: message,
      };

  /// The keys no built-in part reads, for custom builders.
  Map<String, Object?> get extra => {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      };

  String? _text(String name) => switch (json[name]) {
        null => null,
        final String text => text,
        final other => throw FormatException('"$name" must be text', other),
      };

  static const _known = {
    'key',
    'type',
    'label',
    'hint',
    'required',
    'initialValue',
    'options',
    'validators',
    'visibleWhen',
    'enabledWhen',
    'requiredWhen',
  };
}

/// A form read from a JSON catalog (design docs 0001 §3 and 0007 §1): a
/// [FormDef] like any other for the engine, which also lists what the
/// tolerance rule skipped in [issues].
final class FormCatalog extends FormDef {
  FormCatalog._(super.fields, this.issues, this.schemaVersion);

  /// Reads [json]: `{"schemaVersion": 1, "fields": [...]}`.
  ///
  /// Condition operands are decoded through the codec of the field they
  /// read, so `{"eq": ["maritalStatus", "married"]}` equals
  /// `maritalStatus.equals(MaritalStatus.married)` (design doc 0006 §3).
  /// Unknown types, validators and operators, values that do not decode,
  /// and fields that would close a cycle are skipped and listed in
  /// [issues]. A field skipped for a cycle reports only the cycle.
  ///
  /// Throws a [FormatException] when [json] is malformed, or when two
  /// fields share a key.
  factory FormCatalog.fromJson(
    Map<String, Object?> json, {
    FieldTypeRegistry? types,
    ValidatorRegistry? validators,
    ConditionRegistry? conditions,
  }) {
    final reader = _Reader(
      types ?? FieldTypeRegistry(),
      validators ?? ValidatorRegistry(),
      conditions ?? ConditionRegistry(),
    );
    return reader.read(json);
  }

  /// What the tolerance rule skipped, in catalog order.
  final List<CatalogIssue> issues;

  /// The version of the catalog format.
  final int schemaVersion;
}

/// [catalog] with only the fields in [keep], in order, keeping its issues
/// and schema version. Catalog-side; the package barrel does not export it.
FormCatalog narrowCatalog(FormCatalog catalog, Set<FieldPath> keep) =>
    FormCatalog._(
      [
        for (final def in catalog.fields)
          if (keep.contains(def.path)) def,
      ],
      catalog.issues,
      catalog.schemaVersion,
    );

/// One [FormCatalog.fromJson] call.
final class _Reader {
  _Reader(this.types, this.validators, this.conditions);

  final FieldTypeRegistry types;
  final ValidatorRegistry validators;
  final ConditionRegistry conditions;

  /// Where issues go; `null` while probing for codecs.
  List<CatalogIssue>? sink;

  /// Definitions built without conditions or initial values, only for
  /// their codecs, so conditions can decode operands whatever the order,
  /// and each field its own initial value.
  final probes = <FieldPath, FieldDef<Object?>>{};

  /// Paths of fields skipped for a cycle: operands on them are JSON, as on
  /// any path outside the form.
  final outside = <FieldPath>{};

  FormCatalog read(Map<String, Object?> json) {
    final entries = [
      for (final raw in _list(json['fields'], 'fields'))
        switch (raw) {
          final Map<Object?, Object?> map => _object(map),
          _ => throw FormatException('A field is an object', raw),
        },
    ];
    final schemaVersion = switch (json['schemaVersion']) {
      null => 1,
      final int version => version,
      final other => throw FormatException('Bad schemaVersion', other),
    };

    final early = <int, List<CatalogIssue>>{};
    final known = <int>[];
    final keys = <String>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final key = entry['key'];
      final type = entry['type'];
      if (key is! String || type is! String) {
        throw FormatException('A field needs a key and a type', entry);
      }
      if (!keys.add(key)) throw FormatException('Duplicate key "$key"', entry);
      final factory = types._factory(type);
      if (factory == null) {
        early[i] = [
          CatalogIssue(CatalogIssueKind.unknownType, FieldPath(key), type),
        ];
        continue;
      }
      known.add(i);
      probes[FieldPath(key)] = factory(_field(entry, probe: true));
    }

    var built = _build(entries, known);
    if (built.cycles.isNotEmpty) {
      // Operands on a skipped field's path must be read as JSON, so build
      // again. A condition may gain a read of a skipped path, which has no
      // edges of its own, so no new cycle can form.
      outside.addAll(built.cycles);
      built = _build(entries, known);
    }

    return FormCatalog._(
      built.fields,
      List.unmodifiable([
        for (var i = 0; i < entries.length; i++)
          ...?early[i] ?? built.issues[i],
      ]),
      schemaVersion,
    );
  }

  ({
    List<FieldDef<Object?>> fields,
    Map<int, List<CatalogIssue>> issues,
    Set<FieldPath> cycles,
  }) _build(List<Map<String, Object?>> entries, List<int> known) {
    var graph = const DependencyGraph.empty();
    final fields = <FieldDef<Object?>>[];
    final issues = <int, List<CatalogIssue>>{};
    final cycles = <FieldPath>{};
    for (final i in known) {
      final entry = entries[i];
      final own = sink = <CatalogIssue>[];
      final def = types._factory(entry['type']! as String)!(_field(entry));
      sink = null;
      try {
        graph = graph.add(def.path, conditionReads: def.conditionReads);
      } on CycleError catch (e) {
        cycles.add(def.path);
        issues[i] = [CatalogIssue(CatalogIssueKind.cycle, def.path, e.paths)];
        continue;
      }
      issues[i] = own;
      fields.add(def);
    }
    return (fields: fields, issues: issues, cycles: cycles);
  }

  FieldJson _field(Map<String, Object?> entry, {bool probe = false}) {
    final key = entry['key']! as String;
    final path = FieldPath(key);
    final specs = [
      for (final spec in _list(entry['validators'], 'validators'))
        switch (spec) {
          {'type': String _} => _object(spec),
          _ => throw FormatException('A validator has a "type"', spec),
        },
    ];
    Condition? condition(String name) =>
        probe ? null : _condition(path, entry[name]);
    return FieldJson._(
      entry,
      this,
      specs,
      key: key,
      visibleWhen: condition('visibleWhen'),
      enabledWhen: condition('enabledWhen'),
      requiredWhen: condition('requiredWhen'),
      initialValue: probe ? null : _initialValue(path, entry['initialValue']),
    );
  }

  Condition? _condition(FieldPath path, Object? json) {
    if (json == null) return null;
    return conditions.decode(
      json,
      unknown: (operator) => sink
          ?.add(CatalogIssue(CatalogIssueKind.unknownOperator, path, operator)),
      decodeOperand: (read, operand) {
        final def = outside.contains(read) ? null : probes[read];
        // A path outside the form is user data: compared as JSON.
        if (def == null) return operand;
        final (value, ok) = decodeFieldValue(def, operand);
        if (!ok) {
          sink?.add(
              CatalogIssue(CatalogIssueKind.undecodableOperand, path, operand));
          throw FormatException('Undecodable operand', operand);
        }
        return value;
      },
    );
  }

  Object? _initialValue(FieldPath path, Object? json) {
    final def = probes[path];
    if (def == null) return json;
    final (value, ok) = decodeFieldValue(def, json);
    if (!ok) {
      sink?.add(CatalogIssue(CatalogIssueKind.undecodableValue, path, json));
    }
    return value;
  }

  Validator<T>? validator<T>(String key, Map<String, Object?> spec) {
    final validator = validators.build<T>(spec);
    if (validator == null) {
      final type = spec['type']! as String;
      final detail = validators.knows(type) ? '$type does not accept $T' : type;
      sink?.add(CatalogIssue(
          CatalogIssueKind.unknownValidator, FieldPath(key), detail));
    }
    return validator;
  }
}

/// [map] as a read-only JSON object; throws when a key is not text.
Map<String, Object?> _object(Map<Object?, Object?> map) {
  for (final key in map.keys) {
    if (key is! String) throw FormatException('A key must be text', map);
  }
  return Map<String, Object?>.unmodifiable(map);
}

List<Object?> _list(Object? json, String name) => switch (json) {
      null => const [],
      final List<Object?> list => list,
      final other => throw FormatException('"$name" must be a list', other),
    };

final Map<String, FieldTypeFactory> _builtIns = {
  'text': _text,
  'email': _text,
  'password': _text,
  'number': (f) => NumberFieldDef(
        f.key,
        label: f.label,
        hint: f.hint,
        required: f.required,
        visibleWhen: f.visibleWhen,
        enabledWhen: f.enabledWhen,
        requiredWhen: f.requiredWhen,
        validators: f.validators<num>(),
        initialValue: f.initialValue as num?,
        extra: f.extra,
        messages: f.messages,
      ),
  'checkbox': (f) => BoolFieldDef(
        f.key,
        label: f.label,
        hint: f.hint,
        required: f.required,
        visibleWhen: f.visibleWhen,
        enabledWhen: f.enabledWhen,
        requiredWhen: f.requiredWhen,
        validators: f.validators<bool>(),
        initialValue: f.initialValue as bool?,
        extra: f.extra,
        messages: f.messages,
      ),
  'dropdown': (f) => ChoiceFieldDef<Object>(
        f.key,
        options: [
          for (final raw in _list(f.json['options'], 'options'))
            switch (raw) {
              {'value': final Object value, 'label': final String label} =>
                Option<Object>(value, label),
              _ => throw FormatException(
                  'An option is {"value": ..., "label": ...}', raw),
            },
        ],
        label: f.label,
        hint: f.hint,
        required: f.required,
        visibleWhen: f.visibleWhen,
        enabledWhen: f.enabledWhen,
        requiredWhen: f.requiredWhen,
        validators: f.validators<Object>(),
        initialValue: f.initialValue,
        extra: f.extra,
        messages: f.messages,
      ),
};

FieldDef<Object?> _text(FieldJson f) => TextFieldDef(
      f.key,
      type: f.json['type']! as String,
      label: f.label,
      hint: f.hint,
      required: f.required,
      visibleWhen: f.visibleWhen,
      enabledWhen: f.enabledWhen,
      requiredWhen: f.requiredWhen,
      validators: f.validators<String>(),
      initialValue: f.initialValue as String?,
      extra: f.extra,
      messages: f.messages,
    );
