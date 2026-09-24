import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    {
      'key': 'title',
      'type': 'text',
      'label': 'Title',
      'required': true,
      'validators': [
        {'type': 'minLength', 'value': 5},
      ],
    },
    {
      'key': 'priority',
      'type': 'dropdown',
      'label': 'Priority',
      'required': true,
      'options': [
        {'value': 'low', 'label': 'Low'},
        {'value': 'high', 'label': 'High'},
      ],
    },
    {
      'key': 'reason',
      'type': 'text',
      'label': 'Why is it urgent?',
      'required': true,
      'visibleWhen': {'field': 'priority', 'equals': 'high'},
    },
    {
      'key': 'notify',
      'type': 'checkbox',
      'label': 'Notify the team',
    },
  ],
};

/// No controller: the screen owns a history of immutable snapshots and
/// drives [DynamicFormView] with plain `setState`, the same shape a Cubit,
/// a Riverpod Notifier or a Redux store would use. Every field, text
/// included, shows what the current snapshot holds.
class ExternalStateScenario extends StatefulWidget {
  const ExternalStateScenario({super.key});

  @override
  State<ExternalStateScenario> createState() => _ExternalStateScenarioState();
}

class _ExternalStateScenarioState extends State<ExternalStateScenario> {
  final registry = materialFieldRegistry();
  final engine = FormEngine(config: FormConfig.fromMap(_catalogJson));

  /// Every snapshot ever produced; the last one is current. Snapshots are
  /// immutable, so keeping old ones is safe and cheap.
  late List<FormSnapshot> history = [engine.initial()];

  /// The current snapshot, for the inspector.
  late final current = ValueNotifier(history.last);

  void _setHistory(List<FormSnapshot> next) => setState(() {
        history = next;
        current.value = next.last;
      });

  void push(FormSnapshot next) => _setHistory([...history, next]);

  void undo() => _setHistory(history.sublist(0, history.length - 1));

  void reset() => _setHistory([engine.initial()]);

  void fillSample() => push(
        [
          ('title', 'Fix login crash'),
          ('priority', 'high'),
          ('reason', 'Blocks every user'),
          ('notify', true),
        ].fold(current.value, (s, e) => engine.change(s, e.$1, e.$2)),
      );

  void submit() {
    final result = engine.submit(current.value);
    push(result.snapshot);
    if (result.payload case final payload?) showPayload(context, payload);
  }

  @override
  void dispose() {
    current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'External state & undo',
        whatToTry: const [
          'Type a title, pick High, type a reason. Each change is a new '
              'snapshot in the history.',
          'Undo, Reset and Fill sample change the snapshot from outside '
              'the fields: every field follows, text fields included.',
          'Undo while typing a title: the text steps back one keystroke at '
              'a time, and typing again continues from there.',
        ],
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: history.length > 1 ? undo : null,
          ),
          IconButton(
            tooltip: 'Fill sample',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: fillSample,
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: reset,
          ),
        ],
        header: Text('History: ${history.length} snapshot(s)'),
        snapshot: current,
        form: DynamicFormView(
          engine: engine,
          snapshot: current.value,
          onChanged: (key, value) =>
              push(engine.change(current.value, key, value)),
          registry: registry,
        ),
        bottomBar: FilledButton(
          onPressed: current.value.submitAttempted && !current.value.isValid
              ? null
              : submit,
          child: const Text('Submit'),
        ),
      );
}
