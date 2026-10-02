import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

/// Builds the widget of one layout node from its visible [children],
/// already built (design doc 0006 §5).
typedef LayoutNodeBuilder = Widget Function(
  BuildContext context,
  LayoutNode node,
  List<Widget> children,
);

/// Maps layout node types (`section`, `row`, or your own) to builders.
///
/// The package ships no visual builders: a node without one renders its
/// children in a column, and debug builds report its type, except for the
/// root. Register your design system's, or use a kit such as
/// `formwork_material`.
class LayoutRegistry {
  /// An empty registry.
  LayoutRegistry();

  final Map<String, LayoutNodeBuilder> _byType = {};
  final Expando<bool> _reported = Expando();

  /// Registers or replaces the builder for [type].
  void register(String type, LayoutNodeBuilder builder) =>
      _byType[type] = builder;

  /// Registers or replaces several builders by type.
  void registerAll(Map<String, LayoutNodeBuilder> builders) =>
      _byType.addAll(builders);

  /// Builds [node] from its [children].
  Widget build(BuildContext context, LayoutNode node, List<Widget> children) {
    if (_byType[node.type] case final builder?) {
      return builder(context, node, children);
    }
    assert(() {
      if (node.type != 'root' && _reported[node] == null) {
        _reported[node] = true;
        FlutterError.reportError(FlutterErrorDetails(
          exception: FlutterError('No layout builder for "${node.type}": '
              'its children render in a column'),
          library: 'formwork',
        ));
      }
      return true;
    }());
    return layoutColumn(children);
  }
}

/// [children] in a column, stretched: how a node renders without a
/// builder.
Widget layoutColumn(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
