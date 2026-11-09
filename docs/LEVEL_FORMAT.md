<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Level format (v1)

> The machine-readable source of truth is
> `game/data/schemas/level.schema.json`, and CI validates every level against it.

Levels are plain JSON. The same format is used by the campaign, the castle
editor's local saves, exported `.json` files and share codes (which are just
compressed JSON, see §5).

## 1. Coordinates and units

* Units are **metres**. 1 m is drawn as 100 px.
* **x** grows to the right and **y** grows **up**. The origin is the base of
  the trebuchet at ground level.
* `pos` is the centre of an object. `rot` is in **degrees,
  counter-clockwise**.
* Gravity is 9.8 m/s² downward.

## 2. Top level

```jsonc
{
  "$schema": "../../schemas/level.schema.json",
  "format": "level",
  "version": 1,                       // bump + add a migration when breaking
  "id": "greenmantle-01",             // unique; [a-z0-9-]+
  "name": "The Wider Moat",           // English; extracted for translation
  "grievance": "Baron Fennick's moat is wider than mine. Fix that.",
  "time_of_day": "morning",           // dawn|morning|noon|afternoon|golden|dusk|night
  "realm": "greenmantle",             // palette/backdrop set; editor levels pick one
  "world": { "right": 48, "kill_y": -12 },
  "trebuchet": { "x": 0, "y": 0 },
  "terrain": [ /* §3 */ ],
  "blocks":  [ /* §4 */ ],
  "enemies": [ /* §4 */ ],
  "par": { "gold": 1, "silver": 2, "bronze": 4 },   // written by the validator bot
  "par_override": null,                              // or {gold,silver,bronze}
  "solution":       [ { "ammo": "iron", "phase": 0.6475, "tap": -1 } ],  // fewest shots, any ammo
  "solution_basic": [ { "ammo": "boulder", "phase": 0.65, "tap": -1 } ]  // first-visit ammo only
}
```

`phase` is the trebuchet release phase (0–1). `tap` is the delay in seconds
from release to the mid-air action (`-1` = none), applied on an exact
physics tick, so proofs replay identically.

## 2a. Par and proofs (the validator bot)

`make validate-levels` searches each campaign level headlessly:

* **gold** = the fewest shots that win with *any* ammo (players may come back
  with later ammo to chase gold), stored as `solution`;
* **silver** = max(gold + 1, fewest shots with the ammo available on the first
  visit), with that proof stored as `solution_basic`;
* **bronze** = silver + 2.

The bot prefers *robust* solutions, where releasing ±0.0025 earlier or later
still wins. `make check-levels` (run by CI) checks that every castle stands
still on its own and replays both proofs. If a proof stops winning, CI fails.

`world.right` is the playable extent in metres. Anything that falls below
`kill_y` or leaves `[-20, right + 20]` is removed (and an enemy counts as
eliminated).

## 3. Terrain

Each terrain piece is a polyline describing a **top surface**. It is filled
downward to `kill_y` and becomes static collision.

```json
{ "points": [[-20, 0], [22, 0], [25, 1.5], [60, 1.5]], "style": "grass" }
```

`style` picks the look (`grass`, `sand`, `snow`, `rock`) and is cosmetic.
Points must be ordered left to right.

## 4. Blocks and enemies

```jsonc
{ "shape": "rect",   "material": "wood",  "pos": [30, 1.0], "size": [0.25, 2.0], "rot": 0 }
{ "shape": "circle", "material": "stone", "pos": [31, 0.5], "radius": 0.5 }
{ "shape": "tri",    "material": "thatch","pos": [30, 3.2], "size": [2.4, 1.0] }  // isosceles roof
{ "shape": "wedge",  "material": "stone", "pos": [29, 0.4], "size": [1.0, 0.8] }  // right triangle
{ "shape": "poly",   "material": "iron",  "pos": [32, 2.0], "points": [[-0.5,0],[0.5,0],[0,0.7]] } // convex, local
{ "static": true, ... }   // optional: an immovable, unbreakable anchor
```

`material` is an id from `game/data/materials.json` (`wood`, `stone`, `glass`,
`ice`, `iron`, `thatch`, `cloth`). Mass, HP and break behaviour come from the
material and the block's area.

```json
{ "type": "king",    "pos": [31, 3.2] }
{ "type": "queen",   "pos": [33, 3.2] }
{ "type": "knight",  "pos": [35, 1.1] }
{ "type": "hostage", "pos": [36, 1.1] }
```

Kings, queens and knights must all be eliminated to win. Hostages cost
points if they are hit.

## 5. Share codes

`SF1-<payload>-<check>`

* *payload*: the level's canonical JSON (keys sorted, numbers rounded to
  0.01 m / 0.1°, `par`, `solution` and `content_hash` stripped), compressed
  with DEFLATE and encoded as base64url without padding.
* *check*: the first 4 bytes of SHA-256(payload), in base64url. It catches
  typos and truncated pastes.
* `SF1` is the format version. Future versions keep decoding old codes.

## 5a. Campaign authoring

Campaign castles are written as short Python functions in
`tools/levels/build_levels.py`. The building primitives place blocks so they
touch exactly, which keeps castles from shifting on load. Run
`make levels && make validate-levels`. Regenerating keeps the existing par and
proofs until the bot replaces them. Levels in `game/data/levels/dev/` are
developer test scenes and never appear in the campaign.

## 6. Realms

`game/data/realms/<id>.json` lists the realm's levels in play order and sets
its palette and backdrop. Level files live in `game/data/levels/<realm>/`.
To add a realm, add a realm file and a level folder. No code changes are needed.

```jsonc
{
  "$schema": "../schemas/realm.schema.json",
  "id": "greenmantle",
  "name": "Greenmantle Hills",
  "order": 1,
  "levels": ["greenmantle-01", "greenmantle-02"],
  "palette": { "ink": "#3b2f26", "paper": "#f3ead5", "ground": "#6f9e4f" }
}
```

## 7. Versioning

`version` is an integer. The loader migrates old levels step by step
(v1→v2→…) before validating, so old share codes and saved files keep working.
