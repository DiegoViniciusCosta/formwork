import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    {
      'key': 'username',
      'type': 'text',
      'label': 'Username',
      'hint': '3 to 12 lowercase letters or digits',
      'required': true,
      'validators': [
        {'type': 'minLength', 'value': 3},
        {'type': 'maxLength', 'value': 12},
        {
          'type': 'pattern',
          'value': r'^[a-z0-9]+$',
          'message': 'Only lowercase letters and digits',
        },
      ],
    },
    {
      'key': 'email',
      'type': 'email',
      'label': 'Email',
      'required': true,
      'validators': [
        {'type': 'email', 'message': 'That does not look like an email'},
      ],
    },
    {
      'key': 'password',
      'type': 'password',
      'label': 'Password',
      'required': true,
      'validators': [
        {'type': 'minLength', 'value': 8},
        {
          'type': 'pattern',
          'value': r'\d',
          'message': 'Must contain at least one digit',
        },
      ],
    },
    {
      'key': 'age',
      'type': 'number',
      'label': 'Age',
      'required': true,
      'validators': [
        {'type': 'min', 'value': 18, 'message': 'You must be an adult'},
        {'type': 'max', 'value': 120},
      ],
    },
    {
      'key': 'website',
      'type': 'text',
      'label': 'Website (optional)',
      'validators': [
        {
          'type': 'pattern',
          'value': r'^https?://',
          'message': 'Must start with http:// or https://',
        },
      ],
    },
    {
      'key': 'plan',
      'type': 'dropdown',
      'label': 'Plan',
      'required': true,
      'initialValue': 'free',
      'options': [
        {'value': 'free', 'label': 'Free'},
        {'value': 'pro', 'label': 'Pro'},
        {'value': 'team', 'label': 'Team'},
      ],
    },
    {
      'key': 'newsletter',
      'type': 'checkbox',
      'label': 'Send me the newsletter (optional)',
    },
    {
      'key': 'acceptedTerms',
      'type': 'checkbox',
      'label': 'I accept the terms',
      'required': true,
    },
  ],
};

/// Every built-in field type and validator, with message overrides.
class AllFieldTypesScenario extends StatefulWidget {
  const AllFieldTypesScenario({super.key});

  @override
  State<AllFieldTypesScenario> createState() => _AllFieldTypesScenarioState();
}

class _AllFieldTypesScenarioState extends State<AllFieldTypesScenario> {
  final registry = materialFieldRegistry();
  late final controller = FormController(FormCatalog.fromJson(_catalogJson));

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'All field types',
        whatToTry: const [
          'Tap Submit right away: every error appears and the button '
              'disables until the form is valid.',
          'Username "AB": only the first failing validator is shown '
              '(minLength before pattern).',
          'Password: "abcdefgh" fails the digit pattern.',
          'Age: letters are filtered; "17" shows the custom message.',
          'Website is optional: empty is valid, "www.x.com" is not.',
          'Plan starts at "Free" from initialValue.',
        ],
        snapshot: controller,
        form: FormView(controller: controller, registry: registry),
        bottomBar: SubmitButton(
          controller: controller,
          label: 'Create account',
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
