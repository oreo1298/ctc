# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Slow motion must never change the physics step (docs/DESIGN.md §8.2).


func after_each() -> void:
	Effects.reset_time()


func test_step_stays_one_sixtieth() -> void:
	var was: bool = Settings.slow_motion
	Settings.slow_motion = true
	for scale: float in [0.25, 0.3, 0.5]:
		Effects.slow_motion(scale, 0.5)
		assert_lt(Engine.time_scale, 1.0, "slow motion engaged")
		assert_almost_eq(Engine.time_scale / Engine.physics_ticks_per_second, 1.0 / 60.0, 1e-9)
	Settings.slow_motion = was


func test_disabled_by_setting() -> void:
	var was: bool = Settings.slow_motion
	Settings.slow_motion = false
	Effects.slow_motion(0.3, 0.5)
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(Engine.physics_ticks_per_second, 60)
	Settings.slow_motion = was
