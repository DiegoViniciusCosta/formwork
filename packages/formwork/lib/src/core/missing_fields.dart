import 'field_config.dart';
import 'validators.dart';

/// Keys of the fields the user still has to answer. Hides nothing: use it
/// to highlight missing fields in the whole form, or narrow the form with
/// [missingFields].
///
/// A field is missing when its current value in [userData] fails the
/// catalog's own rules:
/// - required and empty: missing;
/// - filled but invalid (e.g. a malformed email): missing;
/// - optional and empty: not missing.
///
/// Fields with `visibleWhen` count only when relevant to this user: if
/// the controlling field is already known, the rule is evaluated now; if it
/// is also missing, the rule is resolved on screen. The controlling field
/// must itself be relevant, so a hidden field hides the whole chain below
/// it.
Set<String> missingKeys(
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

  return {
    for (final f in catalog.fields)
      if (pending.contains(f.key) && relevant(f, {f.key})) f.key,
  };
}

/// Narrows [catalog] down to the fields the user still has to answer: the
/// [missingKeys], in catalog order.
///
/// A known field that sits between two missing keys in the same
/// `visibleWhen` chain is kept too, so the engine sees the whole chain and
/// hiding the top of it also hides the bottom. Pass the same [userData] to
/// the engine (`initial` or the controller's `initialData`) and that field
/// shows its stored value.
FormConfig missingFields(
  FormConfig catalog,
  Map<String, Object?> userData, {
  ValidatorRegistry? validators,
}) {
  final missing = missingKeys(catalog, userData, validators: validators);
  final byKey = {for (final f in catalog.fields) f.key: f};

  // Walk up from each missing key; the known fields passed before reaching
  // another missing key are links.
  final links = <String>{};
  for (final key in missing) {
    final between = <String>[];
    final seen = {key};
    for (var f = byKey[byKey[key]!.visibleWhen?.field];
        f != null && seen.add(f.key);
        f = byKey[f.visibleWhen?.field]) {
      if (missing.contains(f.key)) {
        links.addAll(between);
        break;
      }
      between.add(f.key);
    }
  }

  return FormConfig(
    [
      for (final f in catalog.fields)
        if (missing.contains(f.key) || links.contains(f.key)) f,
    ],
    schemaVersion: catalog.schemaVersion,
  );
}
