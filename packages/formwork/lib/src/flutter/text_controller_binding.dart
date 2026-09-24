import 'package:flutter/widgets.dart';

/// Builds a text input from the binding's stable controller and a callback
/// that parses the text and reports the value.
typedef TextBindingBuilder = Widget Function(
  BuildContext context,
  TextEditingController controller,
  ValueChanged<String> onTextChanged,
);

/// Binds a text input to a form value of type [T].
///
/// Use it in text field builders, including your own design-system ones.
/// It keeps one [TextEditingController] for the life of the field, so the
/// cursor survives rebuilds, and it keeps the text in step with [value]:
///
/// - while the text still means the value (`parse(text) == value`), or is
///   already how the value is shown (`text == format(value)`), the text,
///   cursor, selection and composition are left alone. This is the case
///   while the user types: `-`, `1.50` and `1,5` all stay as typed;
/// - otherwise the value came from outside (undo, reset, restored state)
///   and the text is replaced with `format(value)`, cursor at the end.
///   Replacing the text does not call [onChanged].
///
/// For this to hold, `parse(format(v)) == v` for every value the field can
/// hold, and the state must apply each change before the next one arrives:
/// a lagging adapter can revert typed text. Normalize values at submit
/// time, not in [onChanged]: a value that stops meaning its text gets its
/// text replaced while the user types. See design doc 0005.
class TextControllerBinding<T> extends StatefulWidget {
  /// Creates a binding for [value].
  const TextControllerBinding({
    super.key,
    required this.value,
    required this.onChanged,
    required this.builder,
    this.parse,
    this.format,
  });

  /// The current form value.
  final T? value;

  /// Called with the parsed value each time the user edits the text.
  final ValueChanged<T?> onChanged;

  /// Builds the input. Wire `controller` and `onTextChanged` to it.
  final TextBindingBuilder builder;

  /// Turns text into a value. Defaults to the text itself, which requires
  /// [T] to accept a `String`.
  final T? Function(String text)? parse;

  /// Turns a value into text. Defaults to `toString`, with `null` as `''`.
  final String Function(T? value)? format;

  @override
  State<TextControllerBinding<T>> createState() =>
      _TextControllerBindingState<T>();
}

class _TextControllerBindingState<T> extends State<TextControllerBinding<T>> {
  late final _controller = TextEditingController(text: _format(widget.value));

  T? _parse(String text) {
    final parse = widget.parse;
    return parse == null ? text as T? : parse(text);
  }

  String _format(T? value) {
    final format = widget.format;
    return format == null ? value?.toString() ?? '' : format(value);
  }

  void _onTextChanged(String text) => widget.onChanged(_parse(text));

  @override
  void didUpdateWidget(TextControllerBinding<T> old) {
    super.didUpdateWidget(old);
    final text = _controller.text;
    final value = widget.value;
    final formatted = _format(value);
    if (_parse(text) == value || text == formatted) return;

    // The value came from outside. Only the EditableText below listens to
    // this private controller, and it builds later in this same frame.
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _controller, _onTextChanged);
}
