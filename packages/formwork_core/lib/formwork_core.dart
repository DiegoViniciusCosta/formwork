/// The formwork engine in pure Dart, with no Flutter dependency.
///
/// Import it on its own to validate the same catalogs in a Dart backend or
/// CLI. Flutter apps import `package:formwork/formwork.dart`, which
/// re-exports this library.
library;

export 'src/catalog/condition_registry.dart';
export 'src/catalog/form_catalog.dart' hide narrowCatalog;
export 'src/catalog/missing_data.dart';
export 'src/catalog/validator_registry.dart';
export 'src/engine/built_in_validators.dart' hide matchesPath;
export 'src/engine/condition.dart';
export 'src/engine/dependency_graph.dart' show CycleError;
export 'src/engine/empty_value.dart';
export 'src/engine/error_localizer.dart';
export 'src/engine/field_codec.dart' show FieldCodec;
export 'src/engine/field_def.dart' show FieldDef, Validator;
export 'src/engine/field_defs.dart';
export 'src/engine/field_path.dart' show FieldPath;
export 'src/engine/field_state.dart' show FieldState;
export 'src/engine/form_def.dart';
export 'src/engine/form_engine.dart';
export 'src/engine/form_status.dart';
export 'src/engine/server_errors.dart';
export 'src/engine/validation_error.dart';
