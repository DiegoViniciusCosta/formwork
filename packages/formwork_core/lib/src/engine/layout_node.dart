import 'field_def.dart';
import 'field_path.dart';

/// One place in a form's layout: a field, or a node holding others (design
/// doc 0006 §5). Layout is presentation only: it never touches the payload
/// or validation.
sealed class LayoutChild {
  const LayoutChild();
}

/// [child] as a layout child: a [FieldDef] or a [FieldPath] places that
/// field (or every field of a group, or a list and its items); a
/// [LayoutNode] is itself. Throws an [ArgumentError] for anything else.
LayoutChild _childOf(Object child) => switch (child) {
      final LayoutChild child => child,
      final FieldDef<Object?> def => LayoutField(def.path),
      final FieldPath path => LayoutField(path),
      _ => throw ArgumentError.value(
          child, 'children', 'A FieldDef, a FieldPath or a LayoutNode'),
    };

/// Places the field at [path] in a layout. A group's path places all its
/// fields, and a list's path the list and its item fields. A field placed
/// twice, such as `address` and then `address.zipCode`, renders at its
/// first place.
final class LayoutField extends LayoutChild {
  /// The place of the field at [path].
  const LayoutField(this.path);

  /// The field, group or list placed here.
  final FieldPath path;
}

/// A node of a layout: a [type] that picks its builder, the [children] it
/// arranges, and the other properties a catalog gives it, read as
/// `node['title']`.
///
/// The catalog defines `section` ([SectionNode]) and `row` ([RowNode]).
/// Any other type is custom: a layout builder registered for it renders
/// it, else its children render in a column. The root of a layout has the
/// type `root`.
class LayoutNode extends LayoutChild {
  /// A node of [type] arranging [children], with [props]. A child is a
  /// [FieldDef] or a [FieldPath], which places that field, or a node;
  /// anything else throws an [ArgumentError].
  LayoutNode(
    this.type, {
    List<Object> children = const [],
    Map<String, Object?> props = const {},
  })  : children = List.unmodifiable(children.map(_childOf)),
        _props = Map.unmodifiable(props);

  /// Picks the layout builder.
  final String type;

  /// What this node arranges, in order.
  final List<LayoutChild> children;

  final Map<String, Object?> _props;

  /// The property [key], such as a section's `title`, or `null`.
  Object? operator [](String key) => _props[key];
}

/// A section: children under an optional [title].
final class SectionNode extends LayoutNode {
  /// A section titled [title] holding [children].
  SectionNode({String? title, required List<Object> children})
      : super('section',
            children: children, props: {if (title != null) 'title': title});

  /// The section's title, if any.
  String? get title => this['title'] as String?;
}

/// A row: children side by side.
final class RowNode extends LayoutNode {
  /// A row of [children].
  RowNode({required List<Object> children}) : super('row', children: children);
}
