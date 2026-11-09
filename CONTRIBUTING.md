<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Contributing

Thanks for wanting to help flatten some castles.

## Getting set up

```bash
make dev    # bootstrap: distro packages, pinned Godot, linters, GUT
make run    # play
make editor # open the Godot editor
```

The Godot project lives in `game/`. Always use the pinned engine
(`scripts/godot.sh` or `make editor`). Other versions may rewrite scene files
and produce noisy diffs.

## Before you open a pull request

```bash
make lint   # shellcheck, gdlint + gdformat --check, data schemas, REUSE, identity
make test   # unit tests, script tests, smoke test
```

CI runs the same targets on every push.

## Code style

* **GDScript, statically typed everywhere.** Declare types on every
  variable, parameter and return. `:=` is fine when the type is obvious.
  Untyped declarations are compile errors in this project.
* Format with `make fmt` (gdformat). Lint is `gdlint` with `gdlintrc`.
* Behaviour lives in scripts and **content lives in data**: levels, ammo,
  materials and realms are JSON under `game/data/` with schemas in
  `game/data/schemas/`. Don't hard-code tuning numbers or level content in
  scripts.
* Every user-visible string goes through `tr()`. Add new strings to
  `game/locale/en.po` (or run `make pot` once it exists).
* Platform-specific code goes behind `OS.has_feature("ios")` etc.
* Shell scripts are bash, must pass shellcheck, and need `--help`,
  `--dry-run`, clear error messages and idempotent behaviour.

## Licensing (REUSE)

* New code files start with an SPDX header:
  ```
  # SPDX-FileCopyrightText: 2026 Siegefall contributors
  # SPDX-License-Identifier: MIT
  ```
* Original art, audio, levels and docs are `CC-BY-SA-4.0`.
* **Third-party assets** must be CC0, CC-BY, CC-BY-SA or OFL. Add each one to
  `CREDITS.md` (author, source URL, licence), give it a licence header or a
  `REUSE.toml` entry, and make sure `reuse lint` passes.
* Nothing from *Crush the Castle* or *Castle Clout*: no names, art, sounds,
  characters or level layouts.

## Commits

Small, focused commits with imperative subjects ("Add frost flask ammo").
Explain *why* in the body when it's not obvious. Work on a feature branch.

## Adding levels

See [docs/LEVEL_FORMAT.md](docs/LEVEL_FORMAT.md).

1. Write the castle as a function in `tools/levels/build_levels.py` (or build
   it in the in-game castle editor and export the JSON into
   `game/data/levels/<realm>/`), and list it in the realm file.
2. `make levels` regenerates the JSON from the builder.
3. `make check-levels` makes sure the castle stands still on its own.
4. `make validate-levels` lets the bot find solutions and set par (all CPU
   cores; a few minutes for the whole campaign).
5. Play it. The bot proves a level is *possible*; only you can tell whether
   it is *fun*.
