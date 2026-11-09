<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Credits

## People

* Siegefall contributors (see `git log`).

## Inspiration

* *Castle Clout* by Liam Bowmers (2008) and *Crush the Castle* by Armor
  Games (2009) started the genre. Siegefall uses **none** of their names,
  characters, art, audio or level layouts.

## Engine and tools

| Component | Licence | Source |
|---|---|---|
| Godot Engine 4.7.2 | MIT | <https://godotengine.org> |
| godot-rapier 2D v0.36.1 (physics, shipped) | MIT | <https://github.com/appsinacup/godot-rapier-physics> |
| Rapier physics engine (inside godot-rapier) | Apache-2.0 | <https://rapier.rs> |
| godot-rust (inside godot-rapier) | MPL-2.0 | <https://godot-rust.github.io> |
| AppImage type2 runtime 20251108 (inside the AppImage) | MIT | <https://github.com/AppImage/type2-runtime> |
| NSIS (stub inside the Windows installer) | zlib/libpng | <https://nsis.sourceforge.io> |
| GUT 9.7.1 (dev only, not shipped) | MIT | <https://github.com/bitwes/Gut> |
| gdtoolkit (dev only) | MIT | <https://github.com/Scony/godot-gdscript-toolkit> |
| reuse (dev only) | Apache-2.0 / GPL-3.0+ | <https://reuse.software> |
| ShellCheck (dev only) | GPL-3.0 | <https://www.shellcheck.net> |

## Assets

All assets are listed here, including our own. Every file's exact licence is
also machine-readable through REUSE.

| Asset | Author | Licence | Source / how made |
|---|---|---|---|
| `game/icon.svg` | Siegefall contributors | CC-BY-SA-4.0 | hand-written SVG |
| `game/art/characters/*.svg` (king, queen, knight, hostage, crown, tiara, helmet) | Siegefall contributors | CC-BY-SA-4.0 | hand-written SVG |
| `game/art/ui/*.svg` (restart, pause, lock) | Siegefall contributors | CC-BY-SA-4.0 | hand-written SVG |
| `game/art/ui/editor/*.svg` (turn, resize, anchor, copy, delete, flip) | Siegefall contributors | CC-BY-SA-4.0 | hand-written SVG |
| `game/shaders/*` (blocks, terrain, sky, hills) | Siegefall contributors | MIT | procedural shaders |
| `game/fonts/Fraunces.ttf` (headings) | The Fraunces Project Authors | OFL-1.1 | [google/fonts `ofl/fraunces`](https://github.com/google/fonts/tree/main/ofl/fraunces) @ `5bb2873`, licence in `Fraunces-OFL.txt` |
| `game/fonts/Nunito.ttf` (body text) | The Nunito Project Authors | OFL-1.1 | [google/fonts `ofl/nunito`](https://github.com/google/fonts/tree/main/ofl/nunito) @ `5bb2873`, licence in `Nunito-OFL.txt` |

| `game/audio/sfx/*.wav` (89 files: impacts, breaks, trebuchet, royals, UI, jingles) | Siegefall contributors | CC-BY-SA-4.0 | synthesised by `tools/sfx/generate.py` (noise, filters, inharmonic partials, Karplus-Strong strings); regenerate with `make sfx` |
