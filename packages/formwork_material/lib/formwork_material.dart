/// Material Design field builders for formwork.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:formwork/formwork.dart';

/// Registry with Material builders for `text`, `email`, `password`,
/// `number`, `dropdown` and `checkbox`.
FieldRegistry materialFieldRegistry() =>
    FieldRegistry()..registerAll(materialFieldBuilders);

/// Material builders, to register individually or all at once.
final Map<String, FieldBuilder> materialFieldBuilders = {
  'text': (_, f, x) => _text(f, x),
  'email': (_, f, x) => _text(f, x, keyboard: TextInputType.emailAddress),
  'password': (_, f, x) => _text(f, x, obscure: true),
  'number': (_, f, x) => _text(
        f,
        x,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
        parse: (s) => num.tryParse(s.replaceAll(',', '.')),
      ),
  'dropdown': _dropdown,
  'checkbox': _checkbox,
};

Widget _text(
  FieldConfig f,
  FieldContext x, {
  TextInputType? keyboard,
  bool obscure = false,
  List<TextInputFormatter>? formatters,
  Object? Function(String raw)? parse,
}) =>
    TextControllerBinding<Object>(
      value: x.value,
      parse: parse,
      onChanged: x.onChanged,
      builder: (_, controller, onTextChanged) => TextField(
        controller: controller,
        enabled: x.enabled,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.hint,
          errorText: x.errorText,
        ),
        keyboardType: keyboard,
        obscureText: obscure,
        inputFormatters: formatters,
        onChanged: onTextChanged,
      ),
    );

Widget _dropdown(BuildContext _, FieldConfig f, FieldContext x) =>
    DropdownButtonFormField<Object>(
      initialValue: x.value,
      decoration: InputDecoration(labelText: f.label, errorText: x.errorText),
      items: [
        for (final o in f.options)
          DropdownMenuItem(value: o.value, child: Text(o.label)),
      ],
      onChanged: x.enabled ? x.onChanged : null,
    );

Widget _checkbox(BuildContext context, FieldConfig f, FieldContext x) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: x.value == true,
          title: Text(f.label),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: x.enabled ? x.onChanged : null,
        ),
        if (x.errorText != null)
          Text(
            x.errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
      ],
    );
