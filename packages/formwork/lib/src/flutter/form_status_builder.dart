import 'package:flutter/widgets.dart';
import 'package:formwork_core/formwork_core.dart';

import 'form_controller.dart';
import 'form_scope.dart';

/// Rebuilds when the part of the form's status that [select] picks
/// changes, compared with `==` (design doc 0008 §3). Select several facts
/// at once with a record: `(s) => (s.submitAttempted, s.errorCount)`.
class FormStatusBuilder<R> extends StatefulWidget {
  /// A builder of [select]'s part of [controller]'s status.
  const FormStatusBuilder({
    super.key,
    this.controller,
    required this.select,
    required this.builder,
  });

  /// The form; from the [FormScope] when omitted.
  final FormController? controller;

  /// Picks what [builder] reads from the status.
  final R Function(FormStatus status) select;

  /// Builds from the selected value.
  final Widget Function(BuildContext context, R selected) builder;

  @override
  State<FormStatusBuilder<R>> createState() => _FormStatusBuilderState<R>();
}

class _FormStatusBuilderState<R> extends State<FormStatusBuilder<R>> {
  FormController? _controller;
  late R _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(FormStatusBuilder<R> old) {
    super.didUpdateWidget(old);
    _listen();
    _selected = widget.select(_controller!.status.value);
  }

  void _listen() {
    final controller =
        widget.controller ?? FormScope.maybeOf(context)?.controller;
    assert(controller != null,
        'FormStatusBuilder needs a controller or a FormScope');
    if (identical(controller, _controller)) return;
    _controller?.status.removeListener(_onStatus);
    _controller = controller!..status.addListener(_onStatus);
    _selected = widget.select(controller.status.value);
  }

  void _onStatus() {
    final selected = widget.select(_controller!.status.value);
    if (selected != _selected) setState(() => _selected = selected);
  }

  @override
  void dispose() {
    _controller?.status.removeListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _selected);
}
