import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'dynamic_form_controller.dart';
import 'field_registry.dart';

typedef _CachedField = ({
  Object? value,
  String? error,
  bool enabled,
  Widget widget,
});

/// Presentational widget: takes a snapshot and a change callback.
///
/// Works with any state management (`BlocBuilder`, `Consumer`, ...). It does
/// not render a submit button: the call to action belongs to the screen.
///
/// Each field is rebuilt only when its own value, displayed error or
/// `enabled` flag changes. For every other field the view returns the same
/// widget instance, so Flutter skips the whole subtree.
class DynamicFormView extends StatefulWidget {
  /// Creates the view.
  const DynamicFormView({
    super.key,
    required this.engine,
    required this.snapshot,
    required this.onChanged,
    required this.registry,
    this.enabled = true,
    this.spacing = 16,
  });

  /// Engine that produced [snapshot].
  final FormEngine engine;

  /// State to render.
  final FormSnapshot snapshot;

  /// Called when a field reports a new value.
  final void Function(String key, Object? value) onChanged;

  /// Builders for each field type.
  final FieldRegistry registry;

  /// Whether fields accept input (e.g. `false` while submitting).
  final bool enabled;

  /// Vertical space after each field.
  final double spacing;

  @override
  State<DynamicFormView> createState() => _DynamicFormViewState();
}

class _DynamicFormViewState extends State<DynamicFormView> {
  final _cache = <String, _CachedField>{};
  final _callbacks = <String, ValueChanged<Object?>>{};

  @override
  void didUpdateWidget(DynamicFormView old) {
    super.didUpdateWidget(old);
    // What defines the *shape* of the fields changed: the cache is stale.
    if (old.engine != widget.engine ||
        old.registry != widget.registry ||
        old.spacing != widget.spacing) {
      _cache.clear();
    }
  }

  // Stable per field. Reads `widget` at call time, so a cached field always
  // reaches the latest onChanged.
  ValueChanged<Object?> _callbackFor(String key) =>
      _callbacks[key] ??= (v) => widget.onChanged(key, v);

  Widget _fieldFor(FieldConfig field) {
    final snapshot = widget.snapshot;
    final value = snapshot.values[field.key];
    final error = snapshot.errorFor(field.key);
    final enabled = widget.enabled;

    final cached = _cache[field.key];
    if (cached != null &&
        cached.value == value &&
        cached.error == error &&
        cached.enabled == enabled) {
      return cached.widget;
    }

    final ctx = FieldContext(
      value: value,
      errorText: error,
      enabled: enabled,
      onChanged: _callbackFor(field.key),
    );
    final built = Padding(
      key: ValueKey(field.key),
      padding: EdgeInsets.only(bottom: widget.spacing),
      // A Builder gives each field its own BuildContext, so an inherited
      // lookup (e.g. Theme.of) registers on the field rather than the view
      // and still triggers a rebuild while the widget is cached.
      child: Builder(
        builder: (context) => widget.registry.build(context, field, ctx),
      ),
    );
    _cache[field.key] =
        (value: value, error: error, enabled: enabled, widget: built);
    return built;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in widget.snapshot.visibleFields) _fieldFor(field),
        ],
      );
}

/// Shortcut for apps without external state management.
class DynamicForm extends StatelessWidget {
  /// Creates a form bound to [controller].
  const DynamicForm({
    super.key,
    required this.controller,
    required this.registry,
    this.enabled = true,
  });

  /// Holds the form state.
  final DynamicFormController controller;

  /// Builders for each field type.
  final FieldRegistry registry;

  /// Whether fields accept input.
  final bool enabled;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FormSnapshot>(
        valueListenable: controller,
        builder: (_, snapshot, __) => DynamicFormView(
          engine: controller.engine,
          snapshot: snapshot,
          onChanged: controller.change,
          registry: registry,
          enabled: enabled,
        ),
      );
}
