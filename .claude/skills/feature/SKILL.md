---
name: feature
description: Workflow for adding a feature or changing public API in formwork. Use for any new capability, new public class or method, catalog format change, or behavior change visible to library users. Not needed for internal refactors or bug fixes.
---

# Adding a feature

Follow the steps in order. Do not skip ahead.

## 1. Pass the filter

State in one sentence which principle in `PRINCIPLES.md` the feature
reinforces, and confirm it weakens none.

If it reinforces none, stop. Propose instead a satellite package, a recipe
in the docs, or dropping it, and wait for the human.

## 2. Design first, if it touches a contract

If the feature changes the catalog format or the public API, use the
`design-doc` skill, then **stop and wait for human approval** before
writing code. Check `docs/design/` first: a decision may already exist.

## 3. Tests first

Write failing tests that describe the behavior:

- behavior tests for the feature itself;
- a rebuild-count test in `test/rebuild_test.dart` if rendering is
  affected (principle 2);
- an equivalence or race test if validation is affected (principle 3).

## 4. Implement

Smallest change that makes the tests pass. Engine logic goes in
`formwork_core` (`lib/src/engine`, or `lib/src/catalog` for what only JSON
catalogs need); `formwork/lib/src/flutter` only adapts it.

## 5. Verify

Run `bash tool/verify.sh --fast` until it passes.

## 6. Self-review

Delegate to the `principles-reviewer` subagent. Fix every FAIL.

## 7. Record

- dartdoc on every new public member;
- an entry under `## Unreleased` in the package's `CHANGELOG.md`;
- README update if user-facing usage changed.

Finish with a short summary: what changed, which principle it reinforces,
and anything the human must decide.
