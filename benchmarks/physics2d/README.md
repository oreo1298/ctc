<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# 2D physics benchmark

A tiny standalone Godot project that compares physics engines on the
workloads this game cares about. Every scenario is built procedurally in
`bench.gd`, stepped headlessly at a fixed 60 Hz (`--fixed-fps 60`), and
reported as JSON.

| Scenario | What it stresses |
|---|---|
| `tower` | 20 boxes in a single column (12 m): stacking stability |
| `pyramid` | 120 heavy bricks: wide stacks, sleeping |
| `castle` | 300 bodies: 10 × 10 rooms of wooden pillars and stone lintels, 12 m tall |
| `collapse` | the castle hit by a 1.5 t boulder at 32 m/s: frame time under load, settling |

Metrics: mean/p95/max frame time, max drift of any body from its start
(0 = perfectly stable), bodies that moved > 0.5 m, time until every body
sleeps, and whether two runs end in the identical state (determinism).

```bash
benchmarks/physics2d/run.sh --runs 2    # needs `make dev` first
```

The run fetches the pinned godot-rapier release (`toolchain.lock`) and writes
`build/bench/physics2d/summary.md`. Results and the decision are in
[docs/benchmarks/physics2d.md](../../docs/benchmarks/physics2d.md).
