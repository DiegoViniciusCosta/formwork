import 'package:flutter/widgets.dart';

/// Keeps a [TextEditingController] stable across rebuilds.
///
/// Use it in text field builders, including your own design-system ones:
/// recreating the controller on every state change breaks the cursor and
/// selection.
class TextControllerBinding extends StatefulWidget {
  /// Creates a binding seeded with [initialText].
  const TextControllerBinding({
    super.key,
    required this.initialText,
    required this.builder,
  });

  /// Text used to create the controller. Later changes are ignored.
  final String initialText;

  /// Builds the text field with the stable controller.
  final Widget Function(BuildContext context, TextEditingController controller)
      builder;

  @override
  State<TextControllerBinding> createState() => _TextControllerBindingState();
}

class _TextControllerBindingState extends State<TextControllerBinding> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
