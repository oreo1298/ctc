# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Trebuchet
extends Node2D
## The player's trebuchet: a visual rig posed entirely from TrebuchetModel.
## Tap 1 -> start_swing(); tap 2 -> release() returns the swing phase p.
## The shot itself is launch_velocity(p): see docs/DESIGN.md §8.3.

signal released(phase: float, pos_px: Vector2, vel_px: Vector2)
signal ready_to_fire

enum State { IDLE, SWINGING, FOLLOW_THROUGH, REWINDING }

const ROPE_COLOR := Color(0.36, 0.27, 0.19)
const REWIND_TIME: float = 0.55

var model: TrebuchetModel
var state: State = State.IDLE
var phase: float = 0.0
var last_release_phase: float = -1.0
var ammo: Dictionary = {}

var _elapsed: float = 0.0
var _last_frame_usec: int = 0
var _arm: MeshInstance2D
var _cw: MeshInstance2D
var _cw_straps: Line2D
var _sling: Line2D
var _payload: Node2D = null
var _pivot_cap: MeshInstance2D
var _rewind_from: float = 1.0


func setup(treb_model: TrebuchetModel) -> void:
	model = treb_model
	var wood: Dictionary = Data.material("wood").duplicate(true)
	wood["colors"] = {"base": "#a0714a", "dark": "#6b4529", "light": "#c49466"}
	var iron: Dictionary = Data.material("iron")
	var stone: Dictionary = Data.material("stone")
	var back_wood: Dictionary = wood.duplicate(true)
	back_wood["colors"] = {"base": "#7a5233", "dark": "#523520", "light": "#93683f"}
	var pivot_m: Vector2 = model.pivot()

	# Back upright, behind the arm.
	_beam(Vector2(-1.0, 0.62), pivot_m, 0.28, "treb_back", back_wood, -2)
	# Arm, counterweight and sling are posed every frame.
	_arm = _part(
		{"shape": "rect", "size": Vector2(model.arm_long + model.arm_short, 0.24)},
		"treb_wood",
		wood,
		0
	)
	_cw_straps = Line2D.new()
	_cw_straps.width = 7.0
	_cw_straps.default_color = Color(0.25, 0.25, 0.28)
	_cw_straps.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_cw_straps)
	_cw = _part({"shape": "rect", "size": model.counterweight_size}, "stone", stone, 0)
	_sling = Line2D.new()
	_sling.width = 6.0
	_sling.default_color = ROPE_COLOR
	_sling.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_sling.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_sling)
	# Front frame.
	_beam(Vector2(1.0, 0.62), pivot_m, 0.3, "treb_wood", wood, 2)
	_beam(Vector2(-2.6, 0.55), Vector2(2.2, 0.55), 0.34, "treb_wood", wood, 2)
	_beam(Vector2(-0.62, 1.7), Vector2(0.62, 1.7), 0.2, "treb_wood", wood, 2)
	for wx: float in [-1.9, 1.5]:
		var w := _part({"shape": "circle", "radius": 0.42}, "treb_back", back_wood, 3)
		w.position = Units.to_px(Vector2(wx, 0.42))
		for k: int in 3:
			var spoke := Line2D.new()
			var a: float = PI * k / 3.0 + 0.3
			spoke.points = PackedVector2Array(
				[Vector2.from_angle(a) * 30.0, Vector2.from_angle(a + PI) * 30.0]
			)
			spoke.width = 5.0
			spoke.default_color = UiTheme.INK
			w.add_child(spoke)
		var hub := _part({"shape": "circle", "radius": 0.1}, "iron", iron, 4)
		hub.position = w.position
	_pivot_cap = _part({"shape": "circle", "radius": 0.16}, "iron", iron, 4)
	_pivot_cap.position = Units.to_px(pivot_m)
	set_pose(0.0)


func _part(spec: Dictionary, mat_id: String, def: Dictionary, z: int) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.mesh = ShapeGeometry.bevel_mesh_for(spec, Vector2(mat_id.length() * 1.7, 0.4))
	mi.material = Block.shader_material_for(mat_id, def)
	mi.z_index = z
	add_child(mi)
	return mi


func _beam(
	a_m: Vector2, b_m: Vector2, thickness: float, mat_id: String, def: Dictionary, z: int
) -> void:
	var len_m: float = a_m.distance_to(b_m) + thickness
	var mi := _part({"shape": "rect", "size": Vector2(len_m, thickness)}, mat_id, def, z)
	var a: Vector2 = Units.to_px(a_m)
	var b: Vector2 = Units.to_px(b_m)
	mi.position = (a + b) * 0.5
	mi.rotation = (b - a).angle()


