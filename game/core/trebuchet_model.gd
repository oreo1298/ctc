# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name TrebuchetModel
extends RefCounted
## Analytic trebuchet: everything (rig pose and launch state) is a pure
## function of the swing phase p in [0, 1]. See docs/DESIGN.md §8.3.
##
## Units are metres and seconds, y up, origin at the trebuchet's base.
## The arm turns clockwise (angle decreasing); the sling's absolute angle
## also turns clockwise, lagging the arm and then whipping past it.

const DIFF_H: float = 0.0005

var pivot_height: float = 3.0
var arm_long: float = 3.4
var arm_short: float = 1.0
var sling_length: float = 2.2
var counterweight_size: Vector2 = Vector2(1.2, 1.0)
var swing_duration: float = 1.6
var arm_start: float = deg_to_rad(215.0)
var arm_end: float = deg_to_rad(40.0)
var sling_start: float = deg_to_rad(340.0)
var sling_end: float = deg_to_rad(20.0)
var sling_lag: float = 0.3
var arm_ease: float = 1.8
var sling_ease: float = 1.3
var launch_speed: float = 21.0
var auto_release_phase: float = 1.0

## m/s per unit of d(position)/d(phase); derived so the fastest point of the
## swing launches at exactly `launch_speed`.
var _gain: float = 0.0


static func from_dict(d: Dictionary) -> TrebuchetModel:
	var m := TrebuchetModel.new()
	m.pivot_height = float(d.get("pivot_height", m.pivot_height))
	m.arm_long = float(d.get("arm_long", m.arm_long))
	m.arm_short = float(d.get("arm_short", m.arm_short))
	m.sling_length = float(d.get("sling_length", m.sling_length))
	var cw: Array = d.get("counterweight_size", [1.2, 1.0])
	m.counterweight_size = Vector2(float(cw[0]), float(cw[1]))
	m.swing_duration = float(d.get("swing_duration", m.swing_duration))
	m.arm_start = deg_to_rad(float(d.get("arm_start_deg", 215.0)))
	m.arm_end = deg_to_rad(float(d.get("arm_end_deg", 40.0)))
	m.sling_start = deg_to_rad(float(d.get("sling_start_deg", 340.0)))
	m.sling_end = deg_to_rad(float(d.get("sling_end_deg", 20.0)))
	m.sling_lag = float(d.get("sling_lag", m.sling_lag))
	m.arm_ease = float(d.get("arm_ease", m.arm_ease))
	m.sling_ease = float(d.get("sling_ease", m.sling_ease))
	m.launch_speed = float(d.get("launch_speed", m.launch_speed))
	m.auto_release_phase = float(d.get("auto_release_phase", m.auto_release_phase))
	return m


func _derive_gain() -> void:
	var peak: float = 0.0
	for i: int in 2001:
		peak = maxf(peak, _dpos_dp(i / 2000.0).length())
	_gain = launch_speed / peak if peak > 0.0 else 0.0


## Symmetric sigmoid ease: 0 -> 0, 0.5 -> 0.5, 1 -> 1; steeper with larger a.
static func ease_sigmoid(x: float, a: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	var ta: float = pow(t, a)
	var ua: float = pow(1.0 - t, a)
	if ta + ua <= 0.0:
		return t
	return ta / (ta + ua)


func pivot() -> Vector2:
	return Vector2(0.0, pivot_height)


## Absolute arm angle (radians, CCW from +x) of the long (sling) end.
func arm_angle(p: float) -> float:
	return lerpf(arm_start, arm_end, ease_sigmoid(p, arm_ease))


## Absolute sling angle (radians) from the arm tip towards the projectile.
func sling_angle(p: float) -> float:
	var q: float = clampf((p - sling_lag) / (1.0 - sling_lag), 0.0, 1.0)
	return lerpf(sling_start, sling_end, ease_sigmoid(q, sling_ease))


func arm_tip(p: float) -> Vector2:
	return pivot() + Vector2.from_angle(arm_angle(p)) * arm_long


func counterweight_hinge(p: float) -> Vector2:
	return pivot() - Vector2.from_angle(arm_angle(p)) * arm_short


## Projectile centre while it is still in the sling. The pouch rides on the
## ground (y >= 0) at the start of the swing instead of sinking into it.
func projectile_pos(p: float) -> Vector2:
	var pos: Vector2 = arm_tip(p) + Vector2.from_angle(sling_angle(p)) * sling_length
	pos.y = maxf(pos.y, 0.0)
	return pos


## Launch velocity in m/s for a release at phase p. Pure and deterministic:
## the same p always yields exactly the same vector. It is decoupled from
## swing_duration (an animation length), so slowing the swing for
## accessibility never changes a shot.
func launch_velocity(p: float, speed_scale: float = 1.0) -> Vector2:
	if _gain == 0.0:
		_derive_gain()
	return _dpos_dp(p) * _gain * speed_scale


func _dpos_dp(p: float) -> Vector2:
	var a: float = clampf(p - DIFF_H, 0.0, 1.0)
	var b: float = clampf(p + DIFF_H, 0.0, 1.0)
	if b <= a:
		return Vector2.ZERO
	return (projectile_pos(b) - projectile_pos(a)) / (b - a)


## Flat-ground range estimate (no drag) from the release point, for tooling.
func ideal_range(p: float, speed_scale: float = 1.0, gravity: float = 9.8) -> float:
	var v: Vector2 = launch_velocity(p, speed_scale)
	var h: float = projectile_pos(p).y
	if v.y * v.y + 2.0 * gravity * h < 0.0:
		return 0.0
	var t: float = (v.y + sqrt(v.y * v.y + 2.0 * gravity * h)) / gravity
	return projectile_pos(p).x + v.x * t
