# 0007: Architecture: one engine, several front doors

Status: **accepted** (2026-09-25)

## Problem

formwork has to be easy in two very different situations:

- **Forms served as JSON.** This already works, and it is the package's
  differentiator.
- **Forms written in code, the Flutter way:** "everything is a widget",
  as in `flutter_form_builder` and `reactive_forms`.

The API study ("Formwork lado a lado") measured the second case against
the accepted API. The code was not longer, but the friction was higher:
- three places to touch for each new field;
- seven concepts before the first form;
- no way to customize one field without changing every field of its
  type.

A widget-first front door would remove most of that. It is **not** part
of this release. This doc makes sure the foundation does not rule it out,
and fixes what the study and a closer look at the foundation found:

1. **The engine assumes every field is known up front.** `FormEngine`
   receives its whole config when built, and builds its dependency index
   once. The accepted docs keep this premise: 0002 stage 2 uses fixed
   integer slots, and 0001 §5 detects cycles when `FormDef` is built. A
   widget-first form has fields that appear and disappear as widgets
   mount and unmount.
2. **JSON lives in the core.** `FormConfig.fromMap` sits next to the
   engine, so the server-driven path is the center of the package instead
   of one front door.
3. **Customization is per type.** The registry draws every field of a
   type the same way.
4. **A Dart backend cannot depend on formwork.** `packages/formwork`
   depends on the Flutter SDK in its `pubspec.yaml`, so a pure Dart
   server cannot `pub get` it, although `lib/src/core` imports no Flutter.
   "The same catalog validated in the app and on the server" cannot work
   today.

## Principles

- **Reinforces 1 (agnostic),** and widens it: agnostic of design system,
  of state management, and of how a form is defined. JSON, a class and,
  later, widgets are front doors to the same engine.
- **Reinforces 2 (rebuilds).** State and definitions are keyed by path in
  persistent structures. Registering or removing a field costs what that
  field touches, not the whole form.
- **Reinforces 3 (validation).** One engine and one set of rules,
  whatever the front door. The equivalence test extends to registration.
- **Risks.**
  - More packages to understand. Mitigation: `formwork` re-exports the
    core, so an app adds one dependency.
  - Registration adds engine paths (register, replace, unregister) that
    must stay correct; each gets tests.

## Decision

### 1. Three packages

```
formwork_core       pure Dart, no Flutter anywhere, including pubspec.yaml
  lib/src/engine    FieldDef<T>, Condition, Validator<T>, ValidationError,
                    codecs, FormEngine, FormSnapshot, FieldState
  lib/src/catalog   FormDef.fromJson, JSON type and validator registries,
                    the layout tree, tolerance, missingKeys, onlyMissing

formwork            Flutter, package:flutter/widgets only, nothing visual
                    FormController, per-field listenables, FormScope,
                    FieldView, FormView, SnapshotFormView, FieldRegistry,
                    LayoutRegistry, TextControllerBinding;
                    re-exports formwork_core

formwork_material   Material builders for the registry
```

- **Nothing in `src/engine` imports `src/catalog`** or the catalog
  library. `tool/check_principles.sh` enforces this, so JSON stays one
  front door.
- **`formwork_core` has no runtime dependency.** A Dart backend depends on
  it alone.
- **The widget-first front door needs no new package** later. Its
  primitive will live in `formwork`, and ready-made widgets in the kits.
- **Rejected splits:**
  - a separate `formwork_catalog`: a stricter boundary, one more
    dependency for every user;
  - one package with separate libraries: a backend cannot depend on a
    package that depends on the Flutter SDK.

**This changes project rules.** A human approves each change with this
doc:
- **PRINCIPLES.md §1 title:** "Agnostic of design system, state
  management, and of how forms are defined."
- **PRINCIPLES.md §1 "Forbids" and AGENTS.md:** "no runtime dependency
  besides the Flutter SDK" becomes "no runtime dependency besides the
  Flutter SDK and formwork's own packages". "`lib/src/core`" becomes
  "`formwork_core`".

### 2. Definitions live in the snapshot, and can be registered at runtime

The engine keeps no mutable state (AGENTS.md). If the set of fields can
change, it is state, so it moves into the snapshot, next to values and
errors:

```dart
const engine = FormEngine(); // rules only; no fields

var s = engine.initial(initialValues: data);
s = engine.registerAll(s, form.fields);            // a FormDef, or a catalog
s = engine.register(s, TextFieldDef('nickname'));  // one more, later
s = engine.unregister(s, FieldPath('nickname'));

// The common case keeps a one-liner:
final controller = FormController(form, initialValues: data);
```

- **A `FormDef` and a catalog are sources of definitions**, registered in
  a batch. Widgets will be a third source. The engine does not care which.
- **Order.** The snapshot keeps registration order:
  - `registerAll` keeps its list's order;
  - a later `register` appends;
  - replacing a definition keeps its position.

  The visible list and the payload follow this order. Keeping it is
  O(log n) per registration, with an order index in the persistent
  store. The visible list is built lazily, like the payload.
