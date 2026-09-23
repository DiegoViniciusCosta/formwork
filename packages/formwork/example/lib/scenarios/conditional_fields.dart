import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    // One controller, several dependents.
    {
      'key': 'contactBy',
      'type': 'dropdown',
      'label': 'Preferred contact',
      'required': true,
      'options': [
        {'value': 'email', 'label': 'Email'},
        {'value': 'phone', 'label': 'Phone'},
        {'value': 'none', 'label': 'Do not contact me'},
      ],
    },
    {
      'key': 'contactEmail',
      'type': 'email',
      'label': 'Contact email',
      'required': true,
      'validators': [
        {'type': 'email'},
      ],
      'visibleWhen': {'field': 'contactBy', 'equals': 'email'},
    },
    {
      'key': 'phone',
      'type': 'text',
      'label': 'Phone',
      'required': true,
      'validators': [
        {'type': 'pattern', 'value': r'^\+?\d{10,13}$'},
      ],
      'visibleWhen': {'field': 'contactBy', 'equals': 'phone'},
    },
    {
      'key': 'bestTime',
      'type': 'dropdown',
      'label': 'Best time to call',
      'options': [
        {'value': 'morning', 'label': 'Morning'},
        {'value': 'evening', 'label': 'Evening'},
      ],
      'visibleWhen': {'field': 'contactBy', 'equals': 'phone'},
    },
    // A chain of three: hasVehicle -> vehicleType -> licensePlate.
    {
      'key': 'hasVehicle',
      'type': 'checkbox',
      'label': 'I have a vehicle',
    },
    {
      'key': 'vehicleType',
      'type': 'dropdown',
      'label': 'Vehicle type',
      'required': true,
      'options': [
        {'value': 'car', 'label': 'Car'},
        {'value': 'bike', 'label': 'Bicycle'},
      ],
      'visibleWhen': {'field': 'hasVehicle', 'equals': true},
    },
    {
      'key': 'licensePlate',
      'type': 'text',
      'label': 'License plate',
      'required': true,
      'validators': [
        {'type': 'pattern', 'value': r'^[A-Z]{3}-?\d[A-Z0-9]\d{2}$'},
      ],
      'visibleWhen': {'field': 'vehicleType', 'equals': 'car'},
    },
  ],
};

/// Fields that appear and disappear, including a chain of dependencies.
class ConditionalFieldsScenario extends StatefulWidget {
  const ConditionalFieldsScenario({super.key});

  @override
  State<ConditionalFieldsScenario> createState() =>
      _ConditionalFieldsScenarioState();
}

class _ConditionalFieldsScenarioState extends State<ConditionalFieldsScenario> {
  final registry = materialFieldRegistry();
  late final controller = DynamicFormController(
    FormEngine(config: FormConfig.fromMap(_catalogJson)),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'Conditional fields',
        whatToTry: const [
          'Contact "Phone" shows two fields; switching to "Email" swaps them.',
          'Type a phone, switch to Email and back: the value is kept, but '
              'hidden fields never reach the payload.',
          'A hidden required field does not block submit.',
          'Chain: check "I have a vehicle" and pick Car to show License '
              'plate. Unchecking hides both Vehicle type and License plate.',
        ],
        snapshot: controller,
        form: DynamicForm(controller: controller, registry: registry),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
