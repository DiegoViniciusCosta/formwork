# 0001: Foundation

Status: **accepted** (2026-09-23)

This document fixes the decisions that are expensive to change after 1.0:
the value model, the error model, the definition API and conditions. It
also introduces the dependency graph and per-field state, which tie them
together and are what make principles 2 and 3 hold as features grow.

Async validation, sliver rendering and repeatable-list UI are out of scope
here, but the model below must support them without breaking changes.

## 1. Value model: paths with stable item ids

### Problem

Keys are flat today (`spouseName`). Real forms have groups
(`address.zipCode`) and repeatable lists (`dependents[2].name`).

### Decision

Every field is addressed by a `FieldPath`. Values live in a **flat map
keyed by canonical path**, not in a nested structure.

List items get a **stable internal id**, not their index:

```
dependents[#k3f9].name      internal path
dependents[0].name          serialized path (payload, server errors)
```

The engine converts ids to indexes only at the edges: when building the
payload and when mapping server errors back to fields.

### Why

- **Flat map:** reading or updating one field is O(1), which principle 2
  needs. A nested structure makes every update copy a spine of parents and
  makes per-field comparison harder.
- **Stable ids:** with index-based paths, removing item 0 shifts every key
  after it. Every following field would look changed (breaking principle
  2), and widget state such as text controllers would jump to the wrong
  item.

### Alternatives considered

- *Nested immutable maps:* natural for JSON, but costly for per-field
  updates and diffs.
- *Index-based paths:* simplest, but breaks rebuilds and widget state on
  insert and remove.

### Catalog shape

```json
{ "key": "address", "type": "group", "fields": [ ... ] }
{ "key": "dependents", "type": "list", "minItems": 0, "maxItems": 5,
  "itemFields": [ ... ] }
```

`group` and `list` are structural types handled by the engine, not by the
field registry.

## 2. Error model: codes plus a localizer

### Decision

Validators return data, never text:

```dart
class ValidationError {
  final String code;                 // 'minLength'
  final Map<String, Object?> params; // {'min': 3}
  final ErrorSource source;          // local, async, server
}
```

An `ErrorLocalizer` turns an error into text:

```dart
typedef ErrorLocalizer =
    String Function(ValidationError error, FieldDef field);
```

The package ships an English default localizer. A `message` in the catalog
remains a per-field override, applied before the localizer.

`FieldContext` exposes both the localized `errorText` and the raw
`ValidationError`, so a design system can render codes its own way (for
example, an icon per error type).

### Why

- Principle 1: the design system decides how errors look and read.
- Principle 3: errors are comparable, testable data. Server errors fit the
  same type with `source: server`.

## 3. Definition API: typed Dart first, JSON as serialization

### Decision

The model is a tree of typed Dart definitions. Map/JSON is one way to build
it, not the primary one.

```dart
final form = FormDef([
  TextFieldDef('fullName', required: true, validators: [minLength(3)]),
  NumberFieldDef('income', validators: [min(1000)]),
  ChoiceFieldDef<String>('maritalStatus', options: [...]),
  TextFieldDef('spouseName',
      required: true,
      visibleWhen: eq('maritalStatus', 'married')),
  ListFieldDef('dependents', itemFields: [TextFieldDef('name')]),
]);

final fromServer = FormDef.fromJson(json, types: typeRegistry);
```

`FieldDef<T>` carries the value type. The engine stores `Object?`
internally; typed access goes through the definition:

```dart
final income = snapshot.valueOf(incomeField); // num?
```

Custom field types and validators register a JSON factory in a registry.
Unknown types keep the tolerance rule: skipped and reported.

### Why

- Principle 3: typed validators (`Validator<num>`) catch mistakes at
  compile time instead of casting at runtime.
- One model, two front doors: code-defined and server-driven forms share
  the same engine and tests.

### Open question

Should `FormDef` round-trip (`toJson()`)? Useful for tooling and form
builders, but it commits every custom type to being serializable.

## 4. Conditions: a structured AST, not strings

### Decision

`visibleWhen`, `enabledWhen` and `requiredWhen` take a `Condition`:

```dart
all([eq('maritalStatus', 'married'), gte('age', 18)])
```

```json
{ "all": [ { "eq": ["maritalStatus", "married"] },
           { "gte": ["age", 18] } ] }
```

Built-in operators: `eq`, `ne`, `in`, `gt`, `gte`, `lt`, `lte`, `empty`,
`all`, `any`, `not`. Custom operators register like validators and follow
the tolerance rule.

