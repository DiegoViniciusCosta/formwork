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
      'visibleWhen': {
        'eq': ['maritalStatus', 'married'],
      },
    },
    {
      'key': 'hasVehicle',
      'type': 'dropdown',
      'label': 'Do you have a vehicle?',
      'required': true,
      'options': [
        {'value': 'yes', 'label': 'Yes'},
        {'value': 'no', 'label': 'No'},
      ],
    },
    {
      'key': 'vehicleType',
      'type': 'dropdown',
      'label': 'Vehicle type',
      'required': true,
      'options': [
        {'value': 'car', 'label': 'Car'},
        {'value': 'motorbike', 'label': 'Motorbike'},
      ],
      'visibleWhen': {
        'eq': ['hasVehicle', 'yes'],
      },
    },
    {
      'key': 'licensePlate',
      'type': 'text',
      'label': 'License plate',
      'required': true,
      'visibleWhen': {
        'eq': ['vehicleType', 'car'],
      },
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
    'hasVehicle': 'no',
    'acceptedTerms': false,
  },
  'Single, no income': {
    'fullName': 'João Souza',
    'email': 'joao@example.com',
    'taxId': '98765432100',
    'maritalStatus': 'single',
    'hasVehicle': 'no',
    'acceptedTerms': true,
  },
  'Invalid stored data': {
    'fullName': 'Al',
    'email': 'not-an-email',
    'taxId': '123',
    'monthlyIncome': 500,
    'maritalStatus': 'single',
    'hasVehicle': 'no',
    'acceptedTerms': true,
  },
  // Last year: a car. This year hasVehicle was cleared for re-confirmation
  // and the plate is new in the catalog. Vehicle type sits between two
  // missing fields, so it is asked too, prefilled (design doc 0003).
  'Renewal': {
    'fullName': 'João Souza',
    'email': 'joao@example.com',
    'taxId': '98765432100',
    'monthlyIncome': 4000,
    'maritalStatus': 'single',
    'vehicleType': 'car',
    'acceptedTerms': true,
  },
  'Complete': {
    'fullName': 'Ana Lima',
    'email': 'ana@example.com',
    'taxId': '11122233344',
    'monthlyIncome': 5000,
    'maritalStatus': 'single',
    'hasVehicle': 'no',
    'acceptedTerms': true,
  },
};

/// Exactly [length] digits. Error: `digits`, `{'length': length}`.
final class _Digits extends Validator<String> {
  const _Digits(this.length);

  final int length;

  @override
  ValidationError? validate(String value, _) =>
      RegExp('^\\d{$length}\$').hasMatch(value)
          ? null
          : ValidationError('digits', params: {'length': length});
}

ValidatorRegistry _validators() => ValidatorRegistry()
  ..register('digits', (spec) => _Digits(spec['value']! as int));

String _localizer(ValidationError error, FieldDef<Object?>? field) =>
    error.code == 'digits'
        ? 'Must have ${error.params['length']} digits'
        : englishErrorLocalizer(error, field);

/// How the form treats what the user already answered (design doc 0003).
enum _Mode {
  /// `onlyMissing`: only the questions still to be answered.
  onlyMissing('Only missing'),

  /// `missingKeys`: the whole form, missing fields highlighted.
  highlightMissing('Highlight missing');

  const _Mode(this.label);
  final String label;
}

/// Wraps the Material builders so the fields in [missing] stand out. The
/// set describes the stored data, so it is fixed for the session.
FieldRegistry _highlighting(Set<FieldPath> missing) => FieldRegistry()
  ..registerAll({
    for (final MapEntry(key: type, value: build)
        in materialFieldBuilders.entries)
      type: (context, field) {
        final child = build(context, field);
        if (!missing.contains(field.def.path)) return child;
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          child: child,
        );
      },
  });

/// Progressive profiling: the same catalog, either narrowed to what each
/// user still has to answer, or shown whole with that highlighted.
class ProfileCompletionScenario extends StatefulWidget {
  const ProfileCompletionScenario({super.key});

  @override
  State<ProfileCompletionScenario> createState() =>
      _ProfileCompletionScenarioState();
}

class _ProfileCompletionScenarioState extends State<ProfileCompletionScenario> {
  String preset = _presets.keys.elementAt(1);
  _Mode mode = _Mode.onlyMissing;

  @override
  Widget build(BuildContext context) => _ProfileForm(
        // A new key per preset and mode: a fresh controller for each.
        key: ValueKey((preset, mode)),
        userData: _presets[preset]!,
        mode: mode,
        pickers: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_Mode>(
              segments: [
                for (final m in _Mode.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setState(() => mode = s.single),
            ),
            const SizedBox(height: 12),
            Wrap(
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
          ],
        ),
      );
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({
    super.key,
    required this.userData,
    required this.mode,
    required this.pickers,
  });

  final Map<String, Object?> userData;
  final _Mode mode;
  final Widget pickers;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final FieldRegistry registry;
  late final FormController? controller;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final catalog =
        FormCatalog.fromJson(_catalogJson, validators: _validators());

    final FormCatalog form;
    switch (widget.mode) {
      case _Mode.onlyMissing:
        registry = materialFieldRegistry();
        form = catalog.onlyMissing(widget.userData);
      case _Mode.highlightMissing:
        registry = _highlighting(catalog.missingKeys(widget.userData));
        form = catalog;
    }

    controller = form.fields.isEmpty
        ? null
        : FormController(
            form,
            // Prefills known answers, including a kept middle link.
            initialValues: widget.userData,
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
        'Only missing: switch presets; each user is asked only for what is '
            'missing. The optional nickname is never asked.',
        '"Invalid stored data" asks again for filled but invalid fields, '
            'prefilled with the stored value.',
        '"Renewal": Vehicle type is known but sits between two missing '
            'fields, so it is asked too, prefilled with Car. Answer No: the '
            'type and the plate disappear, and Save works.',
        'Highlight missing: the whole form, prefilled; a bar marks what is '
            'missing.',
        'Save: the payload has only the fields on screen; the fields are '
            'disabled while saving.',
      ],
      header: widget.pickers,
      snapshot: controller,
      form: controller == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Profile complete: nothing to ask.')),
            )
          : FormView(
              controller: controller,
              registry: registry,
              localizer: _localizer,
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
