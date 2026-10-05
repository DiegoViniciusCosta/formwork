# formwork_material

**Material Design fields and layout for [formwork](../formwork), ready to
use.**

Render a formwork catalog with Material components in one line, and see
results before you write a single builder of your own:

```dart
FormView(
  controller: controller,
  registry: materialFieldRegistry(),
  layouts: materialLayoutRegistry(), // sections and rows from the catalog
);
```

Covers `text`, `email`, `password`, `number`, `dropdown` and `checkbox`.
Builders follow your app's `ThemeData`, keep the cursor in place while
the form rebuilds around it, and show errors through your
`ErrorLocalizer`.

## Mix it with your own

The registry is open. Keep the Material builders for common fields and
register your own for the rest:

```dart
final registry = materialFieldRegistry()
  ..register('taxId', (context, field) => MyTaxIdInput(field));
```

Building for your own design system? These builders are short, and a
good reference: see [Custom fields](../formwork/README.md#custom-fields).
