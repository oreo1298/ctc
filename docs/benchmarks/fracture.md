<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Fracture benchmark: runtime Voronoi vs. pre-broken shards (milestone 2)

**Decision: runtime Voronoi** (`game/core/fracture.gd`), using our own
Sutherland–Hodgman half-plane clipping, seeds biased towards the impact
point, an anisotropic metric for wood grain, and minimum seed spacing
against slivers.

Run on 2026-11-09: Godot 4.7.2, Linux x86_64, 4 vCPU VM, 400 fractures per
row (`scripts/godot.sh --headless --path game res://tools/fracture_bench.tscn`).
"Spawn pieces" is the cost of creating the resulting physics bodies
(collision shape, bevel mesh, occluder) and applies to both approaches.

| block | cells | runtime clip (µs) | Geometry2D (µs) | pre-broken lookup (µs) | spawn pieces (µs) | min/mean cell area ratio |
|---|---|---|---|---|---|---|
| wood plank 3.8x0.3 | 7 | 74 | 117 | 1.4 | 779 | 0.11 / 0.46 |
| stone block 1.2x0.8 | 7 | 69 | 125 | 1.5 | 650 | 0.12 / 0.49 |
| glass pane 1x1 | 14 | 249 | 513 | 3.0 | 1278 | 0.13 / 0.44 |
| big stone 2x2 | 10 | 133 | 327 | 2.3 | 1078 | 0.14 / 0.47 |

## Why runtime Voronoi

* **Cost is dominated by spawning, not geometry.** The Voronoi split takes
  70–250 µs, while creating the pieces takes 650–1300 µs either way.
  Pre-broken shards would save at most ~15% of a fracture's cost.
* **Every break is different and reacts to the hit.** Seeds cluster
  where the block was struck, so pieces are small near the impact and large
  far from it. Pre-broken sets repeat visibly, especially on rows of
  identical planks.
* **Our clipper is ~2× faster than `Geometry2D.intersect_polygons`** for
  this job and always yields convex cells, so pieces use
  `ConvexPolygonShape2D` without decomposition.
* **Slivers are controlled:** minimum seed spacing raised the worst cell
  from 1–2% to ≥ 11% of the mean area (first table run vs. this one).

## Guard rails

* At most 3 fractures are spawned per physics tick. Extra ones are queued,
  so worst-case spikes stay around 3 ms.
* Body budget of 320. Cells under 0.018 m² become particles. Settled small
  debris shrinks away after 5 s, and the oldest settled debris is retired
  first when the budget is full.
* Pieces break at most twice (generation 2 crumbles to particles).
