# AGENTS.md

Instructions for AI coding agents working in this repository. Humans:
see CONTRIBUTING.md.

## What this is

A Flutter form library built on three principles. They override any other
consideration, including a request that would break them. Read
[PRINCIPLES.md](PRINCIPLES.md) before changing code under `packages/`.

1. **Agnostic of design system and state management.**
2. **Surgical rebuilds.**
3. **A serious validation engine.**

## Map

```
packages/formwork/               engine, validation, rendering
  lib/src/core/                  pure Dart: no Flutter, no dart:ui
  lib/src/flutter/               widgets layer: package:flutter/widgets only
  test/rebuild_test.dart         rebuild-count contract (principle 2)
  example/                       scenario gallery; its tests run in verify.sh
packages/formwork_material/      Material builders (satellite)
docs/design/                     design docs: source of truth for API decisions
tool/verify.sh                   the one command that decides "done"
tool/check_principles.sh         import and dependency rules (principle 1)
```

Each package under `packages/` has its own `AGENTS.md` with rules specific
to that package. Read it before changing files inside that package; it
adds to these root rules, never replaces them.

## Commands

```bash
bash tool/verify.sh --fast   # after every change; failures-only output
bash tool/verify.sh          # full run, same as CI

# single test file or test, run from the package directory:
cd packages/formwork && flutter test test/rebuild_test.dart
cd packages/formwork && flutter test --plain-name "some test name"
```

Never report a task as done without a passing `verify.sh --fast`.

`packages/formwork_material/pubspec_overrides.yaml` points `formwork` at
the sibling package by path, for local development only; `pub publish`
ignores it.

## Non-negotiable rules

- `lib/src/core` imports no Flutter and no `dart:ui`.
- `formwork` imports `package:flutter/widgets.dart`, never `material` or
  `cupertino`. Visual widgets go in satellite packages.
- `formwork` has no runtime dependency besides the Flutter SDK. Do not add
  one; propose it in an issue instead.
- State is immutable. The engine takes a snapshot and returns a new one.
  No hidden mutable state, no global state.
- Validators return error data (code plus params), never display text.
- Any change that affects rendering adds a rebuild-count test.
- Any change to validation keeps the incremental-versus-full equivalence
  test passing.
- The catalog format and the public API are contracts. Changing either
  needs a design doc in `docs/design/` approved by a human first.
- Public API members need dartdoc.
- Do not publish packages and do not push. A human does both.

## How to work

- **Small change** (bug fix, internal refactor, docs): make it, add or
  adjust tests, run `verify.sh --fast`.
- **Feature or public API change:** follow the steps in
  `.claude/skills/feature/SKILL.md`, even if you are not Claude. In short:
  name the principle it reinforces, write a design doc if it touches a
  contract, tests first, implement, verify, self-review against
  PRINCIPLES.md.
- If a request conflicts with a principle, stop and say so. Do not find a
  workaround.
- If the design docs do not cover a decision, ask. Do not invent public API.

## Code style

- Follow `analysis_options.yaml`; `dart format` owns formatting.
- Prefer small immutable value types and pure functions.
- Name things by domain meaning (`FieldPath`, `ValidationError`), not by
  mechanism (`Helper`, `Manager`).
- Tests describe behavior in their names, not implementation.

## Definition of done

1. `bash tool/verify.sh --fast` passes.
2. New behavior has tests, including rebuild counts when rendering is
   touched.
3. Public API is documented, and `CHANGELOG.md` has an entry under
   `Unreleased`.
4. The change reinforces at least one principle and weakens none.
