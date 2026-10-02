import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

/// Knows the focus node of each mounted field, and moves focus to the
/// first field with an error (design doc 0008 §4).
///
/// Field views register and unregister their nodes on their own, which
/// rebuilds nothing; there is no public way to do it. A `FormController`
/// owns one; with a state management package, create one and pass it to
/// `SnapshotFormView` or `FormScope`.
class FormFocus {
  final Map<FieldPath, ({FocusNode node, BuildContext context})> _fields = {};

  /// Focuses the first mounted field, in registration order, that shows an
  /// error in [snapshot], scrolling to it first unless [scroll] is false.
  /// A text input scrolls itself into view when it gets focus, whatever
  /// [scroll] says.
  ///
  /// Returns whether focus moved. A form error alone moves nothing: there
  /// is no field to focus. When the fields in error are all unmounted,
  /// debug builds report their paths.
  bool requestFirstError(FormSnapshot snapshot, {bool scroll = true}) {
    final first = snapshot.firstErrorPath;
    if (first == null) return false;
    final target = _fields[first] ?? _firstMounted(snapshot);
    if (target == null) {
      assert(() {
        FlutterError.reportError(FlutterErrorDetails(
          exception: FlutterError('No field with an error is mounted: '
              '${_errorPaths(snapshot).join(', ')}'),
          library: 'formwork',
        ));
        return true;
      }());
      return false;
    }
    if (scroll && target.context.mounted) {
      Scrollable.ensureVisible(target.context,
          duration: const Duration(milliseconds: 200));
    }
    target.node.requestFocus();
    return true;
  }

  /// The visible fields that show an error, in registration order.
  static Iterable<FieldPath> _errorPaths(FormSnapshot snapshot) => [
        for (final def in snapshot.visibleFields)
          if (_showsError(snapshot, def)) def.path,
      ];

  static bool _showsError(FormSnapshot snapshot, FieldDef<Object?> def) {
    final state = snapshot.stateOf(def)!;
    return state.error != null &&
        (state.touched || snapshot.status.submitAttempted);
  }

  /// The first mounted field that shows an error, walking the visible
  /// fields: only when the very first one is not mounted.
  ({FocusNode node, BuildContext context})? _firstMounted(
      FormSnapshot snapshot) {
    for (final def in snapshot.visibleFields) {
      if (_showsError(snapshot, def)) {
        if (_fields[def.path] case final target?) return target;
      }
    }
    return null;
  }
}

/// Records the [node] of the field at [path] in [focus], shown at
/// [context]. Called by the field views; not exported.
void registerFieldFocus(FormFocus focus, FieldPath path, FocusNode node,
        BuildContext context) =>
    focus._fields[path] = (node: node, context: context);

/// Forgets the field at [path] in [focus], if [node] is still the one
/// recorded. Called by the field views; not exported.
void unregisterFieldFocus(FormFocus focus, FieldPath path, FocusNode node) {
  if (identical(focus._fields[path]?.node, node)) focus._fields.remove(path);
}
