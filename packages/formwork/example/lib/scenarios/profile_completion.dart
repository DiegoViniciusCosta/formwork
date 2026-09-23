import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

/// Every field the app may ever ask for. Usually decoded from JSON sent by
/// a server or remote config.
const _catalogJson = <String, dynamic>{
  'schemaVersion': 1,
  'fields': [
    {
      'key': 'fullName',
      'type': 'text',
      'label': 'Full name',
      'required': true,
      'validators': [
        {'type': 'minLength', 'value': 3},
      ],
    },
    {
      'key': 'email',
      'type': 'email',
      'label': 'Email',
      'required': true,
      'validators': [
        {'type': 'email'},
      ],
    },
    {
      'key': 'taxId',
      'type': 'text',
      'label': 'Tax ID',
      'required': true,
      'validators': [
        {'type': 'digits', 'value': 11},
      ],
    },
    {
      'key': 'monthlyIncome',
      'type': 'number',
      'label': 'Monthly income',
      'required': true,
      'validators': [
        {'type': 'min', 'value': 1000},
      ],
    },
    {
      'key': 'maritalStatus',
      'type': 'dropdown',
      'label': 'Marital status',
      'required': true,
      'options': [
        {'value': 'single', 'label': 'Single'},
        {'value': 'married', 'label': 'Married'},
      ],
    },
    {
      'key': 'spouseName',
      'type': 'text',
      'label': 'Spouse name',
      'required': true,
      'visibleWhen': {'field': 'maritalStatus', 'equals': 'married'},
    },
    {
      'key': 'nickname',
      'type': 'text',
      'label': 'Nickname (optional)',
    },
    {
      'key': 'acceptedTerms',
      'type': 'checkbox',
      'label': 'I accept the terms',
      'required': true,
    },
  ],
};

/// What the backend already knows, for a few kinds of user.
const _presets = <String, Map<String, Object?>>{
  'New user': {},
  'Married, no income': {
    'fullName': 'Maria Silva',
    'email': 'maria@example.com',
    'taxId': '12345678909',
    'maritalStatus': 'married',
    'acceptedTerms': false,
  },
  'Single, no income': {
    'fullName': 'João Souza',
    'email': 'joao@example.com',
    'taxId': '98765432100',
    'maritalStatus': 'single',
    'acceptedTerms': true,
  },
  'Invalid stored data': {
    'fullName': 'Al',
    'email': 'not-an-email',
    'taxId': '123',
    'monthlyIncome': 500,
    'maritalStatus': 'single',
    'acceptedTerms': true,
  },
  'Complete': {
    'fullName': 'Ana Lima',
    'email': 'ana@example.com',
    'taxId': '11122233344',
    'monthlyIncome': 5000,
    'maritalStatus': 'single',
    'acceptedTerms': true,
  },
};

// Validators return display text in the current 0.1 API. Design doc 0001
// replaces this with error data (code plus params) and a localizer.
ValidatorRegistry _validators() => ValidatorRegistry()
  ..register('digits', (spec) {
    final length = spec['value'] as int;
    return (v) => RegExp('^\\d{$length}\$').hasMatch(v.toString())
        ? null
        : spec['message'] as String? ?? 'Must have $length digits';
  });

/// Progressive profiling: the same catalog, narrowed by `missingFields` to
/// what each user still has to answer.
class ProfileCompletionScenario extends StatefulWidget {
  const ProfileCompletionScenario({super.key});

  @override
  State<ProfileCompletionScenario> createState() =>
      _ProfileCompletionScenarioState();
}

class _ProfileCompletionScenarioState extends State<ProfileCompletionScenario> {
  String preset = _presets.keys.elementAt(1);

  @override
  Widget build(BuildContext context) => _ProfileForm(
        // A new key per preset: a fresh controller for a different user.
        key: ValueKey(preset),
        userData: _presets[preset]!,
        presetPicker: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _presets.keys)
              ChoiceChip(
                label: Text(name),
                selected: name == preset,
                onSelected: (_) => setState(() => preset = name),
              ),
          ],
        ),
      );
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({
    super.key,
    required this.userData,
    required this.presetPicker,
  });

  final Map<String, Object?> userData;
  final Widget presetPicker;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final registry = materialFieldRegistry();
  late final DynamicFormController? controller;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final validators = _validators();
    final catalog = FormConfig.fromMap(
      _catalogJson,
      supportedTypes: registry.types,
    );
    final pending =
        missingFields(catalog, widget.userData, validators: validators);

    controller = pending.fields.isEmpty
        ? null
        : DynamicFormController(
            FormEngine(config: pending, validators: validators),
            initialData: widget.userData,
          );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final payload = controller!.submit();
    if (payload == null) return;

    setState(() => saving = true);
    await Future<void>.delayed(const Duration(seconds: 1)); // your API call
    if (!mounted) return;
    setState(() => saving = false);
    await showPayload(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    return ScenarioPage(
      title: 'Profile completion',
      whatToTry: const [
        'Switch presets: each user is asked only for what is missing.',
        '"Invalid stored data" asks again for filled but invalid fields, '
            'prefilled with the stored value.',
        'The optional nickname is never asked.',
        'Save: the payload has only the asked fields; the fields are '
            'disabled while saving.',
      ],
      header: widget.presetPicker,
      snapshot: controller,
      form: controller == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Profile complete: nothing to ask.')),
            )
          : DynamicForm(
              controller: controller,
              registry: registry,
              enabled: !saving,
            ),
      bottomBar: controller == null
          ? null
          : FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
    );
  }
}
