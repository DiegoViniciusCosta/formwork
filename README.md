# formwork

**Server-driven forms for Flutter, in your own design system.**

formwork renders the forms your server describes in JSON with your own
components, under any state management; asks a known user only what is
still missing; and validates the same catalog in a Dart backend. See the
[`formwork` README](packages/formwork/README.md) for why, and when not to
use it.

It is built on three principles:

1. **Agnostic of design system, state management, and of how forms are
   defined.**
2. **Surgical rebuilds.**
3. **A serious validation engine.**

See [PRINCIPLES.md](PRINCIPLES.md) for what each one means and how it is
enforced.

| Package                                         | What it is                          |
|-------------------------------------------------|-------------------------------------|
| [`formwork`](packages/formwork)                 | Rendering; re-exports the engine    |
| [`formwork_core`](packages/formwork_core)       | Engine and validation, pure Dart    |
| [`formwork_material`](packages/formwork_material) | Material field and layout builders |

Design documents live in [`docs/design`](docs/design).
