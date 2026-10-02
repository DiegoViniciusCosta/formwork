import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'field_registry.dart';
import 'field_view.dart';
import 'form_controller.dart';
import 'form_focus.dart';

/// Gives the field views below it their controller, registry, localizer,
/// focus and view-level `enabled` flag (design docs 0006 §4 and 0008 §4).
///
/// A convenience only: every [FieldView] also takes these explicitly. It
/// carries stable references, never the snapshot, so a change to the form
/// does not rebuild what depends on it; changing one of them rebuilds
/// every field below, which is correct, since each field's props change.
///
/// In debug builds, after the first frame, it reports the visible fields
/// that no [FieldView] shows: they would still be validated, and block
/// submit with an error nobody can see.
class FormScope extends StatefulWidget {
  /// A scope for [child].
  const FormScope({
    super.key,
    this.controller,
    this.registry,
    this.localizer = englishErrorLocalizer,
    this.enabled = true,
    this.focus,
    required this.child,
  });

  /// The controller of the form below.
  final FormController? controller;

  /// The builders of the fields below.
  final FieldRegistry? registry;

  /// Turns errors into text.
  final ErrorLocalizer localizer;

  /// Whether the fields below accept input, for example `false` while
  /// submitting.
  final bool enabled;

  /// Where the fields below register their focus; the controller's when
  /// omitted.
  final FormFocus? focus;

  /// The widgets below.
  final Widget child;

  /// The nearest scope's data, registering [context] to rebuild when it
  /// changes; `null` when there is none.
  static FormScopeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InheritedFormScope>()?.data;

  @override
  State<FormScope> createState() => _FormScopeState();
}

/// What a [FormScope] gives the widgets below it.
@immutable
final class FormScopeData {
  /// The scope's data.
  const FormScopeData({
    required this.controller,
    required this.registry,
    required this.localizer,
    required this.enabled,
    required this.focus,
  });

  /// See [FormScope.controller].
  final FormController? controller;

  /// See [FormScope.registry].
  final FieldRegistry? registry;

  /// See [FormScope.localizer].
  final ErrorLocalizer localizer;

  /// See [FormScope.enabled].
  final bool enabled;

  /// See [FormScope.focus]; the controller's when the scope had none.
  final FormFocus? focus;

  @override
  bool operator ==(Object other) =>
      other is FormScopeData &&
      identical(other.controller, controller) &&
      identical(other.registry, registry) &&
      other.localizer == localizer &&
      other.enabled == enabled &&
      identical(other.focus, focus);

  @override
  int get hashCode => Object.hash(identityHashCode(controller),
      identityHashCode(registry), localizer, enabled, identityHashCode(focus));
}

class _FormScopeState extends State<FormScope> {
  @override
  void initState() {
    super.initState();
    assert(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = widget.controller;
        if (mounted && controller != null) {
          debugReportUnplacedFields(controller);
        }
      });
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) => _InheritedFormScope(
        data: FormScopeData(
          controller: widget.controller,
          registry: widget.registry,
          localizer: widget.localizer,
          enabled: widget.enabled,
          focus: widget.focus ?? widget.controller?.focus,
        ),
        child: widget.child,
      );
}

class _InheritedFormScope extends InheritedWidget {
  const _InheritedFormScope({required this.data, required super.child});

  final FormScopeData data;

  @override
  bool updateShouldNotify(_InheritedFormScope old) => old.data != data;
}
