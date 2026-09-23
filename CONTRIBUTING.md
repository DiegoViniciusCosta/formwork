# Contributing

- Read [PRINCIPLES.md](PRINCIPLES.md) first. A proposal must say which
  principle it reinforces; if it reinforces none, it does not enter the core.
- Open an issue before large changes, especially anything touching the
  catalog format: it is a public contract.
- Changes that affect rendering must add a rebuild-count test.
- Before pushing, from the repository root: `bash tool/verify.sh`
  (the same command CI runs; `--fast` for the local loop).
- Working with an AI agent? See [docs/harness.md](docs/harness.md).
