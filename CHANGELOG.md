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
