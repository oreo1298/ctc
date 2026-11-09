# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name CameraRig
extends Camera2D
## Gameplay camera (docs/DESIGN.md §5): intro flyover -> aim framing ->
## projectile follow with look-ahead -> collapse framing -> back to aim.
## All motion is exponentially smoothed; shake is trauma-based.

enum Mode { INTRO, AIM, FOLLOW, FRAME, MANUAL }

const AIM_WIDTH_M: float = 34.0
const MIN_WIDTH_M: float = 12.0
const MAX_WIDTH_M: float = 70.0

var mode: Mode = Mode.AIM
var target_center: Vector2 = Vector2.ZERO
var target_width_px: float = 3000.0
var follow: Node2D = null
var frame_rect: Rect2 = Rect2()
var aim_center: Vector2 = Vector2.ZERO
var castle_rect: Rect2 = Rect2()
var smoothing: float = 4.0

var _trauma: float = 0.0
var _shake_t: float = 0.0
var _intro_t: float = 0.0
var _noise := FastNoiseLite.new()


func _init() -> void:
	# Physics interpolation requires the camera to move in the physics tick.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	_noise.frequency = 2.0
	Effects.shake_requested.connect(add_trauma)
	ignore_rotation = true


func setup(trebuchet_px: Vector2, castle: Rect2) -> void:
	castle_rect = castle
	var vp: Vector2 = get_viewport_rect().size
	var view_h: float = AIM_WIDTH_M * 100.0 * vp.y / maxf(vp.x, 1.0)
	# Trebuchet in the left third, ground line at ~78% of the screen height.
	aim_center = trebuchet_px + Vector2(AIM_WIDTH_M * 100.0 * 0.36, -view_h * 0.28)
	go_aim(true)


func start_intro() -> void:
	mode = Mode.INTRO
	_intro_t = 0.0
	_fit_rect(castle_rect.grow(350.0), true)


func go_aim(snap: bool = false) -> void:
	mode = Mode.AIM
	follow = null
	target_center = aim_center
	target_width_px = AIM_WIDTH_M * 100.0
	if snap:
		_snap()


func follow_node(n: Node2D) -> void:
	follow = n
	mode = Mode.FOLLOW


func frame(r: Rect2) -> void:
	mode = Mode.FRAME
	frame_rect = r
	_fit_rect(r, false)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _fit_rect(r: Rect2, snap: bool) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var w: float = maxf(r.size.x, r.size.y * aspect)
	target_center = r.get_center()
	target_width_px = clampf(w, MIN_WIDTH_M * 100.0, MAX_WIDTH_M * 100.0)
	if snap:
		_snap()


func _snap() -> void:
	position = target_center
	var vp: Vector2 = get_viewport_rect().size
	var z: float = vp.x / target_width_px
	zoom = Vector2(z, z)
	reset_smoothing()


func _physics_process(delta: float) -> void:
	match mode:
		Mode.INTRO:
			_intro_t += delta
			if _intro_t > 1.3:
				go_aim()
				smoothing = 1.8
		Mode.FOLLOW:
			if is_instance_valid(follow):
				var v := Vector2.ZERO
				if follow is RigidBody2D:
					v = (follow as RigidBody2D).linear_velocity
				var look: Vector2 = follow.global_position + v * 0.28
				# Keep the ground in view: frame from the ground line up to the projectile.
				var top: float = minf(look.y, follow.global_position.y) - 300.0
				var bottom: float = maxf(150.0, follow.global_position.y + 300.0)
				target_center = Vector2(look.x, (top + bottom) * 0.5)
				var vp: Vector2 = get_viewport_rect().size
				var need_h: float = bottom - top
				target_width_px = clampf(
					maxf(AIM_WIDTH_M * 100.0 * 0.85, need_h * vp.x / vp.y),
					MIN_WIDTH_M * 100.0,
					MAX_WIDTH_M * 100.0
				)
				smoothing = 5.0
		_:
			pass
	var k: float = 1.0 - exp(-smoothing * delta)
	position = position.lerp(target_center, k)
	var vp_w: float = get_viewport_rect().size.x
	var z_target: float = vp_w / target_width_px
	var z: float = lerpf(zoom.x, z_target, k)
	zoom = Vector2(z, z)
	if mode != Mode.INTRO:
		smoothing = lerpf(smoothing, 3.5, k)
	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_t += delta * 60.0
	var s: float = _trauma * _trauma * 26.0
	offset = (
		Vector2(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t)) * s / zoom.x
	)
	_trauma = maxf(0.0, _trauma - delta * 1.6)
