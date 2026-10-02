# 0009: Groups and lists in the engine

Status: **accepted** (2026-10-02): groups ship first, lists after.
Amended 2026-10-02: item fields come from a function (§3, §5)

## Problem

0001 §1 gives every field a `FieldPath` (`address.zipCode`,
`dependents[#k3f9].name`) and names `group` and `list` as structural types
"handled by the engine". Step 6 of 0001 implements them, and the docs leave
the shape open:

- The catalog shape exists (`{"type": "group", ...}`, `{"type": "list",
  "itemFields": [...]}`), but not what the code-first API looks like.
- The payload is flat today: `{"address.zipCode": "01000"}`. No backend
  expects that, and a list cannot be written that way.
- A list needs operations (add, remove, move an item), ids that survive
  them, and a place for `minItems` and `maxItems` errors.
- Saved data with lists (`initialValues`) and server errors by index
  (`dependents[0].name`) must find the right item.

Decision 29 of 0001 already settles one thing: rules read fields, never a
group or a list as a whole.

## Principles

- **Principle 3 (validation):** lists are validated like any field
  (`minItems`, `maxItems`, `required`), errors stay data, and server
  errors by index reach the right item even after items moved.
- **Principle 2 (rebuilds):** stable ids are the point. Removing item 0
  must not change the path, the state or the widget of item 1. Adding an
  item rebuilds the list's own field and mounts the new item's fields;
  nothing else.
- **Principle 1 (agnostic):** the engine ships no list UI. A list is a
  field whose builder the app (or a satellite kit) provides; formwork's
  core widgets stay design-free.
- **Risk:** lists are the biggest change to the engine since registration.
  The incremental-versus-full equivalence test grows to cover add, remove
  and move.

## Decision

### 1. Groups are a path prefix, not an object

```dart
FormDef([
  TextFieldDef('address.street'),
  TextFieldDef('address.zipCode', required: true),
]);
```

```json
{ "key": "address", "type": "group", "fields": [
  { "key": "zipCode", "type": "text", "required": true } ] }
```

- **Code:** a dotted key is already a field inside a group. No new class.
- **Catalog:** a `group` entry expands into its fields, with the group key
  as a prefix (`address.zipCode`), in order. Groups nest.
- **A group has no state and no rules of its own** in this release. A
  `visibleWhen` (or any other rule) on a catalog group is skipped and
  listed in `catalog.issues` as `ruleOnGroup`, under the tolerance rule.
- **A key cannot be both a field and a group** (`address` and
  `address.zipCode`): registering throws an `ArgumentError`, and a
  catalog with both is malformed, as with a duplicated key.
- **Decision 29 is checked here:** a rule that reads a path that is a
  group (a strict ancestor of a registered field's path) or a list throws
  an `ArgumentError` when the form registers in code, as a duplicated key
  does. The catalog skips the field that holds the rule and reports it as
  `readsGroup`, as it does for a cycle: dropping only the rule would show
  a field that was meant to hide. The check runs both ways: whichever of
  the rule and the group's fields registers second.

### 2. The payload and the initial values are nested JSON

```json
{ "address": { "street": "Rua A", "zipCode": "01000" },
  "dependents": [ { "name": "Ana" }, { "name": "Bia" } ] }
```

- **`payload()`** nests by path: groups become objects, lists become
  arrays in item order. Hidden fields stay out, as today; a group with no
  visible field is left out; a list with no items is `[]`.
- **`initialValues` and user data take the same shape**, so the data the
  app loads is what it sent. A field finds its value by walking its path
  through nested maps and lists. A flat key (`"address.zipCode"`) still
  works and wins over the nested one.
- A custom field whose value is itself a map (`{"lat": 1, "lng": 2}`) is
  unaffected: walking stops at the field's own path.

### 3. A list is a field whose value is its item ids

```dart
ListFieldDef('dependents',
  itemFields: (item) => [TextFieldDef('$item.name', required: true)],
  minItems: 1,
  maxItems: 5,
)
```

```json
{ "key": "dependents", "type": "list", "minItems": 1, "maxItems": 5,
  "itemFields": [ { "key": "name", "type": "text", "required": true } ] }
```

- **`ListFieldDef extends FieldDef<List<String>>`,** registry type
  `"list"`. Its value is the ordered list of item ids. That makes the list
  an ordinary field for everything that already exists: `FieldState`,
  `FieldView`, a builder in the registry, `visibleWhen`, `required`.
- **Item fields come from a function of the item's path** (amended
  2026-10-02). A `FieldDef`'s path is fixed when it is built, and Dart
  cannot copy an object of a type it does not know, so the engine cannot
  move `TextFieldDef('name')` under `dependents[#3]`. It calls
  `itemFields(dependents[#3])` instead, and registers what it returns.
  Every returned path must be inside the item. `fieldsAt(id)` calls it
  for one item, for a builder that places the item's fields itself. The
  catalog's `"itemFields"` stays a JSON list: the catalog builds the
  function.
- **Its errors:** `required` means at least one item. `minItems` and
  `maxItems` give errors with codes `minItems` (`{'min': n}`) and
  `maxItems` (`{'max': n}`), checked on the item count even when the list
  is empty. `errorCount`, `submit` and focus treat it like any field.
- **Item fields follow their list:** a hidden list hides its items, and a
  disabled list disables them. Unregistering a list unregisters its
  items, which come back with it; removing an item forgets them.
- **The value changes only through the operations of §4:** `change` on a
  list throws an `ArgumentError`.
- **Ids** come from a counter in the snapshot (`1`, `2`, ...), so the
  engine stays pure and tests are deterministic. An id is never reused in
  the same snapshot history.
