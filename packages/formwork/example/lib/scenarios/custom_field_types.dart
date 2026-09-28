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

final _json = FieldCodec<Object>(encode: (v) => v, decode: (j) => j);

/// A star rating from 1 to [max]. A `num`, so number validators such as
/// `min` apply.
final class RatingFieldDef extends FieldDef<num> {
  RatingFieldDef(super.key,
      {super.label,
      super.required,
      super.validators,
      super.messages,
      this.max = 5});

  final int max;

  @override
  String get type => 'rating';
}

/// One of a few options, as a segmented button.
final class SegmentedFieldDef extends FieldDef<Object> {
  SegmentedFieldDef(super.key,
      {super.label, super.required, required this.options})
      : super(codec: _json);

  final List<Option<Object>> options;

  @override
  String get type => 'segmented';
}

/// A number picked on a slider.
final class SliderFieldDef extends FieldDef<num> {
  SliderFieldDef(super.key,
      {super.label,
      super.initialValue,
      super.validators,
      super.messages,
      this.min = 0,
      this.max = 100,
      this.divisions});

  final num min;
  final num max;
  final int? divisions;

  @override
  String get type => 'slider';
}

/// A yes-or-no switch; "no" is a valid answer.
final class SwitchFieldDef extends FieldDef<bool> {
  SwitchFieldDef(super.key, {super.label});

  @override
  String get type => 'switch';
}

/// How the catalog builds the app's types: common parts come read, the
/// rest from the raw entry.
final _types = FieldTypeRegistry()
  ..register(
      'rating',
      (f) => RatingFieldDef(f.key,
          label: f.label,
          required: f.required,
          validators: f.validators<num>(),
          messages: f.messages,
          max: f.json['max'] as int? ?? 5))
  ..register(
      'segmented',
      (f) => SegmentedFieldDef(f.key,
              label: f.label,
              required: f.required,
              options: [
                for (final o in f.json['options']! as List)
                  Option<Object>(
                      (o as Map)['value'] as Object, o['label'] as String),
              ]))
  ..register(
      'slider',
      (f) => SliderFieldDef(f.key,
          label: f.label,
          initialValue: f.initialValue as num?,
          validators: f.validators<num>(),
          messages: f.messages,
          min: f.json['min'] as num? ?? 0,
          max: f.json['max'] as num? ?? 100,
          divisions: f.json['divisions'] as int?))
  ..register('switch', (f) => SwitchFieldDef(f.key, label: f.label));

/// Builders written for this app. Each receives its definition typed, like
/// any design-system component would.
FieldRegistry _registry() => materialFieldRegistry()
  ..registerDef<RatingFieldDef, num>((context, field, def) {
    final value = field.value ?? 0;
    return _Labeled(
      label: def.label ?? '',
      errorText: field.errorText,
      child: Row(
        children: [
          for (var star = 1; star <= def.max; star++)
            IconButton(
              icon: Icon(star <= value ? Icons.star : Icons.star_border),
              color: Colors.amber,
              onPressed: field.enabled ? () => field.onChanged(star) : null,
            ),
        ],
      ),
    );
  })
  ..registerDef<SegmentedFieldDef, Object>((context, field, def) => _Labeled(
        label: def.label ?? '',
        errorText: field.errorText,
        child: SegmentedButton<Object>(
          emptySelectionAllowed: true,
          segments: [
            for (final o in def.options)
              ButtonSegment(value: o.value, label: Text(o.label)),
          ],
          selected: {if (field.value case final Object v) v},
          onSelectionChanged: field.enabled
              ? (s) => field.onChanged(s.isEmpty ? null : s.first)
              : null,
        ),
      ))
  ..registerDef<SliderFieldDef, num>((context, field, def) {
    final value = (field.value ?? def.min).toDouble();
    return _Labeled(
      label: '${def.label}: ${value.round()}',
      errorText: field.errorText,
      child: Slider(
        value: value,
        min: def.min.toDouble(),
        max: def.max.toDouble(),
        divisions: def.divisions,
        onChanged: field.enabled ? (v) => field.onChanged(v.round()) : null,
      ),
    );
  })
  ..registerDef<SwitchFieldDef, bool>((context, field, def) => SwitchListTile(
        title: Text(def.label ?? ''),
        contentPadding: EdgeInsets.zero,
        value: field.value ?? false,
        onChanged: field.enabled ? field.onChanged : null,
      ));

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
  final registry = _registry();
  final catalog = FormCatalog.fromJson(_catalogJson, types: _types);
  late final controller = FormController(catalog);

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
          'Rating reads "max" into its own RatingFieldDef. 1–2 stars show the '
              'built-in "min" validator with a custom message.',
          'Tap the selected segment again to clear it: required fires.',
          'Slider below 50 fails "min". The slider starts at initialValue.',
          '"signature" is a type this app does not know: it is skipped when '
              'the catalog is read, so its "required" never blocks submit.',
        ],
        header: catalog.issues.isEmpty
            ? null
            : Text(
                'Skipped: ${catalog.issues.map((i) => '${i.path} (${i.detail})').join(', ')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        snapshot: controller,
        form: FormView(controller: controller, registry: registry),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
