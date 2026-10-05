import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme;

import 'scenarios/all_field_types.dart';
import 'scenarios/catalog_playground.dart';
import 'scenarios/conditional_fields.dart';
import 'scenarios/cubit_form.dart';
import 'scenarios/custom_field_types.dart';
import 'scenarios/custom_validators.dart';
import 'scenarios/external_state.dart';
import 'scenarios/groups_and_lists.dart';
import 'scenarios/profile_completion.dart';
import 'scenarios/rebuild_inspector.dart';
import 'scenarios/riverpod_form.dart';
import 'scenarios/shadcn_form.dart';

void main() {
  // Built before runApp, as an app would at its root: in debug web builds,
  // building it deep in the widget tree overflows the stack while
  // shadcn_ui's libraries load.
  final shadTheme = shadcnTheme();
  runApp(
    // For the Riverpod and shadcn_ui scenarios.
    ProviderScope(
      child: ShadTheme(
        data: shadTheme,
        child: MaterialApp(
          title: 'formwork examples',
          theme: ThemeData(colorSchemeSeed: Colors.indigo),
          home: const ScenarioGallery(),
        ),
      ),
    ),
  );
}

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
    title: 'Groups and lists',
    subtitle: 'Nested payload; add, remove and move items',
    icon: Icons.view_list,
    page: GroupsAndListsScenario.new,
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
    title: 'Cubit (flutter_bloc)',
    subtitle: 'A BlocSelector per field; server errors',
    icon: Icons.view_stream,
    page: CubitScenario.new,
  ),
  (
    title: 'Riverpod',
    subtitle: 'A select per field; server errors',
    icon: Icons.water_drop,
    page: RiverpodScenario.new,
  ),
  (
    title: 'Your design system (shadcn_ui)',
    subtitle: 'The same form with another component library',
    icon: Icons.palette,
    page: ShadcnScenario.new,
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
