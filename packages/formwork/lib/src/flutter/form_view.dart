import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'field_registry.dart';
import 'field_view.dart';
import 'form_controller.dart';
import 'form_focus.dart';
import 'form_scope.dart';

/// Renders every visible field of a [FormController] in a column, in
/// registration order: the zero-effort layout (design docs 0004 and 0006
/// §4). It renders no submit button: the call to action belongs to the
/// screen.
///
/// The column rebuilds only when a field is shown, hidden, registered or
/// unregistered, or a list's items are added, removed or moved; each field
/// rebuilds only when its own state changes. A list's item fields come
/// right after it, in item order.
class FormView extends StatefulWidget {
  /// A view of [controller]'s form.
  const FormView({
    super.key,
    required this.controller,
    required this.registry,
    this.localizer = englishErrorLocalizer,
    this.enabled = true,
    this.spacing = 16,
  });

  /// The form to render.
  final FormController controller;

  /// The field builders.
  final FieldRegistry registry;

  /// Turns errors into text.
  final ErrorLocalizer localizer;

  /// Whether the fields accept input, for example `false` while
  /// submitting.
  final bool enabled;

  /// The space after each field.
  final double spacing;

  @override
  State<FormView> createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  late List<FieldDef<Object?>> _visible = widget.controller.value.visibleFields;
  final _children = <FieldDef<Object?>, Widget>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSnapshot);
  }

  @override
  void didUpdateWidget(FormView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onSnapshot);
      widget.controller.addListener(_onSnapshot);
      _visible = widget.controller.value.visibleFields;
      _children.clear();
    }
    // The rest reaches the children through the FormScope: only the
    // padding is built into them.
    if (old.spacing != widget.spacing) _children.clear();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSnapshot);
    super.dispose();
  }

  // O(1) per change: the column rebuilds only for a new visible list.
  void _onSnapshot() {
    final visible = widget.controller.value.visibleFields;
    if (identical(visible, _visible)) return;
    setState(() {
      _visible = visible;
      // A field that left the column rebuilds anyway when it returns.
      _children.removeWhere((def, _) => !visible.contains(def));
    });
  }

  // The identical widget for a field that stays, so Flutter skips it.
  Widget _child(FieldDef<Object?> def) => _children[def] ??= Padding(
        key: ValueKey(def.path),
        padding: EdgeInsets.only(bottom: widget.spacing),
        child: FieldView(def),
      );

  @override
  Widget build(BuildContext context) => FormScope(
        controller: widget.controller,
        registry: widget.registry,
        localizer: widget.localizer,
        enabled: widget.enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [for (final def in _visible) _child(def)],
        ),
      );
}

/// Renders every visible field of a [snapshot] in a column, for state
/// management packages: takes the snapshot and a change callback, and
/// works with `BlocBuilder`, `Consumer` and the like (design doc 0004).
///
/// A field whose state is identical to the last build is not built again.
class SnapshotFormView extends StatefulWidget {
  /// A view of [snapshot].
  const SnapshotFormView({
    super.key,
    required this.snapshot,
    required this.onChanged,
    required this.registry,
    this.localizer = englishErrorLocalizer,
    this.enabled = true,
    this.focus,
    this.spacing = 16,
  });

  /// Where the fields register their focus nodes, to move focus to the
  /// first error with [FormFocus.requestFirstError].
  final FormFocus? focus;

  /// The state to render.
  final FormSnapshot snapshot;

  /// Called when a field reports a new value.
  final void Function(FieldPath path, Object? value) onChanged;

  /// The field builders.
  final FieldRegistry registry;

  /// Turns errors into text.
  final ErrorLocalizer localizer;

  /// Whether the fields accept input.
  final bool enabled;

  /// The space after each field.
  final double spacing;

  @override
  State<SnapshotFormView> createState() => _SnapshotFormViewState();
}

class _SnapshotFormViewState extends State<SnapshotFormView> {
  final _callbacks = <FieldPath, ValueChanged<Object?>>{};

  // Stable per field, and always reaches the latest onChanged.
  ValueChanged<Object?> _callbackFor(FieldPath path) =>
      _callbacks[path] ??= (value) => widget.onChanged(path, value);

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final def in snapshot.visibleFields)
          Padding(
            key: ValueKey(def.path),
            padding: EdgeInsets.only(bottom: widget.spacing),
            child: SnapshotFieldView(
              def,
              state: snapshot.stateOf(def)!,
              onChanged: _callbackFor(def.path),
              submitAttempted: snapshot.status.submitAttempted,
              registry: widget.registry,
              localizer: widget.localizer,
              enabled: widget.enabled,
              focus: widget.focus,
            ),
          ),
      ],
    );
  }
}
