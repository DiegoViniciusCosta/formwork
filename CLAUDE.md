@AGENTS.md

## Claude Code specifics

- **Hooks are active** (`.claude/settings.json`):
  - a principle guard blocks edits that would import Flutter into the core
    or Material/Cupertino into `formwork`. If it blocks you, change the
    design; do not work around it;
  - Dart files are formatted after every edit;
  - when you stop, `verify.sh --fast` runs if Dart code changed, and its
    failures come back to you.
- **Skills:** use `feature` for any new feature or public API change, and
  `design-doc` to write a design document.
- **Subagent:** delegate to `principles-reviewer` before finishing any
  change under `packages/`. It reviews the diff in its own context and
  reports per principle.
