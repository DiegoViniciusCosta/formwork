## Unreleased

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
