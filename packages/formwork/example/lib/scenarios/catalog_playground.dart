import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _sample = '''
{
  "schemaVersion": 1,
  "fields": [
    {"key": "email", "type": "email", "label": "Email", "required": true,
     "validators": [{"type": "email"}]},
    {"key": "kind", "type": "dropdown", "label": "Account", "required": true,
     "options": [{"value": "personal", "label": "Personal"},
                 {"value": "company", "label": "Company"}]},
    {"key": "company", "type": "text", "label": "Company name",
     "required": true, "visibleWhen": {"eq": ["kind", "company"]}},
    {"key": "photo", "type": "camera", "label": "Photo"}
  ]
}''';

/// Paste or edit a catalog and render it on the spot, the way a server
/// or remote config would send it.
class CatalogPlaygroundScenario extends StatefulWidget {
  const CatalogPlaygroundScenario({super.key});

  @override
  State<CatalogPlaygroundScenario> createState() =>
      _CatalogPlaygroundScenarioState();
}

class _CatalogPlaygroundScenarioState extends State<CatalogPlaygroundScenario> {
  final registry = materialFieldRegistry();
  final source = TextEditingController(text: _sample);

  FormController? controller;
  List<String> warnings = [];
  String? error;

  @override
  void initState() {
    super.initState();
    apply();
  }

  void apply() {
    try {
      final catalog =
          FormCatalog.fromJson(jsonDecode(source.text) as Map<String, dynamic>);
      // Disposed once the widgets listening to it are gone.
      final old = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      setState(() {
        controller = FormController(catalog);
        error = null;
        warnings = [
          for (final issue in catalog.issues)
            'Skipped (${issue.kind.name}) in ${issue.path}: ${issue.detail}',
        ];
      });
    } on Object catch (e) {
      // Malformed JSON, a malformed catalog, a duplicate key...
      setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final errorColor = Theme.of(context).colorScheme.error;
    return ScenarioPage(
      title: 'Catalog playground',
      whatToTry: const [
        'Edit the JSON and tap Apply. The form is rebuilt from scratch.',
        '"camera" is an unknown type, so it is skipped and reported.',
        'Duplicate a key, or put a number in "label": the error is shown '
            'and the previous form stays.',
        'Make "company" visible when kind is "partner", which is not an '
            'option: the condition is dropped and reported.',
        'Add {"type": "phone"} to a field\'s validators: it is skipped.',
      ],
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: source,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Catalog JSON',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: apply,
              child: const Text('Apply'),
            ),
          ),
          if (error case final error?)
            Text(error, style: TextStyle(color: errorColor)),
          for (final warning in warnings)
            Text(warning, style: TextStyle(color: errorColor)),
          const Divider(height: 32),
        ],
      ),
      snapshot: controller,
      form: controller == null
          ? const SizedBox.shrink()
          : FormView(
              // A new controller means a new form, not an update of the old.
              key: ObjectKey(controller),
              controller: controller,
              registry: registry,
            ),
      bottomBar: controller == null
          ? null
          : SubmitButton(
              key: ObjectKey(controller),
              controller: controller,
              onValid: (payload) => showPayload(context, payload),
            ),
    );
  }
}
