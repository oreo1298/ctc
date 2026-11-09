<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Physics engine benchmark: results (milestone 1)

**Decision: godot-rapier 2D (v0.36.1)**, with the solver pinned to one thread
for determinism. Godot Physics 2D stays a one-line fallback
(`physics/2d/physics_engine`), because the game only uses the standard
`RigidBody2D` API.

Run on 2026-11-09: Godot 4.7.2-stable, Linux x86_64, 4 vCPU cloud VM,
headless, fixed 60 Hz tick, two runs per cell. "GodotPhysics2D-tuned" uses
64 solver iterations, contact bias 0.4 and max penetration 0.1 to give the
built-in engine its best shot.

| scenario | engine | bodies | frame ms mean | p95 | max | max drift (m) | moved >0.5 m | all asleep at (s) | runs identical |
|---|---|---|---|---|---|---|---|---|---|
| castle | GodotPhysics2D | 300 | 2.45 | 3.06 | 6.79 | 465.122 | 300 | never | yes |
| castle | GodotPhysics2D-tuned | 300 | 3.79 | 4.86 | 11.97 | 15.124 | 299 | never | yes |
| castle | Rapier2D | 300 | 0.30 | 1.02 | 6.45 | 0.086 | 0 | 3.6 | yes |
| collapse | GodotPhysics2D | 300 | 2.50 | 3.21 | 12.79 | 12.724 | 300 | never | yes |
| collapse | GodotPhysics2D-tuned | 300 | 3.71 | 4.85 | 9.65 | 62.348 | 296 | never | yes |
| collapse | Rapier2D | 300 | 0.73 | 1.28 | 6.34 | 15.110 | 226 | 11.6 | yes |
| pyramid | GodotPhysics2D | 120 | 0.06 | 0.68 | 4.47 | 0.035 | 0 | 0.9 | yes |
| pyramid | GodotPhysics2D-tuned | 120 | 0.12 | 0.77 | 3.13 | 0.011 | 0 | 0.8 | yes |
| pyramid | Rapier2D | 120 | 0.08 | 0.28 | 2.56 | 0.023 | 0 | 0.8 | yes |
| tower | GodotPhysics2D | 20 | 0.07 | 0.20 | 0.78 | 11.079 | 20 | 5.0 | yes |
| tower | GodotPhysics2D-tuned | 20 | 0.07 | 0.25 | 5.13 | 14.225 | 19 | 4.6 | yes |
| tower | Rapier2D | 20 | 0.06 | 0.10 | 1.18 | 0.132 | 0 | 1.1 | yes |

## Reading the numbers

* **Tall stacks:** with Godot Physics the 20-box tower falls over (all 20
  boxes move more than 0.5 m) even with 4× solver iterations. Rapier holds it
  (13 cm max drift) and puts it to sleep in about 1 s.
* **300-body castle:** with Godot Physics the wall shakes itself apart and
  never sleeps. Tuning slows the collapse but cannot stop it, and it costs
  50% more frame time. Rapier keeps it standing (9 cm max drift), sleeps
  it in 3.6 s, and runs about **8× faster** (0.30 ms vs 2.45 ms per frame).
* **Collapse:** Rapier's frame time stays around 1 ms p95 while 300 bodies
  tumble, and everything settles in about 12 s. Godot Physics never settles.
* **Determinism:** both engines reproduced their final state exactly across
  runs. Rapier also advertises *cross-platform* determinism, which lets the
  level-validator bot's proofs hold on every platform.
* **Platform gate:** the release ships binaries for Linux x86_64 and arm64,
  Windows x86_64, macOS and iOS arm64, as required (docs/DESIGN.md §8.2).

## Costs and risks of the extension

* It is a native GDExtension, fetched and SHA-256-checked by
  `scripts/bootstrap.sh` (not committed: about 117 MB of binaries across
  all platforms).
* Godot upgrades must wait for a matching godot-rapier release (it targets
  a specific `api-4-x`).
* Flathub and source-based packages (AUR `-git`) should build it from source
  with cargo. This is handled in milestone 5.
