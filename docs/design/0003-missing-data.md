# 0003: Missing data: what is missing, and whether to hide the rest

Status: **draft**

## Problem

`missingFields` does two different jobs at once:

1. **Logic:** find what this user still has to answer.
2. **UX:** hide every field that is already filled.

Two problems follow.

**Hiding is not optional.** Some apps want only the missing questions.
Others want the whole form with the missing fields highlighted, or the
known answers shown read-only for review. Today the second group has to
misuse `missingFields` to get the keys and rebuild the full form around
it. Nothing documents that.

**Hiding breaks chains.** A catalog served by an insurer:

```
hasVehicle   dropdown yes/no            required
vehicleType  dropdown car/motorbike     visible when hasVehicle == 'yes'
licensePlate text                       visible when vehicleType == 'car'
```

Stored data: `{vehicleType: 'car'}`.
- `hasVehicle` was cleared for a yearly re-confirmation.
- `licensePlate` is new in the catalog.

`missingFields` asks `hasVehicle` and `licensePlate`, and hides
`vehicleType`, which is known. The engine only receives the narrowed form.
It judges `licensePlate`'s rule by the stored `'car'` and never learns
that `vehicleType` depends on `hasVehicle`. The user answers "no", the
plate stays visible and required, and submit is blocked.

The root must be a yes/no choice, not a checkbox. A required checkbox
counts `false` as empty (`isEmptyValue`), so "no" could never be
submitted anyway.

The skipped test "a chain stays connected when missingFields drops its
middle link" (`packages/formwork/test/core_test.dart`) reproduces the
chain problem. It uses a required checkbox root, so it is rewritten with
a yes/no root (see Impact).

The bug exists only when filled fields are hidden. With the whole form on
screen, the engine sees every chain.

## Principles

- **Reinforces 1 (agnostic).** Whether filled answers are hidden,
  highlighted or shown read-only is a UX decision. It belongs to the app,
  not to the library.
- **Reinforces 3 (validation).** A form whose correct answer cannot be
  submitted is a validation failure.
- **Neutral on 2 (rebuilds).** It runs once, before the engine, in
  O(fields × chain depth). Rendering does not change.
- **Simplicity.** No new types, no flags, no discarded values. The
  existing function keeps its signature.

## Decision

### Still a recipe

PRINCIPLES.md ("Show only missing fields → Recipe built on the engine")
and 0001 ("`missingFields` becomes a recipe") keep missing data out of
the engine. This doc keeps that:

- both functions are built only on the public API (`FieldConfig`,
  `ValidatorRegistry`);
- neither is a member of `FormEngine` or `FormSnapshot`;
- the engine never learns that a form was narrowed.

Proposed wording for that PRINCIPLES.md row: "Recipe built on the
engine's public API (`missingKeys`, `missingFields`)". A human decides.

### Two functions

Split the two jobs, and let the app choose one:

```dart
/// The keys still to be answered. Hides nothing.
Set<String> missingKeys(
  FormConfig catalog,
  Map<String, Object?> data, {
  ValidatorRegistry? validators,
});

/// Only the missing questions: the catalog narrowed to [missingKeys],
/// plus the links that keep chains whole.
FormConfig missingFields(
  FormConfig catalog,
  Map<String, Object?> data, {
  ValidatorRegistry? validators,
});
```

This ships on today's names. 0004 renames both later, together with 0001.

### `missingKeys`

It returns the keys whose stored value fails the field's rules and that
are relevant for this user. This is exactly today's `missingFields`
selection, returned as keys, without links.

A property the link rule relies on: when a key is missing and relevant,
every missing field above it in its chain is in `missingKeys` too.
`relevant` recurses through every controller.

### `missingFields`: links between missing keys

**Rule, in closed form.** A known field K is added when its `visibleWhen`
chain has a missing key **above** K and a missing key **below** K.

- **Result:** `missingKeys` plus those links, in **catalog order**.
- **Order independent.** Values never change, so relevance never changes,
  and the rule only reads the chains.
- **Algorithm:** for each missing key, walk up its chain. If a missing key
  is found above, add every known field in between.
  - Stopping at the nearest missing ancestor or the farthest one gives the
    same union.
  - The walk stops at a field already seen, so cycles terminate.
- **Known chains stay hidden.** A known field with nothing missing above
  it is not added. With `{hasVehicle: 'yes', vehicleType: 'car'}` stored,
  only `licensePlate` is asked. That is safe, because nothing on screen
  can change the fields above it.

