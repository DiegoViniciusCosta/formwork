import 'package:flutter/material.dart';

import 'scenarios/all_field_types.dart';
import 'scenarios/catalog_playground.dart';
import 'scenarios/conditional_fields.dart';
import 'scenarios/custom_field_types.dart';
import 'scenarios/custom_validators.dart';
import 'scenarios/external_state.dart';
import 'scenarios/profile_completion.dart';
import 'scenarios/rebuild_inspector.dart';

void main() => runApp(
      MaterialApp(
        title: 'formwork examples',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const ScenarioGallery(),
      ),
    );

typedef _Scenario = ({
  String title,
  String subtitle,
  IconData icon,
  Widget Function() page,
});

final List<_Scenario> _scenarios = [
  (
    title: 'Profile completion',
    subtitle: 'onlyMissing and missingKeys with different users',
    icon: Icons.person_search,
    page: ProfileCompletionScenario.new,
  ),
  (
    title: 'All field types',
    subtitle: 'Every built-in type and validator',
    icon: Icons.list_alt,
    page: AllFieldTypesScenario.new,
  ),
  (
    title: 'Conditional fields',
    subtitle: 'visibleWhen, shared controllers and chains',
    icon: Icons.account_tree,
    page: ConditionalFieldsScenario.new,
  ),
  (
    title: 'Custom validators',
    subtitle: 'CPF, dates, age, unknown validator types',
    icon: Icons.rule,
    page: CustomValidatorsScenario.new,
  ),
  (
    title: 'Custom field types',
    subtitle: 'Your own builders next to a kit',
    icon: Icons.widgets,
    page: CustomFieldTypesScenario.new,
  ),
  (
    title: 'Rebuild inspector',
    subtitle: '60 fields with a build counter each',
    icon: Icons.speed,
    page: RebuildInspectorScenario.new,
  ),
  (
    title: 'External state & undo',
    subtitle: 'No controller: immutable snapshot history',
    icon: Icons.history,
    page: ExternalStateScenario.new,
  ),
  (
    title: 'Catalog playground',
    subtitle: 'Edit JSON and render it live',
    icon: Icons.data_object,
    page: CatalogPlaygroundScenario.new,
  ),
];

class ScenarioGallery extends StatelessWidget {
  const ScenarioGallery({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('formwork examples')),
        body: ListView(
          children: [
            for (final s in _scenarios)
              ListTile(
                leading: Icon(s.icon),
                title: Text(s.title),
                subtitle: Text(s.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => s.page()),
                ),
              ),
          ],
        ),
      );
}
