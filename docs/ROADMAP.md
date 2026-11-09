<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Roadmap

Milestones are worked in order. Each ends with a commit and a short summary.

| # | Milestone | Status |
|---|---|---|
| 0 | Research, DESIGN.md, repo, pinned Godot, Makefile, CI skeleton, licences | **done** |
| 1 | Physics benchmark → engine choice. Vertical slice: one level, two-tap trebuchet, boulder, wood + stone, king + knight, win screen with medals, `make run`, screenshots | **done** |
| 2 | Destruction + juice: damage/cracks/fracture (Voronoi vs. pre-broken benchmark), all materials, particles, camera, slow-mo, audio | **done** |
| 3 | Content + accessibility: all ammo & enemies, 3 realms × 12 levels, progression, saves (versioned, migrations), settings, one-button mode, reduced shake/flash, non-colour material cues, text scaling; validator bot + auto par | **done** |
| 4 | Castle editor + share codes | **done** |
| 5 | Linux packaging (AppImage, Flatpak, deb, rpm, AUR ×2, Nix), install/uninstall, container CI; Windows zip + NSIS | **done** |
| 6 | iOS CI (unsigned archive), docs/IOS.md, touch polish, haptics, safe areas | next |
| 7 | Performance, polish, release candidate | |

## After 1.0 (ideas, not promises)

* More realms through community level packs (the realm format is already
  pluggable).
* Weather (wind) as a level modifier.
* Replays: share a code that reproduces your exact shots.
* More languages.
