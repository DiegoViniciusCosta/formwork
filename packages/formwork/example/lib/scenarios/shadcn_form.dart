import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../shared/scenario_page.dart';
import '../shared/signup.dart';

/// Field builders made of shadcn_ui components, a design system formwork
/// knows nothing about: each one maps [FieldProps] onto a component.
/// shadcn_ui's own `ShadForm` is not used; formwork owns the state.
FieldRegistry shadcnFieldRegistry() => FieldRegistry()
  ..registerAll({
    'text': (_, field) => _input(field),
    'email': (_, field) => _input(field, keyboard: TextInputType.emailAddress),
    'password': (_, field) => _input(field, obscure: true),
    'dropdown': (_, field) => _select(field),
    'checkbox': (_, field) => _checkbox(field),
  });

/// The label above the component and the error below it, the shadcn way.
Widget _decorated(FieldProps<Object?> field, Widget child,
        {bool label = true}) =>
    ShadInputDecorator(
      label: label ? _text(field.def.label) : null,
      error: _text(field.errorText),
      decoration: ShadDecoration(hasError: field.errorText != null),
      child: child,
    );

Widget? _text(String? text) => text == null ? null : Text(text);

Widget _input(
  FieldProps<Object?> field, {
  TextInputType? keyboard,
  bool obscure = false,
}) =>
    _decorated(
      field,
      TextControllerBinding<Object>(
        value: field.value,
        onChanged: field.onChanged,
        builder: (_, controller, onTextChanged) => ShadInput(
          controller: controller,
          focusNode: field.focusNode,
          enabled: field.enabled,
          placeholder: _text(field.def.hint),
          keyboardType: keyboard,
          obscureText: obscure,
          decoration: ShadDecoration(hasError: field.errorText != null),
          onChanged: onTextChanged,
        ),
      ),
    );

Widget _select(FieldProps<Object?> field) =>
    _decorated(field, _FollowingSelect(field));

/// A [ShadSelect] that shows the form's value, whoever set it.
///
/// `ShadSelect.initialValue` follows a new value but not a cleared one, so
/// a reset or an undo to null would leave the old option on screen. This
/// owns the select's controller and sets it on every change instead: a
/// trap to check in any design system's select.
class _FollowingSelect extends StatefulWidget {
  const _FollowingSelect(this.field);

  final FieldProps<Object?> field;

  @override
  State<_FollowingSelect> createState() => _FollowingSelectState();
}

class _FollowingSelectState extends State<_FollowingSelect> {
  late final controller =
      ShadSelectController<Object>(initialValue: _selection(widget.field));

  static Set<Object> _selection(FieldProps<Object?> field) =>
      {if (field.value case final Object value) value};

  @override
  void didUpdateWidget(_FollowingSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.value != oldWidget.field.value) {
      controller.value = _selection(widget.field);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final def = field.def;
    final options = def is ChoiceFieldDef<Object?>
        ? def.options
        : const <Option<Object?>>[];
    String labelOf(Object value) =>
        options.where((o) => o.value == value).firstOrNull?.label ?? '$value';
    return LayoutBuilder(
      builder: (context, constraints) => ShadSelect<Object>(
        controller: controller,
        focusNode: field.focusNode,
        enabled: field.enabled,
        minWidth: constraints.maxWidth,
        placeholder: Text(def.hint ?? 'Select…'),
        decoration: ShadDecoration(hasError: field.errorText != null),
        options: [
          // ShadSelect has no null value: an option for "none" would need
          // a placeholder value of its own.
          for (final option in options)
            if (option.value case final Object value)
              ShadOption(value: value, child: Text(option.label)),
        ],
        selectedOptionBuilder: (context, value) => Text(labelOf(value)),
        onChanged: field.onChanged,
      ),
    );
  }
}

Widget _checkbox(FieldProps<Object?> field) => _decorated(
      field,
      ShadCheckbox(
        value: field.value == true,
        focusNode: field.focusNode,
        enabled: field.enabled,
        label: _text(field.def.label),
        onChanged: field.onChanged,
      ),
      label: false,
    );

/// The shadcn_ui theme of the example, for a `ShadTheme` at the app's root.
ShadThemeData shadcnTheme() => ShadThemeData(
      colorScheme: const ShadZincColorScheme.light(),
      brightness: Brightness.light,
    );

/// Your design system: the sign-up form of the Cubit and Riverpod
/// scenarios, rendered with shadcn_ui. Only the registry differs from a
/// Material form. Needs a `ShadTheme` above it, as shadcn_ui apps have at
/// their root.
class ShadcnScenario extends StatefulWidget {
  const ShadcnScenario({super.key});

  @override
  State<ShadcnScenario> createState() => _ShadcnScenarioState();
}

class _ShadcnScenarioState extends State<ShadcnScenario> {
  final registry = shadcnFieldRegistry();
  final catalog = FormCatalog.fromJson(signupCatalogJson);
  late final controller = FormController(catalog);

  /// Sets values from outside the fields, as a restored draft would.
  void fillSample() {
    for (final (key, value) in [
      ('email', 'ada@example.com'),
      ('accountType', 'company'),
      ('companyName', 'Analytical Engines'),
      ('news', true),
    ]) {
      controller.change(FieldPath(key), value);
    }
  }

  void clear() {
    for (final def in catalog.fields) {
      controller.change(def.path, null);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'Your design system (shadcn_ui)',
        actions: [
          IconButton(
            tooltip: 'Fill sample',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: fillSample,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_all),
            onPressed: clear,
          ),
        ],
        whatToTry: const [
          'The sign-up form of the Cubit and Riverpod scenarios, with a '
              'FormController and shadcn_ui components: next to a '
              'Material form, only the field registry changes.',
          'Fill sample and Clear set the values from outside the '
              'fields: every component follows, the select included.',
          'Submit empty: the same error codes show in shadcn style.',
          'Submit with taken@example.com: after a second the server '
              'rejects it on the e-mail field, and the focus jumps there.',
        ],
        form: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormView(
              controller: controller,
              registry: registry,
              localizer: signupLocalizer,
            ),
            FormStatusBuilder(
              controller: controller,
              select: (s) => s,
              builder: (context, status) => SendStatusLine(status),
            ),
          ],
        ),
        bottomBar: FormStatusBuilder(
          controller: controller,
          select: (s) => s.submitting,
          builder: (context, submitting) => ShadButton(
            onPressed:
                submitting ? null : () => controller.submitTo(fakeSignup),
            child: Text(submitting ? 'Sending…' : 'Create account'),
          ),
        ),
      );
}
