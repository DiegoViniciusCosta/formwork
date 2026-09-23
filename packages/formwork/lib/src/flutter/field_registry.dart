import 'package:flutter/widgets.dart';

import '../core/field_config.dart';

/// What a field builder receives. Small on purpose: any component,
/// including design-system ones, can satisfy it.
class FieldContext {
  /// Creates a field context.
  const FieldContext({
    required this.value,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  /// Current value.
  final Object? value;

  /// Error to display, already resolved (touched / submit attempted).
  final String? errorText;

  /// Whether the field accepts input.
  final bool enabled;

  /// Reports a new value.
  final ValueChanged<Object?> onChanged;
}

/// Builds the widget for one field type.
typedef FieldBuilder = Widget Function(
  BuildContext context,
  FieldConfig field,
  FieldContext ctx,
);

/// Maps field types to builders.
///
/// The package ships no visual builders: register your design system's
/// components, or use a kit such as `formwork_material`.
class FieldRegistry {
  /// Creates an empty registry.
  FieldRegistry();

  final Map<String, FieldBuilder> _builders = {};

  /// Registered types. Pass to `FormConfig.fromMap(supportedTypes: ...)`.
  Set<String> get types => _builders.keys.toSet();

  /// Registers or replaces the builder for [type].
  void register(String type, FieldBuilder builder) => _builders[type] = builder;

  /// Registers or replaces several builders.
  void registerAll(Map<String, FieldBuilder> builders) =>
      _builders.addAll(builders);

  /// Builds [field]. Unknown types should be filtered out at parse time.
  Widget build(BuildContext context, FieldConfig field, FieldContext ctx) {
    final builder = _builders[field.type];
    assert(builder != null, 'No builder for type: ${field.type}');
    return builder?.call(context, field, ctx) ?? const SizedBox.shrink();
  }
}
