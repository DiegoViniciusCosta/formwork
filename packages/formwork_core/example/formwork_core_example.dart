// A Dart backend validating a payload against the same catalog the app
// renders. Run with: dart run example/formwork_core_example.dart
import 'package:formwork_core/formwork_core.dart';

/// The catalog the server sends to the app, and validates against.
final catalog = FormCatalog.fromJson({
  'fields': [
    {'key': 'name', 'type': 'text', 'label': 'Name', 'required': true},
    {
      'key': 'email',
      'type': 'email',
      'label': 'Email',
      'required': true,
      'validators': [
        {'type': 'email'},
      ],
    },
    {
      'key': 'maritalStatus',
      'type': 'dropdown',
      'label': 'Marital status',
      'options': [
        {'value': 'single', 'label': 'Single'},
        {'value': 'married', 'label': 'Married'},
      ],
    },
    {
      'key': 'spouseName',
      'type': 'text',
      'label': 'Spouse name',
      'required': true,
      'visibleWhen': {
        'eq': ['maritalStatus', 'married'],
      },
    },
  ],
});

void main() {
  const engine = FormEngine();

  // What the app sent: married, but no spouse name, and a bad email.
  final submitted = {
    'name': 'Ana',
    'email': 'ana@',
    'maritalStatus': 'married',
  };

  final form = engine.registerAll(
    engine.initial(initialValues: submitted),
    catalog.fields,
  );
  final (:snapshot, :payload) = engine.submit(form);
  if (payload == null) {
    // The same errors the app shows, as data: a code plus params.
    for (final def in snapshot.visibleFields) {
      if (snapshot.stateOf(def)!.error case final error?) {
        print('Rejected ${def.path}: ${localizeError(error, def)}');
      }
    }
  } else {
    print('Accepted: $payload');
  }
}