- **Item fields** register at `dependents[#3].name` when the item is
  added and unregister when it is removed. Their values do not come back
  if an item is re-added: a new item is a new id.
- **Item fields' rules** may read paths outside any list. Reading a
  sibling (`$item.age`) stays for the list UI doc (0001, "Decided with
  acceptance" 2).

### 4. Engine operations

```dart
FormSnapshot addItem(FormSnapshot s, FieldPath list,
    {Map<String, Object?> values = const {}, int? at});
FormSnapshot removeItem(FormSnapshot s, FieldPath item);
FormSnapshot moveItem(FormSnapshot s, FieldPath item, int to);
```

- **`addItem`** appends (or inserts at `at`) an item, registers its
  fields with `values` (nested JSON, like `initialValues`), and changes
  the list's value. The new id is the one in the list's value at that
  position.
- **Going past `maxItems` is allowed** and gives the `maxItems` error.
  The engine records, the UI decides whether to hide the "add" button.
- **Each counts as a change of the list** for `touched`, `dirty` (ids
  differ from the initial ones) and the race rule of 0008 §2.
- **Order:** `visibleFields`, `firstErrorPath` and the payload list item
  fields right after their list, in item order, not in registration
  order.
- **Server errors by index** (`dependents[0].name`) are mapped to the id
  at that index *when the send started*, so a move during the send does
  not misplace them. An error for an index with no item is discarded,
  like any path no field registers (0008 §2 as amended).
- `FormController` gets the same three methods, delegating to the engine.

### 5. Rendering

- formwork ships **no** `"list"` builder. The list UI (add and remove
  buttons, item cards, `$item` paths) is the later doc 0001 already
  announces. Until then an app registers its own `"list"` builder, which
  receives the ids in `props.value` and places a `FieldView` for each
  definition `listDef.fieldsAt(id)` returns.
- `FormView` renders item fields right after the list, in item order, as
  it renders any visible field. A form that wants them inside the list's
  builder uses a custom layout, as 0006 §4 allows.

## Alternatives considered

- **A `GroupDef` class in code.** Mirrors the catalog, but a dotted key
  already says the same thing, and it would make `FormDef.fields` hold two
  kinds of entries. It can be added later without breaking anyone. Lost.
- **A flat payload** (`"address.zipCode"` keys, `"dependents[0].name"`).
  It is what the engine stores, but no backend takes it, and the app would
  rebuild the nesting itself. Lost.
- **A list outside `FieldDef`** (a separate `ListDef` and `ListState`).
  Cleaner in theory, but every consumer (`FieldView`, focus, status,
  registry, catalog) would need a second path. 0001 already sketched
  `ListFieldDef` inside `fields`. Lost.
- **Item fields as definitions with a relative path**
  (`itemFields: [TextFieldDef('name')]`, the first version of this doc).
  The engine would have to copy each definition under the item's path:
  either every `FieldDef`, custom ones included, implements a
  `withPath` copy, or the absolute path moves from the definition to
  `FieldState`, which touches everything that reads `def.path`. A wrapper
  with another path breaks builders that check the concrete type
  (`def is ChoiceFieldDef`). Lost on 2026-10-02.
- **Random ids** (`k3f9`, as 0001's example). They need a random source,
  which breaks purity and deterministic tests. Counter ids are as stable.
  Lost.
- **Refuse `addItem` past `maxItems`.** It hides a rule violation instead
  of reporting it, and a `maxItems` lowered by a new catalog would still
  leave too many items. Errors are data. Lost.

## Impact

- **Breaking, inside the unreleased foundation:** `payload()` becomes
  nested. Top-level fields are unchanged; only dotted keys move.
- **`formwork_core`:** `ListFieldDef`; `addItem`, `removeItem`,
  `moveItem`; nested `payload()` and `initialValues`; the catalog reads
  `group` and `list`; the decision-29 check; server errors by index.
- **`formwork`:** the three methods on `FormController`; item-field order
  in `FormView`. No new widget.
- **`formwork_material`:** nothing.
- **Example:** one scenario with an address group and a dependents list
  whose `"list"` builder is written in the example itself.

**Tests, written first.**
- **Groups:** catalog expansion and nesting; nested payload and initial
  values; a flat key wins; a rule on a catalog group is reported; reading
  a group or a list throws in code (both registration orders) and is
  skipped by the catalog.
- **Lists:** add, insert, remove and move keep every other item's path
  and state identical; ids are never reused; `minItems`, `maxItems` and
  `required` errors; `initialValues` with a list create its items; the
  payload is in item order and skips hidden item fields; server errors by
  index land on the item that was at that index when the send started.
- **Equivalence:** random add, remove, move and change sequences equal
  building the same items from scratch.
- **Rebuilds** (`rebuild_test.dart`): adding an item builds the list's
  field and the new item's fields only; removing one rebuilds the list's
  field only; moving one rebuilds the list's field only.
- **Work per change:** a change inside item 3 of a 1,000-item list costs
  the same as in a 10-item list.

## Decided with acceptance

1. **Groups ship first, lists after,** in separate commits of BACKLOG
   item 4. Groups are small (catalog expansion, nested payload, the
   decision-29 check); lists are most of the work and of the risk.

## Open questions

1. **`onlyMissing` and `missingKeys` with lists.** Implemented as
   proposed, and approved on 2026-10-02: a list is missing when its own rules
   (`required`, `minItems`, `maxItems`) fail on the number of items in the
   data, and then it is asked as a whole; items are never asked one by
   one. Groups need nothing new: their fields are asked by path.
2. **Rules on a group** (`visibleWhen` on `address` hiding all its
   fields). Left out here: every field can carry the condition today.
