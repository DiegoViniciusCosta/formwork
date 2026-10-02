import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'field_props.dart';
import 'field_registry.dart';
import 'form_controller.dart';
import 'form_focus.dart';
import 'form_scope.dart';

/// Builds a field's surroundings around [field], such as a `Card` or an
/// `Expanded`: only while the field is visible (design doc 0006 §4).
typedef FieldWrapper = Widget Function(BuildContext context, Widget field);

/// Renders one field of a [FormController] anywhere in a layout (design
/// docs 0006 §4 and 0007 §7).
///
/// It rebuilds only when its own field's state changes, whatever the size
/// of the form. A hidden field renders nothing, [wrap] included.
///
/// Every input can be passed here, or taken from the nearest [FormScope]:
/// [controller], [registry], [localizer], [enabled] and [focus].
class FieldView extends StatefulWidget {
  /// The view of [def]'s field.
  const FieldView(
    this.def, {
    super.key,
    this.controller,
    this.registry,
    this.localizer,
    this.enabled,
    this.focus,
    this.builder,
    this.wrap,
  });

  /// The field to render.
  final FieldDef<Object?> def;

  /// Where the field registers its focus node; from the [FormScope], or
  /// the controller's, when omitted.
  final FormFocus? focus;

  /// The form's controller; from the [FormScope] when omitted.
  final FormController? controller;

  /// The field builders; from the [FormScope] when omitted.
  final FieldRegistry? registry;

  /// Turns errors into text; from the [FormScope], or English, when
  /// omitted.
  final ErrorLocalizer? localizer;

  /// Whether the field accepts input, combined with its own rule; from the
  /// [FormScope], or `true`, when omitted.
  final bool? enabled;

  /// Builds this field instead of the registry, for this view only.
  final FieldBuilder? builder;

  /// The field's surroundings, built only while it is visible.
  final FieldWrapper? wrap;

  @override
  State<FieldView> createState() => _FieldViewState();
}

class _FieldViewState extends State<FieldView> {
  // Where this view is counted, for the debug placement checks.
  FormController? _trackedIn;
  FieldPath? _trackedPath;

  void _onChanged(Object? value) =>
      _controller(context).change(widget.def.path, value);

  FormController _controller(BuildContext context) {
    final controller =
        widget.controller ?? FormScope.maybeOf(context)?.controller;
    assert(controller != null,
        'FieldView(${widget.def.path}) needs a controller or a FormScope');
    return controller!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _track(_controller(context));
  }

  @override
  void didUpdateWidget(FieldView old) {
    super.didUpdateWidget(old);
    _track(_controller(context));
  }

  void _track(FormController controller) {
    assert(() {
      final path = widget.def.path;
      if (identical(controller, _trackedIn) && path == _trackedPath) {
        return true;
      }
      _untrack();
      _trackedIn = controller;
      _trackedPath = path;
      debugTrackPlacement(controller, path, 1);
      return true;
    }());
  }

  void _untrack() {
    final controller = _trackedIn;
    final path = _trackedPath;
    if (controller != null && path != null) {
      debugTrackPlacement(controller, path, -1);
    }
  }

