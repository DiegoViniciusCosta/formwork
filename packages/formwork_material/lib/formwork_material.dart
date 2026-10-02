/// Material Design field builders for formwork.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:formwork/formwork.dart';

/// A registry with Material builders for the text types `text`, `email`
/// and `password`, and for `number`, `dropdown` and `checkbox`.
FieldRegistry materialFieldRegistry() =>
    FieldRegistry()..registerAll(materialFieldBuilders);

/// The Material builders by field type, to register one by one or all at
/// once.
final Map<String, FieldBuilder> materialFieldBuilders = {
  'text': (_, field) => _text(field),
  'email': (_, field) => _text(field, keyboard: TextInputType.emailAddress),
  'password': (_, field) => _text(field, obscure: true),
  'number': (_, field) => _text(
        field,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
        parse: (text) => num.tryParse(text.replaceAll(',', '.')),
      ),
  'dropdown': _dropdown,
  'checkbox': _checkbox,
};

Widget _text(
  FieldProps<Object?> field, {
  TextInputType? keyboard,
  bool obscure = false,
  List<TextInputFormatter>? formatters,
  Object? Function(String text)? parse,
}) =>
    TextControllerBinding<Object>(
      value: field.value,
      parse: parse,
      onChanged: field.onChanged,
      builder: (_, controller, onTextChanged) => TextField(
        controller: controller,
        focusNode: field.focusNode,
        enabled: field.enabled,
        decoration: InputDecoration(
          labelText: field.def.label,
          hintText: field.def.hint,
          errorText: field.errorText,
        ),
        keyboardType: keyboard,
        obscureText: obscure,
        inputFormatters: formatters,
        onChanged: onTextChanged,
      ),
    );

Widget _dropdown(BuildContext _, FieldProps<Object?> field) {
  final def = field.def;
  final options =
      def is ChoiceFieldDef<Object?> ? def.options : const <Option<Object?>>[];
  return DropdownButtonFormField<Object?>(
    initialValue: field.value,
    focusNode: field.focusNode,
    decoration: InputDecoration(
      labelText: def.label,
      hintText: def.hint,
      errorText: field.errorText,
    ),
    items: [
      for (final option in options)
        DropdownMenuItem(value: option.value, child: Text(option.label)),
    ],
    onChanged: field.enabled ? field.onChanged : null,
  );
}

Widget _checkbox(BuildContext context, FieldProps<Object?> field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: field.value == true,
          focusNode: field.focusNode,
          title: Text(field.def.label ?? ''),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: field.enabled ? field.onChanged : null,
        ),
        if (field.errorText case final error?)
          Text(
            error,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
      ],
    );
