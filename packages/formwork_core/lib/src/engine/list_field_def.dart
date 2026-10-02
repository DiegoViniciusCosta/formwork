import 'field_codec.dart';
import 'field_def.dart';
import 'field_path.dart';
import 'validation_error.dart';

/// A repeatable list: `"list"` in a catalog (design doc 0009 §3). Its value
/// is the ordered list of its item ids; each item holds the fields
/// [itemFields] returns for it.
///
/// Compared by identity, as [itemFields] is a function: registering a new
/// `ListFieldDef` at the same path replaces the old one, and calls
/// [itemFields] again for every item, even when nothing else differs
/// (design doc 0007 §3). Keep the same instance to make it free.
///
/// Items are added, removed and moved with `FormEngine.addItem`,
/// `removeItem` and `moveItem` (or the same methods of a controller), not
/// with `change`. The payload holds the list as an array of objects, in
/// item order. Rules read fields, never a list as a whole (decision 29 of
/// design doc 0001).
final class ListFieldDef extends FieldDef<List<String>> {
  /// A list at [key] whose items hold the fields [itemFields] returns.
  ///
  /// `required` asks for at least one item; [minItems] and [maxItems]
  /// bound the count. See [FieldDef.new] for the other parameters.
  ListFieldDef(
    super.key, {
    required this.itemFields,
    this.minItems,
    this.maxItems,
    super.label,
    super.hint,
    super.required,
    super.visibleWhen,
    super.enabledWhen,
    super.requiredWhen,
    super.extra,
    super.messages,
  }) : super(codec: const _ItemIds());

  /// The fields of the item at the path it receives, such as
  /// `dependents[#3]`. Every returned path must be inside that item:
  /// `(item) => [TextFieldDef('$item.name')]`. Called for each item, so it
  /// returns the same fields for the same path.
  final List<FieldDef<Object?>> Function(FieldPath item) itemFields;

  /// The fewest items; error `minItems`, `{'min': minItems}`.
  final int? minItems;

  /// The most items; error `maxItems`, `{'max': maxItems}`.
  final int? maxItems;

  @override
  String get type => 'list';

  /// The path of the item with [id], such as `dependents[#3]`, for
  /// `removeItem` and `moveItem`.
  FieldPath itemPath(String id) => path.item(id);

  /// The fields of the item with [id], for a builder that places them.
  List<FieldDef<Object?>> fieldsAt(String id) => itemFields(itemPath(id));
}

/// The error of [def] for [count] items, from [ListFieldDef.minItems] and
/// [ListFieldDef.maxItems]. Engine-side; the package barrel does not
/// export it.
ValidationError? itemCountError(ListFieldDef def, int count) {
  if (def.minItems case final min? when count < min) {
    return ValidationError('minItems', params: {'min': min});
  }
  if (def.maxItems case final max? when count > max) {
    return ValidationError('maxItems', params: {'max': max});
  }
  return null;
}

/// Item ids are not payload: the engine writes a list's JSON from its
/// items, and reads its items from JSON itself.
final class _ItemIds extends FieldCodec<List<String>> {
  const _ItemIds() : super.base();

  @override
  Object? encode(List<String> value) => value;

  @override
  List<String> decode(Object json) =>
      throw FormatException('A list reads its items, not ids', json);

  @override
  bool operator ==(Object other) => other is _ItemIds;

  @override
  int get hashCode => (_ItemIds).hashCode;
}

/// The innermost list item [path] is inside: the list, the item's path and
/// its id; `null` outside any list. Engine-side; not exported.
({FieldPath list, FieldPath item, String id})? itemOf(FieldPath path) {
  for (var p = path.parent; p != null; p = p.parent) {
    if (p.segments.last case ItemSegment(:final id)) {
      return (list: p.parent!, item: p, id: id);
    }
  }
  return null;
}

/// The groups [path] is inside, innermost first, up to the list item that
/// holds it, if any. Engine-side; not exported.
Iterable<FieldPath> groupsOf(FieldPath path) sync* {
  for (var p = path.parent; p != null; p = p.parent) {
    if (p.segments.last is! KeySegment) return;
    yield p;
  }
}
