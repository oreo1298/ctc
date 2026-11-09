<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Art pipeline

Most visuals are procedural: shaders under `game/shaders/` and polygons
generated from data. Hand-made art lives here as **hand-written SVG**, which
Godot imports as textures at the scale set in each `.import` file.

## Dropping in better art

1. Keep the file name (for example `characters/king.svg`), or point the
   material/enemy JSON at a new file with its `art` field.
2. Optional texture overrides for materials go in `materials/<id>_albedo.png`
   and `materials/<id>_normal.png` (tangent-space normal map, +Y up). When
   they exist, the block shader samples them instead of the procedural pattern.
3. Add a row to `CREDITS.md` and make sure `reuse lint` passes (CC0, CC-BY,
   CC-BY-SA or OFL only).
4. Run `make screenshots` and look at the result next to the rest of the scene.

Style guide: chunky shapes, a 6 px ink outline at 1× (#3b2f26), soft
top-left key light, and the realm palette (see `docs/DESIGN.md` §4).
