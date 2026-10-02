import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'layout_registry.dart';

/// Places the visible fields into a layout tree (design doc 0006 §5), and
/// keeps each node's widget while what it holds stays the same: a
/// visibility flip rebuilds only the nodes around it, and typing none.
/// Internal to the views.
final class LayoutTree {
  /// A tree whose fields are built by [slot], which the caller caches.
  LayoutTree(this.slot);

  /// The widget of a field, the identical one while the field stays.
  final Widget Function(FieldDef<Object?> def) slot;

  var _nodes = Expando<(List<Object>, Widget)>();
  List<FieldDef<Object?>>? _lastVisible;
  LayoutNode? _lastRoot;
  LayoutRegistry? _lastRegistry;
  Widget? _last;

  /// The widget of [root] for the [visible] fields, built by [registry].
  Widget build(
    LayoutNode root,
    List<FieldDef<Object?>> visible,
    LayoutRegistry? registry,
  ) {
    if (identical(visible, _lastVisible) &&
        identical(root, _lastRoot) &&
        identical(registry, _lastRegistry)) {
      return _last!;
    }
    // A node's widget holds its builder: a new registry builds anew.
    if (!identical(registry, _lastRegistry)) _nodes = Expando();
    _lastVisible = visible;
    _lastRoot = root;
    _lastRegistry = registry;
    return _last =
        _Placement(this, visible, registry).node(root, isRoot: true)!;
  }
}

/// One placement of the visible fields into the tree.
final class _Placement {
  _Placement(this.tree, List<FieldDef<Object?>> visible, this.registry) {
    // A list's item fields follow it, and move with it.
    for (final def in visible) {
      final owner = units.lastOrNull;
      if (owner != null &&
          owner.first is ListFieldDef &&
          '${def.path}'.startsWith('${owner.first.path}[')) {
        owner.add(def);
      } else {
        units.add([def]);
      }
    }
  }

  final LayoutTree tree;
  final LayoutRegistry? registry;

  /// Each visible field outside a list item, with its item fields.
  final units = <List<FieldDef<Object?>>>[];
  final placed = <List<FieldDef<Object?>>>{};

  Widget? node(LayoutNode node, {bool isRoot = false}) {
    final children = <Widget>[];
    void place(List<FieldDef<Object?>> unit) {
      if (!placed.add(unit)) return;
      children.addAll(unit.map(tree.slot));
    }

    for (final child in node.children) {
      switch (child) {
        case LayoutField(:final path):
          final group = '$path.';
          for (final unit in units) {
            final at = unit.first.path;
            if (at == path || '$at'.startsWith(group)) place(unit);
          }
        case final LayoutNode inner:
          if (this.node(inner) case final widget?) children.add(widget);
      }
    }
    // A field the layout does not place is never lost.
    if (isRoot) units.forEach(place);
    if (children.isEmpty && !isRoot) return null;

    final cached = tree._nodes[node];
    if (cached != null && listEquals(cached.$1, children)) return cached.$2;
    final widget = _LayoutNodeView(
      node: node,
      registry: registry,
      children: children,
    );
    tree._nodes[node] = (children, widget);
    return widget;
  }
}

class _LayoutNodeView extends StatelessWidget {
  const _LayoutNodeView({
    required this.node,
    required this.registry,
    required this.children,
  });

  final LayoutNode node;
  final LayoutRegistry? registry;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      registry?.build(context, node, children) ?? layoutColumn(children);
}
