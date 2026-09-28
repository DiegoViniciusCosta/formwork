## Unreleased

- Catalogs read into typed definitions (decisions 21 and 22 of design
  doc 0001), internal until `formwork` switches to the new engine:
  `FormCatalog.fromJson` with optional `FieldTypeRegistry`,
  `ValidatorRegistry` and `ConditionRegistry`. Condition operands decode
  through the codec of the field they read, whatever the field order.
  Unknown types, validators and operators, values and operands that do
  not decode, and fields that would close a cycle are skipped and listed
  in `issues`. `ConditionRegistry.decode` gains `decodeOperand:` and
  `unknown:`.
- Forms in code (design docs 0001 §3 and 0006 §1 to §3, decisions 14 to
  20):
  - `TextFieldDef`, `NumberFieldDef`, `ChoiceFieldDef<T>` with `Option`,
    and `BoolFieldDef`, with the catalog types `text`, `number`,
    `dropdown` and `checkbox`. They compare by value.
  - `FormDef`: a form as a class whose fields are members, or built from
    a list. A duplicated key throws when the form is registered.
  - Conditions from fields: `equals` and `isIn`, and on number fields
    `greaterThan`, `greaterThanOrEqualTo`, `lessThan` and
    `lessThanOrEqualTo`. A string on an enum field does not compile.
  - Validators `minLength`, `maxLength`, `pattern`, `email`, `min`, `max`
    and `matches`, typed: `min(1000)` on a text field does not compile.
  - `FieldCodec<T>`: a field whose type is not JSON needs one, or
    building it throws. Initial values are decoded when their field
    registers, the payload is encoded, and values that do not decode are
    listed in `undecodable`. A value set on a path no field registers is
    JSON, like an initial value.
  - `FieldDef.messages`: per-field text overrides by error code.
- `FieldDef<T>` and `Validator<T>` (design doc 0001 §3, decisions 9 and
  12): the typed definition of a field, and rules that return error data
  and declare the other paths they read. `FieldState` now carries its
  `def`, which its constructor requires.
- A new engine, internal until `formwork` switches to it (design docs
  0001, 0002 and 0007): fields register and unregister at runtime, state
  lives per path in a persistent trie, and a change recomputes only the
  fields whose rules read it. One change costs about 1 µs at 10,000
  fields, against 0.69 ms before (`tool/bench/change_bench.dart`).
- `CycleError` (design docs 0001 §5 and 0007 §4): names the fields whose
  conditions read each other. Only conditions take part in cycles; two
  cross-field validators that read each other are allowed. Thrown by the
  engine's registration from step 3c on.
- Conditions (design doc 0001, step 2), not used by the engine yet:
  - `Condition`: a rule over the form's values, as a tree of data that
    lists the paths it reads and compares by value. Built with `eq`,
    `ne`, `isIn` (`in` in JSON), `gt`, `gte`, `lt`, `lte`, `empty`, `all`,
    `any` and `not`. `empty` counts what `required` counts as empty;
  - `ConditionRegistry`: decodes JSON conditions and takes custom
    operators. An unknown operator drops the whole condition and is
    reported, so the field behaves as if it had no such rule.
- Fix: an empty map now counts as empty for `required`, as an empty list
  already did. Sets inside `ValidationError.params` compare correctly in
  both directions.
- Foundation data types (design doc 0001, step 1), not used by the engine
  yet:
  - `FieldPath`: a field's address, with groups (`address.zipCode`) and
    list items by stable id (`dependents[#k3f9].name`) or, when
    serialized, by index (`dependents[0].name`). A key is any non-empty
    text without `.`, `[` or `]`;
  - `ValidationError` and `ErrorSource`: errors as a code plus params,
    immutable and compared by value;
  - `FieldState`: one field's state, compared by identity.
- New package: the formwork engine in pure Dart, split out of `formwork`
  (design doc 0007). A Dart backend can depend on it alone to validate
  the same catalogs as the app. It holds field catalog parsing,
  validators, `missingFields`, `missingKeys` and `FormEngine`; their
  history is in the `formwork` changelog, up to its 0.1.0 and its
  Unreleased entries before this split.
- An example: a Dart backend validating a submitted payload against the
  same catalog the app renders.
