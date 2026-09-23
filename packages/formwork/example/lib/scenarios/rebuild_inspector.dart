import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

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
              'visibleWhen': {'field': 'showExtras', 'equals': true},
          },
      ],
    };

/// Counts how many times each field's builder runs.
class _BuildCounts {
  final counts = <String, int>{};

  int hit(String key) => counts[key] = (counts[key] ?? 0) + 1;

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Wraps every builder of [inner] with a badge showing its build count.
FieldRegistry _countingRegistry(
  Map<String, FieldBuilder> inner,
  _BuildCounts counts,
) =>
    FieldRegistry()
      ..registerAll({
        for (final MapEntry(key: type, value: build) in inner.entries)
          type: (context, f, x) => Row(
                children: [
                  Expanded(child: build(context, f, x)),
                  const SizedBox(width: 8),
                  _Badge(counts.hit(f.key)),
                ],
              ),
      });

class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hot = count > 1;
    return Container(
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hot ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Makes principle 2 visible: typing in one field rebuilds only that field.
class RebuildInspectorScenario extends StatefulWidget {
  const RebuildInspectorScenario({super.key});

  @override
  State<RebuildInspectorScenario> createState() =>
      _RebuildInspectorScenarioState();
}

class _RebuildInspectorScenarioState extends State<RebuildInspectorScenario> {
  final counts = _BuildCounts();
  late final registry = _countingRegistry(materialFieldBuilders, counts);
  late final controller = DynamicFormController(
    FormEngine(config: FormConfig.fromMap(_bigCatalog())),
  );
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
          builder: (context, _, __) => _TotalBuilds(counts),
        ),
        form: DynamicForm(
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

class _TotalBuilds extends StatefulWidget {
  const _TotalBuilds(this.counts);

  final _BuildCounts counts;

  @override
  State<_TotalBuilds> createState() => _TotalBuildsState();
}

class _TotalBuildsState extends State<_TotalBuilds> {
  int total = 0;

  @override
  void didUpdateWidget(_TotalBuilds old) {
    super.didUpdateWidget(old);
    _refreshAfterFrame();
  }

  @override
  void initState() {
    super.initState();
    _refreshAfterFrame();
  }

  // Field builders run later in the same frame than this widget, so the
  // total is read once the frame is done.
  void _refreshAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && total != widget.counts.total) {
          setState(() => total = widget.counts.total);
        }
      });

  @override
  Widget build(BuildContext context) => Text(
        'Field builds so far: $total',
        style: Theme.of(context).textTheme.titleMedium,
      );
}
