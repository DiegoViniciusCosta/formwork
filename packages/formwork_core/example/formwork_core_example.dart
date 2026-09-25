// A Dart backend validating a payload against the same catalog the app
// renders. Run with: dart run example/formwork_core_example.dart
import 'package:formwork_core/formwork_core.dart';

/// The catalog the server sends to the app, and validates against.
final catalog = FormConfig.fromMap({
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
      'visibleWhen': {'field': 'maritalStatus', 'equals': 'married'},
    },
  ],
});

void main() {
  final engine = FormEngine(config: catalog);

  // What the app sent: married, but no spouse name, and a bad email.
  final submitted = {
    'name': 'Ana',
    'email': 'ana@',
    'maritalStatus': 'married',
  };

  final (:snapshot, :payload) = engine.submit(engine.initial(submitted));
  if (payload == null) {
    // The same errors the app shows, keyed by field.
    print('Rejected: ${snapshot.errors}');
  } else {
    print('Accepted: $payload');
  }
}
