import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    {
      'key': 'cpf',
      'type': 'text',
      'label': 'CPF',
      'hint': '11 digits, dots and dash optional',
      'required': true,
      'validators': [
        {'type': 'cpf'},
      ],
    },
    {
      'key': 'birthDate',
      'type': 'text',
      'label': 'Birth date',
      'hint': 'dd/mm/yyyy',
      'required': true,
      'validators': [
        {'type': 'date'},
        {'type': 'minAge', 'value': 18},
      ],
    },
    {
      'key': 'coupon',
      'type': 'text',
      'label': 'Coupon (optional)',
      'validators': [
        {
          'type': 'oneOf',
          'values': ['WELCOME10', 'FRIENDS20'],
          'message': 'Unknown coupon',
        },
      ],
    },
    {
      'key': 'iban',
      'type': 'text',
      'label': 'IBAN',
      'hint': 'Uses a validator this app version does not know',
      'required': true,
      'validators': [
        {'type': 'iban'},
      ],
    },
  ],
};

DateTime? _parseDate(Object? v) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(v.toString());
  if (m == null) return null;
  final day = int.parse(m[1]!), month = int.parse(m[2]!);
  final date = DateTime(int.parse(m[3]!), month, day);
  // DateTime rolls over (31/02 -> 03/03); reject instead.
  return date.day == day && date.month == month ? date : null;
}

/// Brazilian tax ID: 11 digits, two check digits, not all equal.
bool _isValidCpf(String input) {
  final d = input.replaceAll(RegExp(r'[.\-]'), '');
  if (!RegExp(r'^\d{11}$').hasMatch(d) || RegExp(r'^(\d)\1+$').hasMatch(d)) {
    return false;
  }
  final digits = d.split('').map(int.parse).toList();
  int check(int length) {
    var sum = 0;
    for (var i = 0; i < length; i++) {
      sum += digits[i] * (length + 1 - i);
    }
    final rest = sum * 10 % 11;
    return rest == 10 ? 0 : rest;
  }

  return check(9) == digits[9] && check(10) == digits[10];
}

/// A validator written by the app. It returns an error code, never text:
/// the localizer below turns codes into text.
final class _Check extends Validator<String> {
  const _Check(this.code, this.isValid, [this.params = const {}]);

  final String code;
  final bool Function(String value) isValid;
  final Map<String, Object?> params;

  @override
  ValidationError? validate(String value, _) =>
      isValid(value) ? null : ValidationError(code, params: params);
}

int _age(DateTime birth) {
  final now = DateTime.now();
  final beforeBirthday = now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day);
  return now.year - birth.year - (beforeBirthday ? 1 : 0);
}

ValidatorRegistry _validators() => ValidatorRegistry()
  ..register('cpf', (_) => _Check('cpf', _isValidCpf))
  ..register('date', (_) => _Check('date', (v) => _parseDate(v) != null))
  ..register('minAge', (spec) {
    final minAge = spec['value']! as int;
    // Malformed dates are the `date` validator's job.
    return _Check('minAge', (v) {
      final birth = _parseDate(v);
      return birth == null || _age(birth) >= minAge;
    }, {'min': minAge});
  })
  ..register('oneOf', (spec) {
    final allowed = (spec['values']! as List).cast<String>().toSet();
    return _Check('oneOf', (v) => allowed.contains(v.toUpperCase()));
  });

/// Text for the app's own codes; the built-in ones stay in English.
String _localizer(ValidationError error, FieldDef<Object?>? field) =>
    switch (error.code) {
      'cpf' => 'Invalid CPF',
      'date' => 'Use dd/mm/yyyy',
      'minAge' => 'You must be at least ${error.params['min']}',
      'oneOf' => 'Not an accepted value',
      _ => englishErrorLocalizer(error, field),
    };

/// Validators registered by the app, composed with built-ins, and one the
/// app does not know.
class CustomValidatorsScenario extends StatefulWidget {
  const CustomValidatorsScenario({super.key});

  @override
  State<CustomValidatorsScenario> createState() =>
      _CustomValidatorsScenarioState();
}

class _CustomValidatorsScenarioState extends State<CustomValidatorsScenario> {
  final registry = materialFieldRegistry();
  final catalog = FormCatalog.fromJson(_catalogJson, validators: _validators());
  late final controller = FormController(catalog);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'Custom validators',
        whatToTry: const [
          'CPF: 529.982.247-25 is valid; 529.982.247-26 fails the check '
              'digit; 111.111.111-11 is rejected.',
          'Birth date: 31/02/2000 fails "date"; a date 17 years ago '
              'passes "date" and fails "minAge".',
          'Coupon is optional: empty is valid, "welcome10" is accepted. Its '
              '"Unknown coupon" text comes from the catalog\'s message.',
          'IBAN: any non-empty value passes, because the app skips the '
              'unknown "iban" validator. The server stays the final '
              'authority.',
        ],
        header: catalog.issues.isEmpty
            ? null
            : Text(
                'Skipped: ${catalog.issues.map((i) => '${i.path} ${i.detail}').join(', ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        snapshot: controller,
        form: FormView(
          controller: controller,
          registry: registry,
          localizer: _localizer,
        ),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