func set_ammo(ammo_def: Dictionary) -> void:
	ammo = ammo_def
	if _payload != null:
		_payload.queue_free()
		_payload = null
	if not ammo.is_empty():
		_payload = Projectile.make_visual(ammo)
		_payload.z_index = 1
		add_child(_payload)
	set_pose(phase)


func set_pose(p: float) -> void:
	phase = p
	var pivot: Vector2 = Units.to_px(model.pivot())
	var arm_a: float = model.arm_angle(p)
	var dir := Vector2(cos(arm_a), -sin(arm_a))
	_arm.position = pivot + dir * (model.arm_long - model.arm_short) * 0.5 * Units.PX_PER_M
	_arm.rotation = dir.angle()
	var hinge: Vector2 = Units.to_px(model.counterweight_hinge(p))
	var cw_center: Vector2 = (
		hinge + Vector2(0.0, (0.3 + model.counterweight_size.y * 0.5) * Units.PX_PER_M)
	)
	_cw.position = cw_center
	var half: float = model.counterweight_size.x * 0.4 * Units.PX_PER_M
	var top: float = cw_center.y - model.counterweight_size.y * 0.5 * Units.PX_PER_M
	_cw_straps.points = PackedVector2Array(
		[Vector2(cw_center.x - half, top), hinge, Vector2(cw_center.x + half, top)]
	)
	var tip: Vector2 = Units.to_px(model.arm_tip(p))
	var pouch: Vector2 = Units.to_px(model.projectile_pos(p))
	if state == State.FOLLOW_THROUGH or state == State.REWINDING:
		# Empty sling: let the pouch trail along the swing.
		_sling.points = PackedVector2Array([tip, pouch])
	else:
		_sling.points = PackedVector2Array([tip, pouch])
	if _payload != null:
		_payload.position = pouch
		_payload.visible = state == State.IDLE or state == State.SWINGING


func can_fire() -> bool:
	return state == State.IDLE and not ammo.is_empty()


func start_swing() -> void:
	if not can_fire():
		return
	state = State.SWINGING
	_elapsed = 0.0
	_last_frame_usec = Time.get_ticks_usec()


## Phase for a release happening right now, with sub-frame precision.
func current_phase() -> float:
	var since_frame: float = (Time.get_ticks_usec() - _last_frame_usec) / 1_000_000.0
	if get_tree().paused:
		since_frame = 0.0
	var t: float = (_elapsed + since_frame) * Settings.swing_speed
	return clampf(t / model.swing_duration, 0.0, 1.0)


## Release now (tap 2). Returns the phase used, or -1 if not swinging.
func release() -> float:
	if state != State.SWINGING:
		return -1.0
	return release_at(current_phase())


## Release at an exact phase (replays, the validator bot, auto-release).
func release_at(p: float) -> float:
	var ph: float = clampf(p, 0.0, 1.0)
	state = State.FOLLOW_THROUGH
	last_release_phase = ph
	var pos: Vector2 = Units.to_px(model.projectile_pos(ph)) + position
	var v_m: Vector2 = model.launch_velocity(ph, float(ammo.get("speed_scale", 1.0)))
	var vel: Vector2 = Vector2(v_m.x, -v_m.y) * Units.PX_PER_M
	set_pose(ph)
	released.emit(ph, pos, vel)
	return ph


func reload() -> void:
	if state == State.FOLLOW_THROUGH:
		state = State.REWINDING
		_rewind_from = phase
		_elapsed = 0.0


func _process(delta: float) -> void:
	_last_frame_usec = Time.get_ticks_usec()
	match state:
		State.SWINGING:
			_elapsed += delta
			var p: float = clampf(_elapsed * Settings.swing_speed / model.swing_duration, 0.0, 1.0)
			set_pose(p)
			if p >= model.auto_release_phase:
				release_at(model.auto_release_phase)
		State.FOLLOW_THROUGH:
			set_pose(minf(1.0, phase + delta * Settings.swing_speed / model.swing_duration))
		State.REWINDING:
			_elapsed += delta
			var k: float = clampf(_elapsed / REWIND_TIME, 0.0, 1.0)
			set_pose(lerpf(_rewind_from, 0.0, k * k * (3.0 - 2.0 * k)))
			if k >= 1.0:
				state = State.IDLE
				set_pose(0.0)
				ready_to_fire.emit()
