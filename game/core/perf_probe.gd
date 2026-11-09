# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name PerfProbe
extends RefCounted
## Timings for `-- --perf` runs (scripts/perf.sh). Headless, a frame is all
## the CPU work for that frame, so frame time divided by the physics ticks
## it ran is the cost of one simulation tick (Rapier plus game scripts).
## Frames without a tick (slow motion) only count towards frame time. The
## first second (loading the level) is skipped.

const WARMUP_FRAMES: int = 60

var _frame_ms: PackedFloat32Array = []
var _tick_ms: PackedFloat32Array = []
var _bodies: PackedInt32Array = []
var _frames: int = 0
var _last_us: int = 0
var _last_ticks: int = 0


func sample() -> void:
	var now: int = Time.get_ticks_usec()
	var ticks: int = Engine.get_physics_frames()
	_frames += 1
	if _frames > WARMUP_FRAMES and _last_us > 0:
		var ms: float = (now - _last_us) / 1000.0
		_frame_ms.append(ms)
		if ticks > _last_ticks:
			_tick_ms.append(ms / float(ticks - _last_ticks))
		_bodies.append(int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))
	_last_us = now
	_last_ticks = ticks


static func percentile(values: PackedFloat32Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(roundi(p * (sorted.size() - 1)), 0, sorted.size() - 1)]


func summary() -> String:
	var bodies := PackedFloat32Array(Array(_bodies))
	return (
		(
			"[perf] frames=%d ticks=%d tick_ms p50=%.2f p95=%.2f p99=%.2f max=%.2f"
			+ " frame_ms max=%.2f bodies_max=%d"
		)
		% [
			_frame_ms.size(),
			_tick_ms.size(),
			percentile(_tick_ms, 0.5),
			percentile(_tick_ms, 0.95),
			percentile(_tick_ms, 0.99),
			percentile(_tick_ms, 1.0),
			percentile(_frame_ms, 1.0),
			int(percentile(bodies, 1.0)),
		]
	)