- **Active field.** A field is active when it is registered, its own
  `visibleWhen` passes, and every field up its chain is active. Only
  active fields validate and reach the payload.
- **Unregistering behaves like hiding, for everything that depends on the
  field.**
  - The value is kept, so a field that comes back finds it.
  - Its dependents become inactive, exactly as when it is hidden.
    Otherwise a condition would read a stale value nobody can see, which
    is 0003's chain bug in a new form.
  - The engine tells apart a path that was never registered (user data,
    judged by value as today) from a path that was registered and then
    removed (inactive).
- **Values arrive raw and are decoded at registration.** `initialValues`
  are stored as given, which is JSON for server data.
  - When a field registers, its codec decodes its raw value.
  - If there is no value, `FieldDef.initialValue` applies.
  - If a replacement definition has a different codec, the value is
    encoded with the old codec and decoded with the new one. A value
    that no longer decodes becomes `null`, and the engine reports it.
- **Replacing a definition** (a different, non-equal `FieldDef` for a
  path) keeps the value and position, and revalidates that field and its
  dependents only. `FieldState` carries the definition, so a replacement
  changes the field's state identity and reaches the views (see the 0004
  amendment).

### 3. When two definitions are "the same"

Re-registering must be cheap and must never be wrong:
- **Identity is the default.** The base `FieldDef` does not define `==`,
  so an unknown subclass (a `RatingFieldDef` with a `max`) is compared by
  identity. A new instance is treated as a replacement: correct, just not
  free. It can never silently keep an old definition.
- **Built-in definitions are `final` classes with value equality** over
  every parameter, with deep equality for their lists and maps (options,
  validators, `extra`). Built-in validators, conditions and codecs have
  value equality too. `matches(password)` compares the referenced field
  by path.
- **Custom subclasses opt in** by overriding `==` and `hashCode`. The
  dartdoc states the contract: every parameter must take part.
- **An equal re-registration returns the identical snapshot instance:** no
  change, no notification, no rebuild.

### 4. An incremental dependency graph, with tolerance

The reverse index of 0001 §5 (path → rules that read it) lives in the
snapshot, in a persistent structure. `register` adds a field's edges, and
`unregister` removes them.

**Cycles.** Adding edges can close a cycle, and detecting that walks what
the new edges can reach. The cost is O(reachable nodes), not only the
field's own edges.
- **Code path** (`register` called by the app): throws a `CycleError`
  naming the paths. A cycle written in code is a programmer error.
- **Catalog path:** follows the tolerance rule. The fields that close the
  cycle are skipped and reported, and the rest of the form works. This
  keeps today's behaviour (the engine tolerates cycles).

### 5. Storage keyed by path

Fixed slots (0002 stage 2) assume the full field set is known when the
engine is built. Per-field state, definitions and the graph therefore
live in a persistent hash trie keyed by `FieldPath` (HAMT):
- a change copies one root-to-leaf path, as the slot trie did;
- it adds hashing, collision nodes and bitmap-compressed nodes.

0002's targets still apply to the HAMT, and are re-committed here:
`change()` under 50 µs, and change plus frame under 4 ms, at 10,000
fields, plus the randomized store-versus-`Map` test.

Values for paths that were never registered (user data) stay in a plain
map, shared across snapshots, as 0002 decided.

### 6. Async results and server errors

- **Async results are tagged** with the field's registration generation,
  a counter in `FieldState` that moves on register and replace. A result
  for an older generation, or for an unregistered field, is discarded as
  stale. This is principle 3's race-free rule.
- **Server errors** for a path that is not registered are kept, and
  applied when the field registers. The snapshot lists them, so an app
  can show errors for fields that are not on screen. They do not
  block submit (see "Decided with acceptance").

### 7. `FieldView` in this release: a per-field `builder:`

`FieldView` (0006 §4) renders a registered field. It gains an optional
per-instance builder:

```dart
FieldView(form.cpf, builder: (context, props) => MyCpfInput(props, icon: ...))
```

This closes the customization gap the API study found. `FormView` renders
through `FieldView`.

**What does not ship now.** `FieldView` does not register on mount. The
0006 semantics stay as accepted:
- `fields` lists what is registered;
- a `FieldView` for a field not in the form is reported;
- a field mounted twice is reported, not thrown.

Registering from widgets needs answers that belong to the widget-first
doc:
- when to register during a frame;
- ownership and reference counts when a field is mounted twice;
- registration under `SnapshotFieldView` (Bloc, Riverpod);
- how `onlyMissing` interacts with widgets that register fields again.

The engine API above is what that doc will build on.

## Alternatives considered

- **Keep the engine static, and rebuild it whenever the field set
  changes.** O(fields) per change, and the graph is rebuilt from scratch.
  It fails principle 2 exactly where widget-first forms change most.
- **A mutable field registry inside the engine.** Simple, but it breaks
  the immutability rule: an old snapshot would refer to fields that no
  longer exist, and undo would break.
- **Ship register-on-mount now.** It would make `fields` optional today,
  but it pulls every widget-first question into this release.
