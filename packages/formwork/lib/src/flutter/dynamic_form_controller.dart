import 'package:flutter/foundation.dart';
import 'package:formwork_core/formwork_core.dart';

/// Minimal [FormEngine] adapter using only Flutter, for apps without a
/// state management package.
class DynamicFormController extends ValueNotifier<FormSnapshot> {
  /// Creates a controller starting from [initialData].
  DynamicFormController(
    this.engine, {
    Map<String, Object?> initialData = const {},
  }) : super(engine.initial(initialData));

  /// The rules this controller applies.
  final FormEngine engine;

  /// Updates the value of [key].
  void change(String key, Object? value) =>
      this.value = engine.change(this.value, key, value);

  /// Returns the payload when valid; otherwise `null`, and every error
  /// becomes visible.
  Map<String, Object?>? submit() {
    final result = engine.submit(value);
    value = result.snapshot;
    return result.payload;
  }
}
