import 'field_config.dart';
import 'validators.dart';

/// Narrows [catalog] down to the fields the user still has to fill in.
///
/// A field is missing when its current value in [userData] fails the
/// catalog's own rules:
/// - required and empty: asked;
/// - filled but invalid (e.g. a malformed email): asked, prefilled;
/// - optional and empty: not asked.
///
/// Fields with `visibleWhen` are kept only when relevant to this user: if
/// the controlling field is already known, the rule is evaluated now; if it
/// is also missing, both are kept and the rule is resolved on screen. The
/// controlling field must itself be relevant, so a hidden field hides the
/// whole chain below it.
FormConfig missingFields(
  FormConfig catalog,
  Map<String, Object?> userData, {
  ValidatorRegistry? validators,
}) {
  final registry = validators ?? ValidatorRegistry();

  final pending = <String>{
    for (final f in catalog.fields)
      if (registry.buildFor(f)?.call(userData[f.key]) != null) f.key,
  };

  final byKey = {for (final f in catalog.fields) f.key: f};

  bool relevant(FieldConfig f, Set<String> seen) {
    final rule = f.visibleWhen;
    if (rule == null) return true;
    if (!pending.contains(rule.field) && !rule.evaluate(userData)) return false;
    final controller = byKey[rule.field];
    // `seen` stops a cycle (A reads B, B reads A) from looping forever.
    if (controller == null || !seen.add(controller.key)) return true;
    return relevant(controller, seen);
  }

  return FormConfig(
    [
      for (final f in catalog.fields)
        if (pending.contains(f.key) && relevant(f, {f.key})) f,
    ],
    schemaVersion: catalog.schemaVersion,
  );
}
