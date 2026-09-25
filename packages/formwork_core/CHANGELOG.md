## Unreleased

- New package: the formwork engine in pure Dart, split out of `formwork`
  (design doc 0007). A Dart backend can depend on it alone to validate
  the same catalogs as the app. It holds field catalog parsing,
  validators, `missingFields`, `missingKeys` and `FormEngine`; their
  history is in the `formwork` changelog, up to its 0.1.0 and its
  Unreleased entries before this split.
- An example: a Dart backend validating a submitted payload against the
  same catalog the app renders.
