import 'field_def.dart';

/// A form: its fields, in the order the default layout renders them and
/// the payload lists them (design docs 0001 §3 and 0006 §1).
///
/// Write a form as a class whose fields are members, so that `form.` lists
/// them and conditions and validators can reference them:
///
/// ```dart
/// class ProfileForm extends FormDef {
///   final maritalStatus = ChoiceFieldDef<MaritalStatus>('maritalStatus',
///       options: [for (final s in MaritalStatus.values) Option(s, s.name)]);
///   late final spouseName = TextFieldDef('spouseName',
///       visibleWhen: maritalStatus.equals(MaritalStatus.married));
///
///   @override
///   List<FieldDef<Object?>> get fields => [maritalStatus, spouseName];
/// }
/// ```
///
/// `FormDef([...])` builds one from a list. A form is one source of
/// definitions for the engine, registered in a batch (design doc 0007 §2).
class FormDef {
  /// A form with [fields]. Subclasses override [fields] instead.
  FormDef([List<FieldDef<Object?>> fields = const []])
      : _fields = List.unmodifiable(fields);

  final List<FieldDef<Object?>> _fields;

  /// The fields, in order. Two fields with the same key make registering
  /// the form throw.
  List<FieldDef<Object?>> get fields => _fields;
}