Every condition can list the paths it reads. This is what feeds the
dependency graph (section 5).

### Why not a string expression language

A string like `"maritalStatus == 'married' && age >= 18"` needs a parser,
has no static structure to validate or version, and invites arbitrary logic
into the catalog. The AST is serializable, analyzable and safe.

## 5. The dependency graph

### Decision

Every rule declares what it reads:

- conditions (`visibleWhen`, `enabledWhen`, `requiredWhen`);
- cross-field validators (`matches('password')`, date ranges).

At `FormDef` build time the engine creates a reverse index:
**path → rules that read it**. A change to path P recomputes only the
rules in that index, then follows the chain if a recomputed rule changes
another field's state.

Cycles (A's visibility depends on B, B's on A) are detected at build time
and rejected with a clear error.

### Why

This is the single mechanism behind principles 2 and 3. Incremental
revalidation, visibility and cross-field validation all use the same graph
instead of each growing its own special case. The current `_dependents`
index is the first, narrow version of it.

### Open question

Relative paths inside list items: a rule in `dependents[#id].relationship`
that reads a sibling needs a syntax such as `$item.age`. To be decided
together with the list UI.

## 6. Per-field state and structural sharing

### Decision

The snapshot holds one immutable `FieldState` per path:

```dart
class FieldState {
  final Object? value;
  final ValidationError? error;
  final bool visible, enabled, required, touched, dirty, validating;
}
```

When the engine applies a change, **every `FieldState` that did not change
is the same instance** as in the previous snapshot. Each snapshot also
exposes `changedPaths`.

### Why

Principle 2 becomes an identity check. The view rebuilds a field if and
only if `!identical(previous, next)`, replacing today's tuple comparison.
Adapters can use `changedPaths` directly: a `BlocSelector` or Riverpod
`select` per field works out of the box.

`validating` is in the state now, even before async validation exists, so
adding it later is not a breaking change.

## Migration from 0.1

0.1 is unpublished, so this is a clean break:

| 0.1                        | Foundation                          |
|----------------------------|-------------------------------------|
| `FieldConfig` (Map only)   | `FieldDef<T>` plus `FormDef.fromJson` |
| flat `String` keys         | `FieldPath` with stable item ids    |
| `String` errors            | `ValidationError` plus localizer    |
| `VisibilityRule` (equals)  | `Condition` AST                     |
| `_dependents` index        | dependency graph                    |
| tuple cache in the view    | `FieldState` identity               |

`missingFields` becomes a recipe on top of `FormDef` and the engine.

## Implementation order

1. `FieldPath`, `FieldState`, `ValidationError`: pure data types, fully
   tested.
2. `Condition` AST, JSON codec, operators.
3. Dependency graph, cycle detection, incremental engine on top of it.
4. `FieldDef<T>` and `FormDef.fromJson`.
5. View switch to identity checks; rebuild tests updated.
6. `group` and `list` in the engine; list UI stays for a later document.

## Decided with acceptance

1. **`FormDef.toJson()`:** not in the foundation release. Custom types are
   not required to serialize. A visual form editor is a later goal of the
   backlog, and it is what will bring `toJson()` back: registered as a
   plan, not a refusal.
2. **Relative paths inside list items** (`$item.age`): decided together
   with the list UI, in its own doc.

## Decided during implementation (2026-09-28)

Conditions (§4), settled in step 2:

1. **`in` is `isIn` in Dart**, a reserved word otherwise. It matches the
   field helper of 0006. JSON keeps `"in"`.
2. **`empty` counts what `required` counts as empty:** `null`, blank
   text, `false` and an empty collection. One notion of empty in the
   library. `eq(path, false)` tells "answered no" apart from "not
   answered".
3. **An unknown operator drops the whole condition**, nested ones
   included, and is reported. The field behaves as if it had no such
   rule: visible, not required, enabled. Dropping only the unknown branch
   would change what the rest means. A malformed condition throws, as a
   malformed validator spec does.
4. **JSON shapes.** A condition is an object with exactly one key, its
   operator:

   | Operator                             | Arguments                |
   |--------------------------------------|--------------------------|
   | `eq`, `ne`, `gt`, `gte`, `lt`, `lte` | `["path", value]`        |
   | `in`                                 | `["path", [value, ...]]` |
   | `empty`                              | `["path"]`               |
   | `all`, `any`                         | `[condition, ...]`       |
   | `not`                                | `condition`              |

