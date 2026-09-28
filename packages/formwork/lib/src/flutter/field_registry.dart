import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'field_props.dart';

/// Builds the widget of one field.
typedef FieldBuilder = Widget Function(
  BuildContext context,
  FieldProps<Object?> props,
);

/// Builds the widget of a field defined by a [D] holding a [T], with both
/// typed (design doc 0006 §2).
typedef FieldDefBuilder<D extends FieldDef<T>, T> = Widget Function(
  BuildContext context,
  FieldProps<T> props,
  D def,
);

/// Maps fields to builders: by definition class for [registerDef], else
/// by [FieldDef.type].
///
/// The package ships no visual builders: register your design system's
/// components, or use a kit such as `formwork_material`.
class FieldRegistry {
  /// An empty registry.
  FieldRegistry();

  final Map<String, FieldBuilder> _byType = {};
  final Map<Type, FieldBuilder> _byDef = {};

  /// The field types with a builder, for a catalog's type registry.
  Set<String> get types => _byType.keys.toSet();

  /// Registers or replaces the builder for [type].
  void register(String type, FieldBuilder builder) => _byType[type] = builder;

  /// Registers or replaces several builders by type.
  void registerAll(Map<String, FieldBuilder> builders) =>
      _byType.addAll(builders);

  /// Registers or replaces the builder for definitions of class [D], which
  /// receives the props and the definition typed. It wins over a builder
  /// registered for the definition's [FieldDef.type]. It matches [D]
  /// exactly: a subclass of [D] needs its own registration.
  void registerDef<D extends FieldDef<T>, T>(FieldDefBuilder<D, T> builder) =>
      _byDef[D] = (context, props) {
        final def = props.def as D;
        return builder(
          context,
          FieldProps<T>(
            def: def,
            value: props.value as T?,
            error: props.error,
            errorText: props.errorText,
            enabled: props.enabled,
            required: props.required,
            validating: props.validating,
            onChanged: props.onChanged,
          ),
          def,
        );
      };

  /// Whether some builder renders [def].
  bool canBuild(FieldDef<Object?> def) =>
      _byDef.containsKey(def.runtimeType) || _byType.containsKey(def.type);

  /// Builds the field [props] describes. A field no builder renders is
  /// reported in debug builds and renders nothing.
  Widget build(BuildContext context, FieldProps<Object?> props) {
    final def = props.def;
    final builder = _byDef[def.runtimeType] ?? _byType[def.type];
    assert(builder != null, 'No builder for ${def.runtimeType} (${def.type})');
    return builder?.call(context, props) ?? const SizedBox.shrink();
  }
}
