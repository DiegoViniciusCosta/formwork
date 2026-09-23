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

// Validators return display text in the current 0.1 API. Design doc 0001
// replaces this with error data (code plus params) and a localizer.
ValidatorRegistry _validators(void Function(String type) onUnknown) =>
    ValidatorRegistry(onUnknown: onUnknown)
      ..register(
        'cpf',
        (s) => (v) => _isValidCpf(v.toString())
            ? null
            : s['message'] as String? ?? 'Invalid CPF',
      )
      ..register(
        'date',
        (s) => (v) => _parseDate(v) == null
            ? s['message'] as String? ?? 'Use dd/mm/yyyy'
            : null,
      )
      ..register('minAge', (s) {
        final minAge = s['value'] as int;
        return (v) {
          final birth = _parseDate(v);
          // Malformed dates are the `date` validator's job.
          if (birth == null) return null;
          final now = DateTime.now();
          final beforeBirthday = now.month < birth.month ||
              (now.month == birth.month && now.day < birth.day);
          final age = now.year - birth.year - (beforeBirthday ? 1 : 0);
          return age < minAge
              ? s['message'] as String? ?? 'You must be at least $minAge'
              : null;
        };
      })
      ..register('oneOf', (s) {
        final allowed = (s['values'] as List).cast<String>().toSet();
        return (v) => allowed.contains(v.toString().toUpperCase())
            ? null
            : s['message'] as String? ?? 'Not an accepted value';
      });

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
  final unknownTypes = <String>{};
  late final DynamicFormController controller;

  @override
  void initState() {
    super.initState();
    // Built here, not lazily: the engine reports unknown validators while
    // it is created, before the first build reads [unknownTypes].
    controller = DynamicFormController(
      FormEngine(
        config: FormConfig.fromMap(_catalogJson),
        validators: _validators(unknownTypes.add),
      ),
    );
  }

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
          'Coupon is optional: empty is valid, "welcome10" is accepted.',
          'IBAN: any non-empty value passes, because the app skips the '
              'unknown "iban" validator. The server stays the final '
              'authority.',
        ],
        header: unknownTypes.isEmpty
            ? null
            : Text(
                'Skipped unknown validators: ${unknownTypes.join(', ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        snapshot: controller,
        form: DynamicForm(controller: controller, registry: registry),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