5. **Custom operators** register in a `ConditionRegistry`, like
   validators: `register(operator, (args, decode) => ...)`, where `decode`
   decodes nested conditions.
6. **Operands through field codecs (step 4, 0006 §3).** `decode` gains an
   optional named parameter that decodes an operand given its path. It is
   additive, so `ConditionFactory` does not change. Built-in operators use
   it; a custom operator decodes its own operands.
7. **Known cost of `isIn`, and of 0006's `matches`, `min` and `max`:**
   `package:test` and `flutter_test` export matchers named `isIn` and
   `matches`, and `dart:math` exports `min` and `max`. A file that
   imports both and uses one of them must hide it from one side.

Dependency graph (§5), settled in step 3:

8. **Only conditions take part in cycle detection.** A condition changes
   another field's state, which can flow down a chain. A cross-field
   validator only revalidates, and no chain follows it. Two validators
   that read each other (`matches` both ways) are allowed.

The engine (§3, §6, and 0002 open question 2), settled in step 3:

9. **`Validator<T>`** declares what it reads, like a condition:

   ```dart
   abstract class Validator<T> {
     Set<FieldPath> get reads => const {}; // other paths; usually none
     ValidationError? validate(T value, Object? Function(FieldPath) valueOf);
   }
   ```

   Validators still skip empty values; only `required` judges them.
   Built-in validators compare by value (0007 §3).
10. **The snapshot exposes accessors only:** `stateOf(def)`,
    `valueOf(def)`, `changedPaths`, `visibleFields`, `payload()`, and
    `status` when 0008 lands. The `values`, `errors` and `touched` maps go away, in the
    same clean break as the rest of 0001: nothing builds a whole map on
    a change.
11. **A disabled field is read-only data:** it stays in the payload and
    is not validated. An error the user cannot fix would block submit,
    for the same reason 0007 does not block on server errors for fields
    that are not on screen.
12. **`required: true` or `requiredWhen`:** a field is required when
    either holds. Passing both is redundant, not an error.
13. **A field that registers again comes back as it was:** value,
    `touched`, and the initial value `dirty` compares with. A change to
    its path while it is unregistered updates the value it will find.

Definitions, codecs and catalogs (§3, and 0006 §1 to §3), settled in
step 4:

14. **Built-in definitions keep the catalog's type names:**
    `TextFieldDef` (`"text"`), `NumberFieldDef` (`"number"`),
    `ChoiceFieldDef<T>` (`"dropdown"`) and `BoolFieldDef` (`"checkbox"`).
    Catalogs and the Material builders stay as they are. Any other value
    type is a custom `FieldDef<T>` with a `codec:`.
15. **`FieldCodec<T>`** is two functions, `encode` and `decode`. Built-in
    codecs compare by value; an app's codec compares by identity.
16. **`FormCatalog.fromJson`**, in the catalog library: a `FormDef` built
    from JSON, which also lists what the tolerance rule skipped. It is
    the `catalog` of 0004's `catalog.onlyMissing(data)`.
17. **Message overrides live on the definition:** `FieldDef.messages`
    maps an error code to text, as §2's per-field override. A catalog
    validator's `"message"` fills it for that validator's code. Errors
    stay a code plus params.
18. **Values that do not decode** become `null`, as 0007 §2 says, and
    `snapshot.undecodable` lists them with their raw value, until the
    field gets a new value or is unregistered. A replacement with
    another codec tries the raw value again.
19. **A duplicated key throws when the form is registered**, not when
    `FormDef` is constructed as 0006 §1 says: `fields` is a getter a
    class overrides, so registration is the first point that sees the
    whole list.
20. **A path no field registers holds JSON**, in `change` as in
    `initialValues`, so a field that registers there later decodes it.
    An option whose value is neither JSON nor an enum needs `json:`.
21. **The JSON front door.** `FormCatalog.fromJson(json, types:,
    validators:, conditions:)` takes optional registries. A custom type
    registers a factory that receives a `FieldJson`: the common parts
    already read (key, label, conditions, typed validators, messages,
    the decoded initial value) and the raw map for the rest.
    `catalog.issues` lists what the tolerance rule skipped, as
    `CatalogIssue`s: where, what kind (unknown type, validator or
    operator, a cycle, a value or operand that does not decode) and why.
22. **A condition operand that does not decode** through the codec of
    the field it reads drops the whole condition, as an unknown operator
    does, and is listed in `issues`.
