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
     "required": true, "visibleWhen": {"field": "kind", "equals": "company"}},
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

  DynamicFormController? controller;
  List<String> warnings = [];
  String? error;

  @override
  void initState() {
    super.initState();
    apply();
  }

  void apply() {
    final skipped = <String>[];
    final unknownValidators = <String>{};
    try {
      final engine = FormEngine(
        config: FormConfig.fromMap(
          jsonDecode(source.text) as Map<String, dynamic>,
          supportedTypes: registry.types,
          onUnsupported: (f) => skipped.add('${f.key} (${f.type})'),
        ),
        validators: ValidatorRegistry(onUnknown: unknownValidators.add),
      );
      // Disposed once the widgets listening to it are gone.
      final old = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      setState(() {
        controller = DynamicFormController(engine);
        error = null;
        warnings = [
          if (skipped.isNotEmpty) 'Skipped fields: ${skipped.join(', ')}',
          if (unknownValidators.isNotEmpty)
            'Skipped validators: ${unknownValidators.join(', ')}',
        ];
      });
    } on Object catch (e) {
      // Malformed JSON, a wrong type in the catalog, a duplicate key...
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
        '"camera" has no builder, so it is skipped and reported.',
        'Duplicate a key, or put a string in "required": the error is '
            'shown and the previous form stays.',
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
          : DynamicForm(
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
