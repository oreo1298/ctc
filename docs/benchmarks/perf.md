<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Performance: the heaviest moments

Measured with `scripts/perf.sh` (headless, fixed 60 Hz, Godot 4.7.2-stable,
godot-rapier v0.36.1, one solver thread) on: Intel(R) Xeon(R) Processor @ 2.30GHz.

A tick is one 1/60 s step: Rapier plus every game script, without
drawing. At 60 Hz a frame has 16.7 ms for ticks and rendering together.

| Scene | tick p50 (ms) | tick p95 | tick p99 | worst tick | most bodies awake |
|---|---|---|---|---|---|
| greenmantle-12 | 0.29 | 0.92 | 2.14 | 6.27 | 52 |
| saffron-12 | 0.18 | 0.65 | 1.69 | 5.58 | 41 |
| frostfang-12 | 0.38 | 1.12 | 2.43 | 4.50 | 82 |
| shatter | 0.89 | 3.47 | 5.37 | 8.49 | 161 |
