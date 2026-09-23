/// Typed models parsed from the configuration map.
///
/// Parsing happens once, at the edge. Everything downstream works with
/// these types, never with raw `Map<String, dynamic>`.
library;

Map<String, dynamic> _asMap(Object? o) => Map<String, dynamic>.from(o as Map);

/// One option of a choice field (e.g. `dropdown`).
class FieldOption {
  /// Creates an option.
  const FieldOption(this.value, this.label);

  /// Parses `{'value': ..., 'label': ...}`.
  factory FieldOption.fromMap(Map<String, dynamic> m) =>
      FieldOption(m['value'] as Object, m['label'] as String);

  /// Value stored in the form state when this option is selected.
  final Object value;

  /// Text shown to the user.
  final String label;
}

/// Simple visibility rule: `{'field': 'maritalStatus', 'equals': 'married'}`.
class VisibilityRule {
  /// Creates a rule.
  const VisibilityRule({required this.field, this.equals});

  /// Parses the rule map.
  factory VisibilityRule.fromMap(Map<String, dynamic> m) =>
      VisibilityRule(field: m['field'] as String, equals: m['equals']);

  /// Key of the field this rule depends on.
  final String field;

  /// Value that makes the dependent field visible.
  final Object? equals;

  /// Whether the dependent field is visible for [values].
  bool evaluate(Map<String, Object?> values) => values[field] == equals;
}

/// Configuration of a single field.
class FieldConfig {
  /// Creates a field configuration.
  const FieldConfig({
    required this.key,
    required this.type,
    required this.label,
    this.hint,
    this.required = false,
    this.initialValue,
    this.options = const [],
    this.validators = const [],
    this.visibleWhen,
    this.extra = const {},
  });

  /// Parses one entry of the `fields` list.
  factory FieldConfig.fromMap(Map<String, dynamic> m) => FieldConfig(
        key: m['key'] as String,
        type: m['type'] as String,
        label: m['label'] as String? ?? '',
        hint: m['hint'] as String?,
        required: m['required'] as bool? ?? false,
        initialValue: m['initialValue'],
        options: (m['options'] as List? ?? const [])
            .map((o) => FieldOption.fromMap(_asMap(o)))
            .toList(),
        validators: (m['validators'] as List? ?? const []).map(_asMap).toList(),
        visibleWhen: m['visibleWhen'] == null
            ? null
            : VisibilityRule.fromMap(_asMap(m['visibleWhen'])),
        extra: Map.fromEntries(
          m.entries.where((e) => !_known.contains(e.key)),
        ),
      );

  /// Unique identifier; also the key in the submitted payload.
  final String key;

  /// Field type, resolved by the `FieldRegistry`.
  final String type;

  /// Label shown to the user.
  final String label;

  /// Optional helper text.
  final String? hint;

  /// Whether an empty value is invalid.
  final bool required;

  /// Default value when no user data is provided.
  final Object? initialValue;

  /// Options for choice fields.
  final List<FieldOption> options;

  /// Validator specs, e.g. `{'type': 'minLength', 'value': 3}`.
  final List<Map<String, dynamic>> validators;

  /// Optional visibility rule.
  final VisibilityRule? visibleWhen;

  /// Unrecognized keys, available to custom field builders.
  final Map<String, dynamic> extra;

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
  };

  /// Whether this field's own rule passes for [values].
  ///
  /// The engine also hides the field when the field its rule reads is
  /// hidden, so a whole chain follows its root.
  bool isVisible(Map<String, Object?> values) =>
      visibleWhen?.evaluate(values) ?? true;
}

/// A parsed form catalog.
class FormConfig {
  /// Creates a form configuration.
  const FormConfig(this.fields, {this.schemaVersion = 1});

  /// Parses the configuration map.
  ///
  /// [supportedTypes] lists the field types the app can render (usually
  /// `registry.types`). Fields of other types are dropped and reported via
  /// [onUnsupported], which may throw to reject the whole form instead.
  factory FormConfig.fromMap(
    Map<String, dynamic> m, {
    Set<String>? supportedTypes,
    void Function(FieldConfig field)? onUnsupported,
  }) {
    final fields = <FieldConfig>[];
    final keys = <String>{};

    for (final raw in m['fields'] as List) {
      final f = FieldConfig.fromMap(_asMap(raw));
      if (supportedTypes != null && !supportedTypes.contains(f.type)) {
        onUnsupported?.call(f);
        continue;
      }
      if (!keys.add(f.key)) {
        throw ArgumentError('Duplicate field key: ${f.key}');
      }
      fields.add(f);
    }
    return FormConfig(fields, schemaVersion: m['schemaVersion'] as int? ?? 1);
  }

  /// Fields in catalog order.
  final List<FieldConfig> fields;

  /// Version of the catalog format.
  final int schemaVersion;
}
