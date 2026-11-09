# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node2D
## Stacking / collapse benchmark. Builds one scenario procedurally, steps it
## for a fixed number of physics ticks (run with --fixed-fps 60 so the engine
## never waits on real time), then writes a JSON report and quits.
##
## User args (after `--`):
##   --scenario=tower|pyramid|castle|collapse   --out=/path/report.json
##   --ticks=N  (default 600)

const PX: float = 100.0  # pixels per metre
const FRICTION: float = 0.6
const BOUNCE: float = 0.05

var _scenario: String = "tower"
var _out: String = ""
var _max_ticks: int = 600
var _ticks: int = 0
var _bodies: Array[RigidBody2D] = []
var _initial: PackedVector2Array = PackedVector2Array()
var _frame_us: PackedInt64Array = PackedInt64Array()
var _last_us: int = 0
var _all_asleep_tick: int = -1
var _awake_samples: PackedInt32Array = PackedInt32Array()
var _boulder: RigidBody2D = null
var _engine_label: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--engine-label="):
			_engine_label = arg.get_slice("=", 1)
		elif arg.begins_with("--ticks="):
			_max_ticks = arg.get_slice("=", 1).to_int()
	_build_ground()
	match _scenario:
		"tower":
			_build_tower(Vector2(0.0, 0.0), 20, Vector2(0.6, 0.6))
		"pyramid":
			_build_pyramid(15, Vector2(0.8, 0.4))
		"castle", "collapse":
			_build_castle(10, 10)
		_:
			push_error("unknown scenario %s" % _scenario)
			get_tree().quit(2)
			return
	for b: RigidBody2D in _bodies:
		_initial.append(b.position)


func _physics_process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_us != 0:
		_frame_us.append(now - _last_us)
	_last_us = now
	_ticks += 1
	if _scenario == "collapse" and _ticks == 120:
		_fire_boulder()
	var awake: int = 0
	for b: RigidBody2D in _bodies:
		if not b.sleeping:
			awake += 1
	if _ticks % 30 == 0:
		_awake_samples.append(awake)
	var settle_from: int = 120 if _scenario == "collapse" else 0
	if awake == 0 and _all_asleep_tick < 0 and _ticks > settle_from + 1:
		_all_asleep_tick = _ticks
	elif awake > 0 and _ticks <= settle_from + 1:
		_all_asleep_tick = -1
	if _ticks >= _max_ticks:
		_finish()


# --------------------------------------------------------------- building ---
func _body(pos_m: Vector2, size_m: Vector2, density: float) -> RigidBody2D:
	var b := RigidBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size_m * PX
	shape.shape = rect
	b.add_child(shape)
	b.position = Vector2(pos_m.x, -pos_m.y) * PX
	b.mass = size_m.x * size_m.y * density
	var mat := PhysicsMaterial.new()
	mat.friction = FRICTION
	mat.bounce = BOUNCE
	b.physics_material_override = mat
	b.can_sleep = true
	add_child(b)
	_bodies.append(b)
	return b


func _build_ground() -> void:
	var g := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400.0, 4.0) * PX
	shape.shape = rect
	g.add_child(shape)
	g.position = Vector2(0.0, 2.0) * PX
	var mat := PhysicsMaterial.new()
	mat.friction = FRICTION
	g.physics_material_override = mat
	add_child(g)


func _build_tower(base: Vector2, count: int, size: Vector2) -> void:
	for i: int in count:
		_body(base + Vector2(0.0, size.y * (i + 0.5)), size, 600.0)


func _build_pyramid(rows: int, size: Vector2) -> void:
	for row: int in rows:
		var n: int = rows - row
		for i: int in n:
			var x: float = (i - (n - 1) * 0.5) * size.x
			_body(Vector2(x, size.y * (row + 0.5)), size, 2400.0)


## A wall of `cols` x `levels` rooms: two wooden pillars and a stone lintel
## each, i.e. 3 bodies per room (10 x 10 = 300 bodies, 12 m tall).
func _build_castle(cols: int, levels: int) -> void:
	var room_w: float = 1.2
	var pillar := Vector2(0.2, 1.0)
	var lintel := Vector2(1.2, 0.2)
	for lv: int in levels:
		var y0: float = lv * (pillar.y + lintel.y)
		for c: int in cols:
			var x0: float = (c - cols * 0.5) * room_w
			_body(Vector2(x0 + 0.1, y0 + pillar.y * 0.5), pillar, 600.0)
			_body(Vector2(x0 + room_w - 0.1, y0 + pillar.y * 0.5), pillar, 600.0)
			_body(Vector2(x0 + room_w * 0.5, y0 + pillar.y + lintel.y * 0.5), lintel, 2400.0)


func _fire_boulder() -> void:
	var b := RigidBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 0.45 * PX
	shape.shape = circle
	b.add_child(shape)
	b.position = Vector2(-14.0, -7.0) * PX
	b.mass = PI * 0.45 * 0.45 * 2400.0
	b.linear_velocity = Vector2(32.0, -2.0) * PX
	add_child(b)
	_boulder = b


# ---------------------------------------------------------------- report ---
func _finish() -> void:
	var drift_max: float = 0.0
	var drift_sum: float = 0.0
	var toppled: int = 0
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_SHA256)
	for i: int in _bodies.size():
		var b: RigidBody2D = _bodies[i]
		var d: float = b.position.distance_to(_initial[i]) / PX
		drift_max = maxf(drift_max, d)
		drift_sum += d
		if d > 0.5:
			toppled += 1
		var q := Vector2i(roundi(b.position.x * 100.0), roundi(b.position.y * 100.0))
		hash_ctx.update(("%d,%d;" % [q.x, q.y]).to_utf8_buffer())
	var sorted: PackedInt64Array = _frame_us.duplicate()
	sorted.sort()
	var total: int = 0
	for v: int in _frame_us:
		total += v
	var n: int = maxi(sorted.size(), 1)
	var report: Dictionary = {
		"engine": _engine_label,
		"physics_server": str(ProjectSettings.get_setting("physics/2d/physics_engine")),
		"scenario": _scenario,
		"bodies": _bodies.size(),
		"ticks": _ticks,
		"frame_ms_mean": total / float(n) / 1000.0,
		"frame_ms_p95": sorted[int(n * 0.95)] / 1000.0 if sorted.size() > 0 else 0.0,
		"frame_ms_max": sorted[n - 1] / 1000.0 if sorted.size() > 0 else 0.0,
		"drift_max_m": drift_max,
		"drift_mean_m": drift_sum / maxf(_bodies.size(), 1.0),
		"moved_over_0_5m": toppled,
		"all_asleep_at_s": _all_asleep_tick / 60.0 if _all_asleep_tick >= 0 else -1.0,
		"awake_every_0_5s": Array(_awake_samples),
		"final_state_sha256": hash_ctx.finish().hex_encode().substr(0, 16),
	}
	var text: String = JSON.stringify(report, "  ")
	print(text)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	get_tree().quit(0)
