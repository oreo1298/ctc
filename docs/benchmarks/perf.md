<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Performance: the heaviest moments

Measured with `scripts/perf.sh` (headless, fixed 60 Hz, Godot 4.7.2-stable,
godot-rapier v0.36.1, one solver thread) on: Intel(R) Xeon(R) Processor @ 2.10GHz.

A tick is one 1/60 s step: Rapier plus every game script, without
drawing. At 60 Hz a frame has 16.7 ms for ticks and rendering together.

| Scene | tick p50 (ms) | tick p95 | tick p99 | worst tick | most bodies awake |
|---|---|---|---|---|---|
| greenmantle-12 | 0.43 | 1.78 | 3.26 | 9.86 | 52 |
| saffron-12 | 0.29 | 1.09 | 3.04 | 12.92 | 41 |
| frostfang-12 | 0.73 | 2.12 | 4.28 | 10.46 | 82 |
| mirefen-12 | 0.64 | 1.87 | 3.54 | 7.44 | 75 |
| cinderreach-12 | 0.60 | 1.77 | 3.23 | 10.30 | 54 |
| skyreach-12 | 0.56 | 1.35 | 2.59 | 6.10 | 69 |
| shatter | 0.90 | 4.98 | 7.44 | 10.79 | 161 |
