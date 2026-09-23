# 0002: Per-change cost independent of form size

Status: **draft**

## Problem

PRINCIPLES.md §2 says engine work is "proportional to the affected fields,
never to the size of the form". Today it is proportional to the form.

Typing one character in one field (`FormEngine.change`) makes four full
copies:

```dart
final values = Map.unmodifiable({...s.values, key: value}); // 2 copies
final errors = {...s.errors};                               // 1 copy
errors: Map.unmodifiable(errors),                           // 1 copy
```

`Map.unmodifiable` copies; it is not a view. Validation itself is already
incremental: only the changed field and its dependents are revalidated.

The view has the same shape. `DynamicFormView.build` visits every visible
field to check its cache, and the `Column` diffs every child. The per-field
cache prevents *rebuilds*, so `rebuild_test.dart` passes, but not the
*visit*.

Measured cost of one change, flat form, all fields required, before
stage 1 (`flutter test`, JIT, Apple Silicon; compare rows, not absolute
values):

| Fields | `change()` | change + frame |
|-------:|-----------:|---------------:|
| 100    | 0.02 ms    | 0.5 ms         |
| 1,000  | 0.18 ms    | 1.9 ms         |
| 10,000 | 2.9 ms     | **23 ms**      |

Nearly all of the `change()` cost is the map copies: copying the same maps
outside the engine takes the same time. At 10,000 fields a keystroke
misses the 16 ms frame budget, and most of the frame is the view, not the
engine. No existing test can catch this: rebuild counts stay at 1.

## Principles

- **Reinforces 2 (surgical rebuilds).** It makes the stated rule true for
  the engine and the view, not only for widget rebuilds.
- **Risk to 1 (agnostic).** The persistent structure must be written in
  `formwork`, because the package takes no runtime dependencies. The
  adapter change in stage 3 must keep working for Bloc and Riverpod users,
  not only `DynamicFormController`.
- **Risk to 3 (validation).** A new store is a new place for incremental
  and full paths to disagree. The equivalence test must run over the new
  store unchanged.
- **Immutability rule: kept.** A persistent structure is immutable; old
  snapshots stay valid, so undo and time travel keep working.

## Decision

Three stages. Each one ships alone and is measured before the next.

**Stage 1: stop the needless copies (internal, no API change).**
- Build the new map once and wrap it in `UnmodifiableMapView` instead of
  copying again with `Map.unmodifiable`.
- Reuse the previous `errors` map when no recomputed error changed, which
  is the common case of typing in a valid field.

Implemented ahead of this doc's acceptance, because it is internal and
changes no API. Measured `change()` before and after, same benchmark:

| Fields | typing, before | typing, after | error changes, before | error changes, after |
|-------:|---------------:|--------------:|----------------------:|---------------------:|
| 100    | 22 µs          | 7.6 µs        | 21 µs                 | 11 µs                |
| 1,000  | 184 µs         | 47 µs         | 185 µs                | 90 µs                |
| 10,000 | 2.9 ms         | 0.69 ms       | 2.9 ms                | 1.46 ms              |

About 4x faster when errors do not change (the common keystroke) and 2x
when one does. Still O(n): one copy of `values` per change remains. The
frame at 10,000 fields went from 23 ms to 21 ms, because the view
dominates.

**Stage 2: a persistent field store (internal to the engine).**

The fields of a form are known when `FormEngine` is built, so each field
gets a fixed integer slot. Per-field state lives in a persistent vector: a
32-way trie indexed by slot. Updating one slot copies only the nodes on the
path from root to leaf, which is 2 to 4 arrays of 32 for any realistic
form. Every other node is shared with the previous snapshot.

```dart
// Shape only. Internal: not exported.
final class FieldStore {
  FieldState operator [](int slot);   // O(log32 n), in practice 2-4 hops
  FieldStore set(int slot, FieldState s); // copies one root-to-leaf path
}
```

- This is the storage behind 0001 §6. Unchanged `FieldState`s are shared
  for free, and `changedPaths` is the list of slots that `set` touched.
- Values for keys outside the form (user data used by visibility rules)
  stay in a plain map. It is shared as-is and copied only when one of those
  keys changes.