  @override
  void dispose() {
    assert(() {
      _untrack();
      return true;
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = FormScope.maybeOf(context);
    final controller = _controller(context);
    final registry = widget.registry ?? scope?.registry;
    assert(registry != null || widget.builder != null,
        'FieldView(${widget.def.path}) needs a registry or a builder');
    return ValueListenableBuilder<FieldState?>(
      valueListenable: controller.fieldState(widget.def),
      builder: (context, state, _) {
        if (state == null) {
          _report('${widget.def.path} is not a field of this form');
          return const SizedBox.shrink();
        }
        return SnapshotFieldView(
          widget.def,
          state: state,
          onChanged: _onChanged,
          submitAttempted: controller.value.status.submitAttempted,
          registry: registry,
          localizer: widget.localizer ?? scope?.localizer,
          enabled: widget.enabled ?? scope?.enabled ?? true,
          focus: widget.focus ?? scope?.focus ?? controller.focus,
          builder: widget.builder,
          wrap: widget.wrap,
        );
      },
    );
  }
}

/// Renders one field from its state and a callback, for state management
/// packages (design doc 0006 §4): fed by `BlocSelector`, `select` or
/// equivalent.
///
/// It builds the field again only when [state] is a different instance,
/// or [enabled], [localizer], [registry], [builder] or [wrap] change:
/// the engine keeps an unchanged field's state identical (design doc 0001
/// §6), and gives new states to the fields whose error a submit shows.
class SnapshotFieldView extends StatefulWidget {
  /// The view of [def]'s field in [state].
  const SnapshotFieldView(
    this.def, {
    super.key,
    required this.state,
    required this.onChanged,
    this.submitAttempted = false,
    this.registry,
    this.localizer,
    this.enabled = true,
    this.focus,
    this.builder,
    this.wrap,
  });

  /// The field to render.
  final FieldDef<Object?> def;

  /// Where the field registers its focus node, for
  /// [FormFocus.requestFirstError].
  final FormFocus? focus;

  /// Its state in the current snapshot.
  final FieldState state;

  /// Reports a new value.
  final ValueChanged<Object?> onChanged;

  /// Whether a submit was attempted, which shows every error:
  /// `snapshot.status.submitAttempted`.
  final bool submitAttempted;

  /// The field builders, unless [builder] is given.
  final FieldRegistry? registry;

  /// Turns errors into text; English when omitted.
  final ErrorLocalizer? localizer;

  /// Whether the field accepts input, combined with its own rule.
  final bool enabled;

  /// Builds this field instead of the registry.
  final FieldBuilder? builder;

  /// The field's surroundings, built only while it is visible.
  final FieldWrapper? wrap;

  @override
  State<SnapshotFieldView> createState() => _SnapshotFieldViewState();
}

class _SnapshotFieldViewState extends State<SnapshotFieldView> {
  SnapshotFieldView? _builtFor;
  Widget? _built;

  /// Owned here, the same node for as long as the field is mounted, so it
  /// never invalidates the cached field (design doc 0008 §4).
  late final FocusNode _focusNode =
      FocusNode(debugLabel: widget.def.path.toString());

  @override
  void initState() {
    super.initState();
    if (widget.focus case final focus?) {
      registerFieldFocus(focus, widget.def.path, _focusNode, context);
    }
  }

  @override
  void didUpdateWidget(SnapshotFieldView old) {
    super.didUpdateWidget(old);
    if (!identical(old.focus, widget.focus) ||
        old.def.path != widget.def.path) {
      if (old.focus case final focus?) {
        unregisterFieldFocus(focus, old.def.path, _focusNode);
      }
      if (widget.focus case final focus?) {
        registerFieldFocus(focus, widget.def.path, _focusNode, context);
      }
    }
  }

  @override
  void dispose() {
    if (widget.focus case final focus?) {
      unregisterFieldFocus(focus, widget.def.path, _focusNode);
    }
    _focusNode.dispose();
    super.dispose();
  }

  // A tear-off of this State is stable, and reaches the latest callback.
  void _onChanged(Object? value) => widget.onChanged(value);

  bool _sameInputs(SnapshotFieldView a, SnapshotFieldView b) =>
      identical(a.state, b.state) &&
      a.enabled == b.enabled &&
      a.localizer == b.localizer &&
      identical(a.registry, b.registry) &&
      a.builder == b.builder &&
      a.wrap == b.wrap;

  @override
  Widget build(BuildContext context) {
    final built = _built;
    final builtFor = _builtFor;
    if (built != null && builtFor != null && _sameInputs(builtFor, widget)) {
      return built;
    }
    _builtFor = widget;
    return _built = _buildField();
  }

  Widget _buildField() {
    final state = widget.state;
    if (!state.visible) return const SizedBox.shrink();
    final error = state.error;
    final props = FieldProps<Object?>(
      def: state.def,
      value: state.value,
      error: error,
      errorText: error != null && (state.touched || widget.submitAttempted)
          ? localizeError(
              error, state.def, widget.localizer ?? englishErrorLocalizer)
          : null,
      enabled: widget.enabled && state.enabled,
      required: state.required,
      validating: state.validating,
      onChanged: _onChanged,
      focusNode: _focusNode,
    );
    final wrap = widget.wrap;
    // A Builder gives the field its own BuildContext, so an inherited
    // lookup in a builder (Theme.of) registers on the field, and still
    // rebuilds it while this view returns the cached widget.
    final field = Builder(
      builder: (context) =>
          widget.builder?.call(context, props) ??
          widget.registry!.build(context, props),
    );
    return wrap == null ? field : Builder(builder: (c) => wrap(c, field));
  }
}

void _report(String message) {
  assert(() {
    FlutterError.reportError(FlutterErrorDetails(
      exception: FlutterError(message),
      library: 'formwork',
    ));
    return true;
  }());
}

/// How many field views show each path, per controller, in debug builds.
final _placements = Expando<Map<FieldPath, int>>('formwork placements');

/// Counts a [FieldView] of [path] in or out of [controller]; reports a
/// field placed twice. Debug builds only.
void debugTrackPlacement(FormController controller, FieldPath path, int by) {
  final counts = _placements[controller] ??= {};
  final count = (counts[path] ?? 0) + by;
  counts[path] = count;
  if (by > 0 && count == 2) {
    // Animated switchers and kept-alive pages mount a field twice for a
    // moment, so this is reported, not thrown (design doc 0006 §4).
    _report('$path is shown by two FieldViews of the same form');
  }
}

/// Reports the visible fields of [controller] that no [FieldView] shows.
/// Debug builds only.
void debugReportUnplacedFields(FormController controller) {
  final counts = _placements[controller] ?? const {};
  for (final def in controller.value.visibleFields) {
    if ((counts[def.path] ?? 0) == 0) {
      _report('${def.path} is visible, but no FieldView shows it: it is '
          'still validated, and can block submit with a hidden error');
    }
  }
}
