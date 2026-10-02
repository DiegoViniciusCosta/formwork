import 'package:flutter/material.dart';
import 'package:formwork/formwork.dart';
import 'package:formwork_material/formwork_material.dart';

import '../shared/scenario_page.dart';

const _catalogJson = <String, dynamic>{
  'fields': [
    {'key': 'name', 'type': 'text', 'label': 'Name', 'required': true},
    {
      'key': 'address',
      'type': 'group',
      'fields': [
        {'key': 'street', 'type': 'text', 'label': 'Street'},
        {
          'key': 'zipCode',
          'type': 'text',
          'label': 'ZIP code',
          'required': true,
        },
      ],
    },
    {
      'key': 'dependents',
      'type': 'list',
      'label': 'Dependents',
      'minItems': 1,
      'maxItems': 3,
      'itemFields': [
        {
          'key': 'name',
          'type': 'text',
          'label': 'Dependent name',
          'required': true,
        },
        {'key': 'age', 'type': 'number', 'label': 'Age'},
      ],
    },
  ],
};

/// A group nests the payload; a list adds, removes and moves items. formwork
/// ships no list widget (design doc 0009 §5): this screen registers its own
/// `"list"` builder, and FormView places each item's fields after it.
class GroupsAndListsScenario extends StatefulWidget {
  const GroupsAndListsScenario({super.key});

  @override
  State<GroupsAndListsScenario> createState() => _GroupsAndListsScenarioState();
}

class _GroupsAndListsScenarioState extends State<GroupsAndListsScenario> {
  late final controller = FormController(
    FormCatalog.fromJson(_catalogJson),
    initialValues: const {
      'address': {'street': 'Rua A'},
      'dependents': [
        {'name': 'Ana', 'age': 7},
      ],
    },
  );
  late final registry = materialFieldRegistry()..register('list', _list);

  Widget _list(BuildContext context, FieldProps<Object?> field) {
    final def = field.def as ListFieldDef;
    final ids = field.value as List<String>? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(def.label ?? '', style: Theme.of(context).textTheme.titleMedium),
        for (var i = 0; i < ids.length; i++)
          Row(children: [
            Expanded(child: Text('Dependent ${i + 1}')),
            IconButton(
              tooltip: 'Move up',
              icon: const Icon(Icons.arrow_upward),
              onPressed: i == 0
                  ? null
                  : () => controller.moveItem(def.itemPath(ids[i]), i - 1),
            ),
            IconButton(
              tooltip: 'Remove dependent ${i + 1}',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => controller.removeItem(def.itemPath(ids[i])),
            ),
          ]),
        if (field.errorText case final error?)
          Text(error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add dependent'),
          onPressed: () => controller.addItem(def.path),
        ),
      ],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScenarioPage(
        title: 'Groups and lists',
        whatToTry: const [
          'Submit: the payload nests "address" and holds "dependents" as an '
              'array, in item order.',
          'Add up to three dependents; a fourth shows the maxItems error.',
          'Remove every dependent: the list asks for at least one.',
          'Move a dependent up: only the list rebuilds, and its fields keep '
              'what you typed.',
        ],
        snapshot: controller,
        form: FormView(controller: controller, registry: registry),
        bottomBar: SubmitButton(
          controller: controller,
          onValid: (payload) => showPayload(context, payload),
        ),
      );
}
