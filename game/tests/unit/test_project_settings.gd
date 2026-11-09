# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Guards the engine-level decisions recorded in docs/DESIGN.md §8.


func test_fixed_physics_tick_with_interpolation() -> void:
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60)
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"))


func test_custom_xdg_user_dir() -> void:
	assert_true(ProjectSettings.get_setting("application/config/use_custom_user_dir"))
	var slug: String = ProjectSettings.get_setting("application/config/custom_user_dir_name")
	assert_ne(slug, "")
	assert_true(
		OS.get_user_data_dir().ends_with("/" + slug), "user dir should end with the app slug"
	)


func test_mobile_renderer_with_gl_fallback() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "mobile")
	assert_true(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3"))


func test_wayland_preferred_on_linux() -> void:
	assert_eq(ProjectSettings.get_setting("display/display_server/driver.linuxbsd"), "wayland")
