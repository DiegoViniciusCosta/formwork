# Agent harness

This repository is built to be worked on by AI coding agents as well as
humans. The harness has three layers, each stricter than the last:

| Layer          | Where                                  | Nature        |
|----------------|----------------------------------------|---------------|
| Instructions   | `AGENTS.md`, `CLAUDE.md`, skills       | guides        |
| Local gates    | `.claude/settings.json` hooks          | enforces      |
| Final gate     | CI running `tool/verify.sh`            | enforces      |

Two rules keep it coherent:

- **One verification command.** Humans, hooks and CI all run
  `tool/verify.sh`. There is no check that exists in one place and not the
  others.
- **Deterministic gates over instructions.** When a rule matters, it is a
  script, not a sentence. Instructions explain the why; scripts guarantee
  the what. `check_principles.sh` and the principle guard hook enforce
  principle 1; `rebuild_test.dart` enforces principle 2.

`AGENTS.md` is the vendor-neutral source of truth. `CLAUDE.md` imports it
and only adds Claude Code specifics, so other agents read the same rules.

Hooks are written in Dart so they run on every platform a Flutter developer
uses, without extra tools like `jq`.
