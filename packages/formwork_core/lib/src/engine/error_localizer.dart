import 'field_def.dart';
import 'validation_error.dart';

/// Turns an error into the text a user reads (design doc 0001 §2).
///
/// [field] is the field the error belongs to, or `null` for an error about
/// the whole form (design doc 0008 §3). A field's own
/// [FieldDef.messages] win over any localizer: see [localizeError].
typedef ErrorLocalizer = String Function(
  ValidationError error,
  FieldDef<Object?>? field,
);

/// The English texts of the built-in error codes, the default localizer.
/// An unknown code reads "Invalid value".
String englishErrorLocalizer(ValidationError error, FieldDef<Object?>? field) {
  final params = error.params;
  return switch (error.code) {
    'required' => 'This field is required',
    'minLength' => 'Must be at least ${params['min']} characters',
    'maxLength' => 'Must be at most ${params['max']} characters',
    'pattern' => 'Invalid format',
    'email' => 'Invalid email address',
    'min' => 'Must be at least ${params['min']}',
    'max' => 'Must be at most ${params['max']}',
    'matches' => 'Does not match',
    'minItems' => 'Needs at least ${_items(params['min'])}',
    'maxItems' => 'Allows at most ${_items(params['max'])}',
    _ => 'Invalid value',
  };
}

String _items(Object? count) => count == 1 ? '1 item' : '$count items';

/// The text of [error] on [field]: the field's own message for the code
/// when it has one, as a catalog's `message` sets, else [localizer]'s.
String localizeError(
  ValidationError error,
  FieldDef<Object?>? field, [
  ErrorLocalizer localizer = englishErrorLocalizer,
]) =>
    field?.messages[error.code] ?? localizer(error, field);
