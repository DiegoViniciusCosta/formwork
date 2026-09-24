import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formwork/formwork.dart';

/// Holds a value the way an adapter would, and renders one bound TextField.
class _Harness<T> extends StatefulWidget {
  const _Harness({
    super.key,
    required this.initial,
    this.parse,
    this.applyChanges = true,
  });

  final T? initial;
  final T? Function(String text)? parse;

  /// When false, emitted values are recorded but never applied: an adapter
  /// that lags behind the user.
  final bool applyChanges;

  @override
  State<_Harness<T>> createState() => _HarnessState<T>();
}

class _HarnessState<T> extends State<_Harness<T>> {
  late T? value = widget.initial;
  String? error;
  final emitted = <T?>[];

  void setOutside(T? v) => setState(() => value = v);
  void setError(String? e) => setState(() => error = e);

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: TextControllerBinding<T>(
            value: value,
            parse: widget.parse,
            onChanged: (v) {
              emitted.add(v);
              if (widget.applyChanges) setState(() => value = v);
            },
            builder: (context, controller, onTextChanged) => TextField(
              controller: controller,
              onChanged: onTextChanged,
              decoration: InputDecoration(errorText: error),
            ),
          ),
        ),
      );
}

num? _parseNumber(String text) => num.tryParse(text.replaceAll(',', '.'));

TextEditingController _controller(WidgetTester t) =>
    t.widget<TextField>(find.byType(TextField)).controller!;

void main() {
  testWidgets('an outside value replaces the text, cursor at the end',
      (t) async {
    final key = GlobalKey<_HarnessState<String>>();
    await t.pumpWidget(_Harness<String>(key: key, initial: 'Ana'));
    expect(_controller(t).text, 'Ana');

    key.currentState!.setOutside('Bruno');
    await t.pump();

    expect(_controller(t).text, 'Bruno');
    expect(_controller(t).selection, const TextSelection.collapsed(offset: 5));
  });

  testWidgets('typing keeps text that means the value', (t) async {
    await t.pumpWidget(const _Harness<num>(initial: null, parse: _parseNumber));

    for (final typed in ['-', '1.50', '1,5']) {
      await t.enterText(find.byType(TextField), typed);
      await t.pump();
      expect(_controller(t).text, typed, reason: 'typed "$typed"');
    }
  });

  testWidgets('typing in the middle keeps the cursor where it is', (t) async {
    await t.pumpWidget(const _Harness<String>(initial: 'hello'));
    await t.showKeyboard(find.byType(TextField));

    t.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'helXlo',
      selection: TextSelection.collapsed(offset: 4),
    ));
    await t.pump();

    expect(_controller(t).text, 'helXlo');
    expect(_controller(t).selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('an error-only rebuild keeps selection and composition',
      (t) async {
    final key = GlobalKey<_HarnessState<String>>();
    await t.pumpWidget(_Harness<String>(key: key, initial: null));
    final untouched = _controller(t).value;

    key.currentState!.setError('This field is required');
    await t.pump();
    expect(_controller(t).value, untouched, reason: "'' and null");

    await t.showKeyboard(find.byType(TextField));
    t.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    ));
    await t.pump();
    key.currentState!.setError('Another error');
    await t.pump();

    expect(_controller(t).value.composing, const TextRange(start: 0, end: 3));
  });

  testWidgets('an outside value of the wrong type is not rewritten later',
      (t) async {
    final key = GlobalKey<_HarnessState<Object>>();
    await t.pumpWidget(
      _Harness<Object>(key: key, initial: null, parse: _parseNumber),
    );

    key.currentState!.setOutside('41'); // a string where a number belongs
    await t.pump();
    expect(_controller(t).text, '41');

    await t.showKeyboard(find.byType(TextField));
    // Kept by `text == format(value)` alone: parse('41') is 41, not '41'.
    const composing = TextEditingValue(
      text: '41',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 2),
    );
    t.testTextInput.updateEditingValue(composing);
    await t.pump();
    key.currentState!.setError('Must be at least 50');
    await t.pump();

    expect(_controller(t).value, composing);
  });

  testWidgets('replacing the text does not call onChanged', (t) async {
    final key = GlobalKey<_HarnessState<String>>();
    await t.pumpWidget(_Harness<String>(key: key, initial: 'Ana'));

    key.currentState!.setOutside('Bruno');
    await t.pump();

    expect(key.currentState!.emitted, isEmpty);
  });

  testWidgets('known limit: a reset that keeps the value keeps the text',
      (t) async {
    final key = GlobalKey<_HarnessState<num>>();
    await t.pumpWidget(
      _Harness<num>(key: key, initial: null, parse: _parseNumber),
    );
    await t.enterText(find.byType(TextField), '-'); // value stays null
    await t.pump();

    key.currentState!.setOutside(null);
    await t.pump();

    expect(_controller(t).text, '-');
  });

  testWidgets('known limit: a lagging adapter reverts typed text', (t) async {
    final key = GlobalKey<_HarnessState<String>>();
    await t.pumpWidget(
      _Harness<String>(key: key, initial: 'a', applyChanges: false),
    );
    await t.enterText(find.byType(TextField), 'ab'); // not applied yet
    await t.pump();

    key.currentState!.setOutside('a'); // the old value arrives late
    await t.pump();

    expect(_controller(t).text, 'a');
  });
}
