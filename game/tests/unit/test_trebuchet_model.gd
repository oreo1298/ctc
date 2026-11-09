# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## The trebuchet must give exactly the same shot for the same release phase
## (docs/DESIGN.md §8.3), independent of animation speed.

var model: TrebuchetModel


func before_each() -> void:
	model = TrebuchetModel.from_dict(Data.trebuchet)


func test_same_phase_same_shot_bitwise() -> void:
	for p: float in [0.3, 0.5123, 0.65, 0.99]:
		var a: Vector2 = model.launch_velocity(p)
		var b: Vector2 = TrebuchetModel.from_dict(Data.trebuchet).launch_velocity(p)
		assert_eq(a, b, "phase %s must be reproducible" % p)
		assert_eq(model.projectile_pos(p), model.projectile_pos(p))


func test_peak_speed_matches_data() -> void:
	var peak: float = 0.0
	for i: int in 2001:
		peak = maxf(peak, model.launch_velocity(i / 2000.0).length())
	assert_almost_eq(peak, model.launch_speed, 0.01)


func test_swing_duration_does_not_change_shots() -> void:
	var slow := TrebuchetModel.from_dict(Data.trebuchet)
	slow.swing_duration *= 2.0
	assert_eq(slow.launch_velocity(0.6), model.launch_velocity(0.6))


func test_useful_window_sweeps_from_lob_to_flat() -> void:
	# Releasing later in the window throws flatter.
	var prev: float = 999.0
	var p: float = 0.5
	while p <= 0.66:
		var ang: float = rad_to_deg(model.launch_velocity(p).angle())
		assert_lt(ang, prev, "launch angle should fall as p grows (p=%s)" % p)
		prev = ang
		p += 0.02
	var lob: Vector2 = model.launch_velocity(0.5)
	assert_gt(rad_to_deg(lob.angle()), 60.0)
	assert_gt(lob.x, 0.0, "a lob still goes forwards")


func test_payload_never_below_ground() -> void:
	for i: int in 101:
		assert_gte(model.projectile_pos(i / 100.0).y, 0.0)


func test_speed_scale_is_linear() -> void:
	assert_eq(model.launch_velocity(0.6, 0.5), model.launch_velocity(0.6) * 0.5)
