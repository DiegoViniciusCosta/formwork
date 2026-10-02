import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'field_registry.dart';
import 'field_view.dart';
import 'form_controller.dart';
import 'form_focus.dart';
import 'form_scope.dart';
import 'layout_registry.dart';
import 'layout_tree.dart';

/// Renders every visible field of a [FormController] in a column, in
/// registration order: the zero-effort layout (design docs 0004 and 0006
/// §4). When the form has a layout (`controller.layout`), it renders that
/// tree instead, with [layouts] building its nodes (0006 §5). It renders
/// no submit button: the call to action belongs to the screen.
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
    this.layouts,
    this.localizer = englishErrorLocalizer,
    this.enabled = true,
    this.spacing = 16,
  });

  /// The form to render.
  final FormController controller;

  /// The layout node builders; without it, every node is a column.
  final LayoutRegistry? layouts;

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
  late var _tree = LayoutTree(_child);

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
      _tree = LayoutTree(_child);
    }
    // The rest reaches the children through the FormScope: only the
    // padding is built into them.
    if (old.spacing != widget.spacing) {
      _children.clear();
      _tree = LayoutTree(_child);
    }
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
        child: switch (widget.controller.layout) {
          final layout? => _tree.build(layout, _visible, widget.layouts),
          null => layoutColumn([for (final def in _visible) _child(def)]),
        },
      );
}

/// Renders every visible field of a [snapshot] in a column, for state
/// management packages: takes the snapshot and a change callback, and
/// works with `BlocBuilder`, `Consumer` and the like (design doc 0004).
///
/// A field whose state is identical to the last build is not built again.
/// With a [layout], it renders that tree, with [layouts] building its nodes
/// (design doc 0006 §5); typing rebuilds no node.
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
    this.layout,
    this.layouts,
    this.spacing = 16,
  });

  /// How to arrange the fields, such as the form's `layout`; `null`, the
  /// default, renders a column. Pass the same tree on every build: a new
  /// one builds every node again.
  final LayoutNode? layout;

  /// The layout node builders; without it, every node is a column.
  final LayoutRegistry? layouts;

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

  final _slots = <FieldDef<Object?>, Widget>{};
  late var _tree = LayoutTree(_slot);
  List<FieldDef<Object?>>? _slotsFor;

  // The identical widget for a field that stays: it reads its state from
  // the scope, so a layout node never rebuilds to pass it down.
  Widget _slot(FieldDef<Object?> def) => _slots[def] ??= Padding(
        key: ValueKey(def.path),
        padding: EdgeInsets.only(bottom: widget.spacing),
        child: _SnapshotSlot(def),
      );

  @override
  void didUpdateWidget(SnapshotFormView old) {
    super.didUpdateWidget(old);
    if (old.spacing != widget.spacing) {
      _slots.clear();
      _tree = LayoutTree(_slot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (widget.layout case final layout?) {
      final visible = snapshot.visibleFields;
      if (!identical(visible, _slotsFor)) {
        _slotsFor = visible;
        final kept = visible.toSet();
        _slots.removeWhere((def, _) => !kept.contains(def));
      }
      return _SnapshotScope(
        snapshot: snapshot,
        view: widget,
        callbackFor: _callbackFor,
        child: _tree.build(layout, visible, widget.layouts),
      );
    }
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

/// The snapshot and the view's inputs, for the fields of a laid-out
/// [SnapshotFormView]. A field depends on its own definition, and is told
/// only when its state, or an input of the view, changes.
class _SnapshotScope extends InheritedModel<FieldDef<Object?>> {
  const _SnapshotScope({
    required this.snapshot,
    required this.view,
    required this.callbackFor,
    required super.child,
  });

  final FormSnapshot snapshot;
  final SnapshotFormView view;
  final ValueChanged<Object?> Function(FieldPath path) callbackFor;

  bool _sameInputs(_SnapshotScope old) =>
      identical(old.view.registry, view.registry) &&
      identical(old.view.localizer, view.localizer) &&
      old.view.enabled == view.enabled &&
      identical(old.view.focus, view.focus) &&
      old.snapshot.status.submitAttempted == snapshot.status.submitAttempted;

  @override
  bool updateShouldNotify(_SnapshotScope old) =>
      !identical(old.snapshot, snapshot) || !_sameInputs(old);

  @override
  bool updateShouldNotifyDependent(
    _SnapshotScope old,
    Set<FieldDef<Object?>> dependencies,
  ) =>
      !_sameInputs(old) ||
      dependencies.any((def) =>
          !identical(old.snapshot.stateOf(def), snapshot.stateOf(def)));
}

/// One field of a laid-out [SnapshotFormView], fed by [_SnapshotScope].
class _SnapshotSlot extends StatelessWidget {
  const _SnapshotSlot(this.def);

  final FieldDef<Object?> def;

  @override
  Widget build(BuildContext context) {
    final scope =
        InheritedModel.inheritFrom<_SnapshotScope>(context, aspect: def)!;
    final state = scope.snapshot.stateOf(def);
    if (state == null) return const SizedBox.shrink();
    final view = scope.view;
    return SnapshotFieldView(
      def,
      state: state,
      onChanged: scope.callbackFor(def.path),
      submitAttempted: scope.snapshot.status.submitAttempted,
      registry: view.registry,
      localizer: view.localizer,
      enabled: view.enabled,
      focus: view.focus,
    );
  }
}