**Prefilled, as long as the caller passes the data.** A `FormConfig`
carries no values. A link shows its stored value only when the same
`data` reaches the engine (`FormEngine.initial` or the controller's
`initialData`), as the README already shows. Without it, the link shows
up empty, which is still correct, only less convenient.

**João's case.** The form becomes `[hasVehicle, vehicleType,
licensePlate]`, with the stored data passed to the controller.
- He answers "no": the type and the plate disappear, and submit returns
  a payload.
- He answers "yes": "Type: Car" appears prefilled, and he can keep it or
  change it.

### Recipe: highlight what is missing

With the whole form on screen, the builder decides how a missing field
looks. The app captures the set when it builds its registry:

```dart
final missing = missingKeys(catalog, data);
final registry = FieldRegistry()
  ..register('text', (context, field, ctx) => missing.contains(field.key)
      ? HighlightedText(field, ctx)
      : PlainText(field, ctx));
```

- **The set is fixed for the session.** It describes the stored data, not
  the live form, so the per-field cache stays correct without comparing
  it. An app that wants the highlight to change as the user types is
  asking for per-field state, which is `FieldContext`'s job.
- **This does not break PRINCIPLES.md §1** ("everything a field needs to
  render arrives through `FieldContext`"). That rule constrains the
  library. App data captured in a closure is the app's own business, like
  a theme.

## Alternatives considered

- **Reset the link: ask it again, empty.** It never submits an old answer
  as a new one. Lost on complexity:
  - `missingFields` would have to tell the caller which stored values to
    drop, so it needs a new result type and a breaking change;
  - dropping a value changes the relevance of other fields, so the
    selection becomes a fixpoint;
  - it opens payload questions (should a dropped value be sent as
    `null`?).

  Prefilled, the old answer is visible on screen, not hidden, and the
  server stays the final authority. Revisit if a real flow needs reset.
- **Prefilled but "unconfirmed"**, with submit blocked until the user
  confirms each one. It keeps reset's safety without the retyping. Lost
  for now: it needs a new per-field state in the engine and in
  `FieldContext`. It is the natural next step if prefill proves unsafe.
- **A flag on `missingFields`** (`hideKnown: false`). Lost: one name for
  two behaviours. Two functions with honest names are simpler to read and
  to test.
- **Missing state in `FieldContext`** for the highlight recipe. Lost for
  now: the set is static per session, and a closure is enough. Revisit if
  the highlight has to be live.
- **Give the engine the full catalog for its rules** (0001 §5). It is the
  right long-term engine model, but the hidden `vehicleType` would still
  keep `'car'` and be impossible to change.
- **Document it as a limitation.** Lost: it breaks submit in the main
  server-driven flow.

## Impact

- **No breaking change.** `missingFields` keeps its signature;
  `missingKeys` is new.
- **Behaviour change:** in a rare case, `missingFields` returns a field
  whose value is already known. CHANGELOG entry under Unreleased.
- **README:**
  - Quick start shows the whole form, prefilled with the user's data;
  - two recipes: "Ask only what is missing" (`missingFields`) and
    "Highlight what is missing" (`missingKeys` and a builder).
- **Example:**
  - Profile completion gets a "Renewal" preset (João's case, yes/no root);
  - a toggle between the two modes.
- **PRINCIPLES.md:** the recipe row, if a human accepts the wording above.
- **Tests, written first:**
  - the skipped middle-link test, rewritten with a required yes/no root:
    after "no", only the root is visible and `submit().payload` is not
    null;
  - `missingKeys` equals today's selection over the existing cases, and
    never contains links;
  - a link is added only between two missing keys: a known root above a
    missing leaf is not added;
  - a link shows its stored value when it becomes visible, given the same
    data;
  - catalog order independence: the reverse catalog gives the same keys,
    and the result stays in catalog order;
  - two consecutive links between two missing keys;
  - a cycle terminates.

## Open questions

1. **Multi-field conditions (0001 §4).** The rule is defined on chains.
   With `all`/`any`, a field reads several others and chains become a
   graph. The natural reading: add K if some path in the graph runs from a
   missing key, through K, to another missing key. This must be settled
   before the release that bundles 0001 and 0004, or the renamed function
   ships with undefined behaviour.
2. **Stale data on the server.** João answers "no". `vehicleType` is
   hidden, so it is not in the payload, and the server still holds
   `'car'`. The same happens with any field hidden on screen, so this is
   the general question of whether hidden fields should be cleared, not
   specific to this doc.
