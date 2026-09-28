/// Whether [value] counts as empty for `required`: `null`, blank text,
/// `false`, or an empty collection or map. A required checkbox must
/// therefore be checked; a yes/no question whose "no" is a valid answer is
/// a choice field instead (design doc 0003).
bool isEmptyValue(Object? value) =>
    value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is bool && !value) ||
    (value is Iterable && value.isEmpty) ||
    (value is Map && value.isEmpty);