- `isValid` reads an error count maintained incrementally, instead of
  `errors.isEmpty`.
- `FormSnapshot.values` and `errors` become lazy, read-only `Map` views
  over the store, so current callers keep working.

Prototype measured against today's copy (`set` of one slot):

| Fields  | `Map.unmodifiable({...})` | `UnmodifiableMapView({...})` | trie `set` |
|--------:|--------------------------:|-----------------------------:|-----------:|
| 100     | 10.9 µs                   | 4.7 µs                       | 0.6 µs     |
| 1,000   | 90.8 µs                   | 45.4 µs                      | 0.2 µs     |
| 10,000  | 1,475 µs                  | 792 µs                       | 0.4 µs     |
| 100,000 | 17,720 µs                 | 8,943 µs                     | 1.1 µs     |

**Stage 3: a view that visits only what changed.**
- The controller notifies per field, using `changedPaths`, instead of
  notifying the whole form.
- Each field widget listens to its own slot.
- The parent `Column` rebuilds only when the visible list changes.
- For Bloc and Riverpod, the same `changedPaths` drives `BlocSelector` or
  `select` per field.

## Alternatives considered

- **Keep copying and document a size limit.** Lost: it contradicts §2 as
  written, and the limit (a few thousand fields) is reachable by generated
  and server-driven forms, which are this library's main use case.
- **`built_collection`.** Lost twice: it is a dependency, and
  `BuiltMap.rebuild` copies the whole map. It gives immutability, not
  structural sharing.
- **`fast_immutable_collections` or `dartz`.** They provide persistent
  collections. Lost only on the no-dependency rule. Worth reading as
  references.
- **HAMT keyed by field path** (Clojure's `PersistentHashMap`). It supports
  keys that are not known in advance, at the cost of hashing, collision
  nodes and bitmap-compressed nodes. Lost for now: slots are known at build
  time, so the simpler index trie is enough. Revisit with lists (open
  question 1).
- **Two-level chunked copy-on-write** (a top array of 32-slot chunks).
  Simpler, but a change still copies n/32 entries, so the cost still grows
  with the form. The trie is only slightly more code.
- **Mutable store with a version counter.** Constant-time and trivial, but
  it breaks the immutability rule: an old snapshot would change under its
  holder, and undo would break. Rejected outright.

## Impact

- **Stage 1:** no API change. Tested: after a change that leaves errors
  intact, `identical(previous.errors, next.errors)`; snapshot maps stay
  read-only; a change never alters the previous snapshot.
- **Stage 2:** no API change while the snapshot keeps `Map` views.
  - Reading a value becomes a 2 to 4 hop lookup instead of a hash lookup.
  - A change allocates about 3 × 32 slots instead of n entries.
  - Tests:
    - unit tests for the store;
    - a randomized test comparing it to a plain `Map` over thousands of
      operations;
    - the equivalence test, unchanged.
- **Stage 3:** touches `DynamicFormController` and `DynamicFormView`. It
  needs rebuild tests that also count *visits*, not only builds.
- **Engine work counts** ("Planned" in PRINCIPLES.md §2): add a counter
  test asserting that one change on a 10,000-field form does the same
  validator calls and slot writes as on a 10-field form. Timing
  benchmarks go to `tool/bench/`, outside CI, because CI timing is too
  noisy to gate on.

## Open questions

1. **Repeatable lists (0001 §1).** Items add and remove fields at runtime,
   so slots are no longer fixed. Options:
   - append to the vector and leave holes for removed items;
   - one sub-store per list;
   - switch to a HAMT keyed by `FieldPath`.

   To be decided together with lists.
2. **Snapshot surface.** Keep `Map` views, or expose only `FieldState`
   accessors as 0001 §6 proposes. Views are compatible; accessors are
   cheaper and harder to misuse.
3. **Targets.** Proposed: `change()` under 50 µs and change + frame under
   4 ms at 10,000 fields, measured in profile mode on a mid-range device.
   Needs agreement.
4. **Stage 3 notification cost.** A `ChangeNotifier` calls every listener,
   so n listeners still means n calls per change. Per-field notification
   needs a keyed listener registry. Its shape is not designed here.
