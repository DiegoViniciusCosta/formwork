import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/build_counts.dart';
import '../shared/scenario_page.dart';

const _fieldCount = 60;

/// A long generated catalog: text and number fields, plus a group that
/// only shows when "showExtras" is checked.
Map<String, dynamic> _bigCatalog() => {
      'fields': [
        {
          'key': 'showExtras',
          'type': 'checkbox',
          'label': 'Show extra fields (every 5th field)',
        },
        for (var i = 1; i <= _fieldCount; i++)
          {
            'key': 'field$i',
            'type': i.isEven ? 'number' : 'text',
            'label': 'Field $i${i % 5 == 0 ? ' (extra)' : ''}',
            'required': i % 3 == 0,
            'validators': [
              if (i.isEven)
                {'type': 'max', 'value': 100}
              else
                {'type': 'minLength', 'value': 2},
            ],
            if (i % 5 == 0)
              'visibleWhen': {
                'eq': ['showExtras', true],
              },
          },
      ],
    };

/// Makes principle 2 visible: typing in one field rebuilds only that field.
class RebuildInspectorScenario extends StatefulWidget {
  const RebuildInspectorScenario({super.key});

  @override
  State<RebuildInspectorScenario> createState() =>
      _RebuildInspectorScenarioState();
}

class _RebuildInspectorScenarioState extends State<RebuildInspectorScenario> {
  final counts = BuildCounts();
  late final registry = countingRegistry(materialFieldBuilders, counts);
  late final controller = FormController(FormCatalog.fromJson(_bigCatalog()));
  bool enabled = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'Rebuild inspector',
        whatToTry: const [
          'The badge counts builds of each field. Type in Field 1: only '
              'its badge grows.',
          'Check "Show extra fields": the checkbox and the extras build; '
              'nothing else rebuilds.',
          'Tap Submit: only fields whose displayed error changed rebuild.',
          'Toggle "enabled" in the app bar: every field rebuilds once, as '
              'expected.',
        ],
        actions: [
          IconButton(
            tooltip: 'Toggle enabled',
            icon: Icon(enabled ? Icons.lock_open : Icons.lock),
            onPressed: () => setState(() => enabled = !enabled),
          ),
        ],
        header: ValueListenableBuilder<FormSnapshot>(
          valueListenable: controller,
          builder: (context, _, __) => TotalBuilds(counts),
        ),
        form: FormView(
          controller: controller,
          registry: registry,
          enabled: enabled,
        ),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
