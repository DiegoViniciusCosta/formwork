import 'field_path.dart';
import 'validation_error.dart';

/// The server's answer to a rejected submit (design doc 0008 §2): errors
/// for fields, and one for the whole form.
final class ServerErrors {
  /// An answer with field errors by path, and a form error.
  ServerErrors({
    Map<FieldPath, ValidationError> fields = const {},
    this.form,
  }) : fields = Map.unmodifiable(fields);

  /// Errors by field path. An error for a path no field registers is
  /// discarded: map unknown keys to [form], or handle them in the app.
  final Map<FieldPath, ValidationError> fields;

  /// An error about the whole form, such as "wrong e-mail or password".
  final ValidationError? form;

  /// Whether the answer holds no error: the server accepted.
  bool get isEmpty => fields.isEmpty && form == null;
}
