# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Units
extends RefCounted
## Conversions between data space (metres, y up) and Godot 2D space
## (pixels, y down). 1 m = 100 px, matching Rapier's length_unit_2d.

const PX_PER_M: float = 100.0
const GRAVITY_M: float = 9.8
const TICKS_PER_SECOND: int = 60


static func to_px(v: Vector2) -> Vector2:
	return Vector2(v.x * PX_PER_M, -v.y * PX_PER_M)


static func to_m(v: Vector2) -> Vector2:
	return Vector2(v.x / PX_PER_M, -v.y / PX_PER_M)


## Data rotation (degrees, counter-clockwise) to Godot rotation (radians, clockwise).
static func rot_to_godot(deg_ccw: float) -> float:
	return -deg_to_rad(deg_ccw)


static func vec2(a: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		var arr: Array = a
		return Vector2(float(arr[0]), float(arr[1]))
	return fallback


static func color(hex: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if hex is String and Color.html_is_valid(hex as String):
		return Color.html(hex as String)
	return fallback
