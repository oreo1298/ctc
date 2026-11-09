<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Milestone 0 foundations: design document, single-source app identity
  (`app.env`), pinned Godot 4.7.2-stable with SHA-512 verification
  (`toolchain.lock`), `scripts/bootstrap.sh` for pacman/apt/dnf/zypper/xbps/
  emerge/NixOS with immutable-distro guidance, Makefile, CI skeleton,
  REUSE-compliant licensing (MIT code, CC BY-SA 4.0 assets).
- Boot scene with a `--smoke-test` mode, first GUT unit tests guarding
  engine settings.
- Milestone 1: physics benchmark (Godot Physics 2D vs godot-rapier 2D);
  Rapier chosen and pinned. Vertical slice: data-driven level loading
  (JSON + schemas), analytic two-tap trebuchet with swing gauge and ghost
  trail, boulder ammo, wood and stone blocks with impact damage and cracks,
  king and knight with slapstick eliminations and flying headgear, camera
  intro/follow/collapse framing, medals with a wax-seal win card, versioned
  atomic saves, storybook backdrop (painted sky, parallax hills and trees),
  normal-mapped procedural block shading, OFL fonts, screenshot harness,
  gettext catalogue extraction, unit tests for trebuchet determinism,
  scoring, level parsing, saves and geometry.
- Milestone 2: runtime Voronoi fracture (benchmarked against pre-broken
  shards) with a style per material, debris budget and cleanup, impact
  marks, iron sparks and dents, fire (burning, spreading, charring) and
  frost (brittle) states, material-specific particles, lingering dust,
  collapse-following camera, dotted ghost trail, deterministic slow motion,
  haptics, and 77 procedurally synthesised sound effects. Royals and
  knights are much easier to knock out and can be crushed.

- Milestone 3: eight ammo types with mid-air actions (scatter-stones,
  iron ball, powder keg, firepot, chain shot, frost flask, void flask);
  Saffron Reach and Frostfang Peaks realms (mesas, cacti, sand; peaks,
  snowy pines, snow, aurora); 36 campaign levels written with a level
  builder; validator bot (search, replay, stability) that proves every
  level beatable and sets par, with CI replay; level select with medals,
  sequential unlocks and realm unlocks; settings (gameplay, accessibility,
  sound, video, remappable controls); one-button mode; grievance banner;
  progression and rebinding tests.
- Milestone 4: castle editor. Palette of shapes, materials and people;
  settle-on-drop placement and stacking; select, drag, turn, resize, copy,
  delete, anchors; ground tool for terrain points; castle settings (name,
  grievance, sky, scenery, ground, width); undo/redo; overlap and
  world-edge warnings; mouse, touch, trackpad and keyboard controls.
  Test-play with *Edit castle* to return; beating your castle sets its
  par. Castles autosave to `user://levels`; share as an `SF1.` code
  (author's par included) or a `.json` file; imports never overwrite.
  Editor toolbar icons.
- Milestone 5: headless exports for Linux x86_64/arm64 and Windows
  (`make build`); packages from one staged layout (`make package`):
  portable tarball, AppImage (pinned type2 runtime), deb, rpm, Flatpak
  manifest and bundle, AUR `siegefall-bin` and `siegefall` (from source),
  Nix flake package (from source), Windows zip and per-user NSIS
  installer. `scripts/install.sh` / `uninstall.sh` (per-user or system,
  manifest-tracked, safe to re-run, `--purge` asks first), man page,
  icons rendered by Godot, third-party notices generated from the engine.
  Tested by installing and starting each package on Arch, Ubuntu, Debian,
  Fedora, Tumbleweed, Void, Linux arm64, Flatpak, Nix and Windows in CI.

### Fixed
- Installing godot-rapier into a fresh clone (the addons folder did not
  exist yet) now works, and any failure stops instead of reporting success.
- `make dev` exited silently on interactive runs (no `--yes`); optional
  packages are now filtered by availability and installed in one visible
  call.
- Simulation was not reproducible between runs (global RNG in headgear
  props); slow motion could shift body removal. Both fixed and tested.
