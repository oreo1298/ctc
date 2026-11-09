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
- Press again after a shot to go straight back to the trebuchet and load
  the next one (the ammo's mid-air trick still comes first). A quick double
  tap right after letting go is ignored, so a shot is never thrown away.
  The first shot of a level ends with a tip about it.
- A proper pause menu: Resume, Restart, Choose level (Edit castle in
  test-play), Main menu; Esc, P or Start resume; works with a gamepad and
  in one-button mode. In-world sounds pause with the game.
- A bigger powder keg: blast radius 4.3 m (was 3.6), more push and damage,
  and a louder show: brighter flash, shockwave ring, rolling fireball, a
  moment of orange light, a smoke column, more debris, a heavier rumble.
  Par was re-checked on every multi-shot level where the keg is available;
  none changed.

### Fixed
- The camera sometimes stayed on the castle after a shot: once a shot
  settled on its own, the collapse framing kept pulling the camera back
  to the castle while the trebuchet reloaded, and nothing re-aimed it when
  the trebuchet was ready. Now the camera always comes home (unless the
  castle falls to a win). The double-tap guard after letting go is 0.35 s.
- Pausing froze the game with no way back: the pause card faded in with a
  tween that stopped with the rest of the level, so it stayed invisible,
  and neither its buttons nor Esc received input while paused.

## [1.0.0-rc.1] - 2026-11-09

First release candidate: everything below, nothing published yet.

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
- Milestone 6: iOS. The Xcode project exports on Linux (`make build
  ARGS=--target ios`); CI archives it on macOS without signing and keeps
  an unsigned `.ipa`. Landscape, iOS 16+, saves and castles visible in
  the Files app. Safe areas now apply to menus and the editor as well as
  the HUD; levels pause when the app goes to the background; the editor
  shows touch tips on touch screens. docs/IOS.md explains signing with a
  free Apple account.
- Milestone 7: performance harness (`make perf`: cost of a physics tick
  in the heaviest scenes; worst 8.5 ms, p95 at most 3.5 ms) with a CI
  budget; fire drawn as overlapping flame tongues with embers and a
  flickering light; one SemVer version in `app.env` mapped to what each
  format needs (deb/rpm `1.0.0~rc.1`, pacman `1.0.0rc1`, numeric for
  Windows and iOS, AppStream `type="development"`).

### Fixed
- Translatable strings split over several lines (or built from pieces)
  were missing from the catalogue; the extractor now reads whole files and
  the editor tips are one sentence per string.
- Installing godot-rapier into a fresh clone (the addons folder did not
  exist yet) now works, and any failure stops instead of reporting success.
- `make dev` exited silently on interactive runs (no `--yes`); optional
  packages are now filtered by availability and installed in one visible
  call.
- Simulation was not reproducible between runs (global RNG in headgear
  props); slow motion could shift body removal. Both fixed and tested.

[Unreleased]: https://github.com/oreo1298/ctc/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/oreo1298/ctc/releases/tag/v1.0.0-rc.1
