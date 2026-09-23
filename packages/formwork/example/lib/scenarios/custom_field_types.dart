import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    {
      'key': 'name',
      'type': 'text',
      'label': 'Name',
      'required': true,
    },
    {
      'key': 'rating',
      'type': 'rating',
      'label': 'How was your experience?',
      'required': true,
      'max': 5, // unknown to the catalog parser: lands in `extra`
      'validators': [
        {'type': 'min', 'value': 3, 'message': 'Tell us what went wrong below'},
      ],
    },
    {
      'key': 'recommend',
      'type': 'segmented',
      'label': 'Would you recommend us?',
      'required': true,
      'options': [
        {'value': 'no', 'label': 'No'},
        {'value': 'maybe', 'label': 'Maybe'},
        {'value': 'yes', 'label': 'Yes'},
      ],
    },
    {
      'key': 'budget',
      'type': 'slider',
      'label': 'Monthly budget',
      'initialValue': 50,
      'min': 0,
      'max': 500,
      'divisions': 10,
      'validators': [
        {'type': 'min', 'value': 50, 'message': 'Our cheapest plan is 50'},
      ],
    },
    {
      'key': 'contactMe',
      'type': 'switch',
      'label': 'You may contact me about my answers',
    },
    {
      'key': 'signature',
      'type': 'signature',
      'label': 'Signature',
      'required': true,
    },
  ],
};

/// Builders written for this app. Each one sees only [FieldConfig] and
/// [FieldContext], like any design-system component would.
final Map<String, FieldBuilder> _appBuilders = {
  'rating': (context, f, x) {
    final max = f.extra['max'] as int? ?? 5;
    final value = x.value as int? ?? 0;
    return _Labeled(
      label: f.label,
      errorText: x.errorText,
      child: Row(
        children: [
          for (var star = 1; star <= max; star++)
            IconButton(
              icon: Icon(star <= value ? Icons.star : Icons.star_border),
              color: Colors.amber,
              onPressed: x.enabled ? () => x.onChanged(star) : null,
            ),
        ],
      ),
    );
  },
  'segmented': (context, f, x) => _Labeled(
        label: f.label,
        errorText: x.errorText,
        child: SegmentedButton<Object>(
          emptySelectionAllowed: true,
          segments: [
            for (final o in f.options)
              ButtonSegment(value: o.value, label: Text(o.label)),
          ],
          selected: {if (x.value case final Object v) v},
          onSelectionChanged:
              x.enabled ? (s) => x.onChanged(s.isEmpty ? null : s.first) : null,
        ),
      ),
  'slider': (context, f, x) {
    final min = (f.extra['min'] as num? ?? 0).toDouble();
    final max = (f.extra['max'] as num? ?? 100).toDouble();
    final value = (x.value as num? ?? min).toDouble();
    return _Labeled(
      label: '${f.label}: ${value.round()}',
      errorText: x.errorText,
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: f.extra['divisions'] as int?,
        onChanged: x.enabled ? (v) => x.onChanged(v.round()) : null,
      ),
    );
  },
  'switch': (context, f, x) => SwitchListTile(
        title: Text(f.label),
        contentPadding: EdgeInsets.zero,
        value: x.value == true,
        onChanged: x.enabled ? x.onChanged : null,
      ),
};

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.errorText});

  final String label;
  final String? errorText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        child,
        if (errorText case final error?)
          Text(
            error,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
      ],
    );
  }
}

/// App-specific field types mixed with a kit, and a type the app cannot
/// render.
class CustomFieldTypesScenario extends StatefulWidget {
  const CustomFieldTypesScenario({super.key});

  @override
  State<CustomFieldTypesScenario> createState() =>
      _CustomFieldTypesScenarioState();
}

class _CustomFieldTypesScenarioState extends State<CustomFieldTypesScenario> {
  final registry = materialFieldRegistry()..registerAll(_appBuilders);
  final skipped = <String>[];
  late final DynamicFormController controller;

  @override
  void initState() {
    super.initState();
    controller = DynamicFormController(
      FormEngine(
        config: FormConfig.fromMap(
          _catalogJson,
          supportedTypes: registry.types,
          onUnsupported: (f) => skipped.add('${f.key} (${f.type})'),
        ),
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
        title: 'Custom field types',
        whatToTry: const [
          'Rating, segmented, slider and switch are built by the app; '
              'Name comes from formwork_material. Same registry.',
          'Rating reads "max" from FieldConfig.extra. 1–2 stars show the '
              'built-in "min" validator with a custom message.',
          'Tap the selected segment again to clear it: required fires.',
          'Slider below 50 fails "min". The slider starts at initialValue.',
          '"signature" has no builder: it is dropped at parse time, so its '
              '"required" never blocks submit.',
        ],
        header: skipped.isEmpty
            ? null
            : Text(
                'Skipped unsupported fields: ${skipped.join(', ')}',
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