- **Value equality on the base `FieldDef`.** Convenient, but subclasses
  that add parameters would compare equal when they are not.
- **Only widgets, dropping JSON.** Loses the differentiator.

## Impact

### Amends accepted docs

| Doc | What changes |
|---|---|
| 0001 | §3: `FormDef` is one source of definitions, registered in a batch. §5: the graph is incremental; cycles throw on the code path and are tolerated on the catalog path. §6: `FieldState` carries the definition and a registration generation. `fromJson` moves to the catalog library. |
| 0002 | Stage 2: a HAMT keyed by `FieldPath`, not fixed slots, with the same targets and randomized test. Lists: storage is settled by registration; the list UI is still decided with lists. |
| 0003 | `missingKeys` and `onlyMissing` move to the catalog library. |
| 0004 | `FormEngine(x)` becomes `const FormEngine()` plus `registerAll`. `FormController(form, initialValues:)` registers the batch. Cache contract: a definition can change under the same engine, and reaches views through `FieldState` identity. The "recipe library" is the catalog library. |
| 0005 | Unaffected. |
| 0006 | The layout tree and its parsing move to the catalog library. `FieldView` gains `builder:`. The `fieldState` listenables are keyed by path. Order comes from registration order, which `fields` sets. |

### Project rules and tooling

- **PRINCIPLES.md and AGENTS.md:** the rule changes in §1 of this
  decision. The missing-data recipe row follows the 0004 names when those
  land.
- **`tool/check_principles.sh`:**
  - the core rule points at `packages/formwork_core`;
  - the runtime-dependency rule allows formwork's own packages;
  - new rules: `formwork_core` has no Flutter in `pubspec.yaml` or in
    imports, and `src/engine` imports nothing from `src/catalog`.
- **`tool/hooks/guard_principles.dart`:** it hardcodes
  `packages/formwork/lib/src/core/`, and moves to the new path.
- **AGENTS files:**
  - the root map;
  - `packages/formwork/AGENTS.md`;
  - a new `packages/formwork_core/AGENTS.md`;
  - `.claude/agents/principles-reviewer.md`.
- **`tool/verify.sh`:** pure-Dart packages get their own branch, running
  `dart pub get`, `dart analyze` and `dart test`. The core tests are
  ported from `flutter_test` to `package:test`, which is a dev
  dependency only.
- **`pubspec_overrides.yaml`:** each package, and the example, override
  every sibling it uses:
  - `formwork` → `formwork_core`;
  - `formwork_material` → both;
  - the example → all three.
- **Publishing:** `formwork_core` first, and the three versions move in
  lockstep. Each package gets its own CHANGELOG, and the moved code keeps
  its history in the entries.

### Order

1. **The package split first.** It is mechanical: move the code, add the
   tooling above, port the core tests. No behaviour changes, and every
   test stays green.
2. **Then the foundation**, with runtime registration in the engine from
   the start.

### Tests, written first

- **Equivalence:** for acyclic input, registering fields one by one gives
  the same active set, values and errors as `registerAll`, in any order.
  The visible list and the payload follow registration order by design.
- **Re-registration:**
  - an equal built-in definition returns the identical snapshot;
  - a custom subclass without `==` is replaced;
  - a changed definition keeps the value and position, and revalidates
    only the field and its dependents.
- **Unregistering:**
  - the field leaves validation and the payload;
  - its dependents become inactive;
  - its value survives unregister and register again.
- **Codecs:** a raw JSON value in `initialValues` is decoded when the
  field registers; a replacement with another codec re-decodes, and
  reports a value it cannot decode.
- **Cycles:** a `CycleError` on the code path; skip and report on the
  catalog path.
- **Async:** a result for an old generation is discarded.
- **Server errors:** an error for an unregistered path is applied when the
  path registers.
- **Rebuilds:** registering or replacing one field rebuilds no other
  field. Form-level listeners are counted separately: they rebuild once
  per registration batch.
- **Performance:** the 0002 targets, and the randomized store test,
  against the HAMT.
- **Backend:** `formwork_core` passes its tests under `dart test`, without
  Flutter.

## Open questions

1. **Hot reload with custom validators created inline.** Every hot reload
   replaces them and revalidates the field. That is correct, but it could
   be noisy. The widget-first doc may compare validators by type and
   parameters.
2. **Package names.** `formwork_core` was free on pub.dev on 2026-09-24,
   as `formwork` and `formwork_material` were the day before. Check again
   right before the first publish.

## Decided with acceptance

1. **Server errors for paths that never register** are shown, and do not
   block submit. The user has no field on screen to fix them, so blocking
   would be a dead end, and the server rejects the payload again anyway.
   The snapshot keeps listing them, so an app that wants to block can do
   it in its own submit handler.
2. **The two rule changes of §1** (the title of principle 1, and
   dependencies between formwork's own packages) are approved. They land
   in PRINCIPLES.md, AGENTS.md and the tooling with the package split,
   once `formwork_core` exists.
