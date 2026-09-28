# formwork_material

Material Design field builders for [formwork](../formwork).

```dart
final registry = materialFieldRegistry();
FormView(controller: controller, registry: registry);
```

Covers `text`, `email`, `password`, `number`, `dropdown` and `checkbox`.
Use it as-is, or as a reference when writing builders for your own design
system.
