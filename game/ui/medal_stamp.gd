# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name MedalStamp
extends Control
## A wax-seal style medal drawn procedurally (crisp at any size). Shows a
## crown for gold, two bars for silver, one for bronze, so the medal reads
## without relying on colour alone.

@export var medal: Scoring.Medal = Scoring.Medal.GOLD:
	set(v):
		medal = v
		queue_redraw()
## 0..1 stamp-in animation progress.
var stamp: float = 1.0:
	set(v):
		stamp = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(150, 150)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.42 * lerpf(1.6, 1.0, ease(stamp, 0.4))
	var col: Color = UiTheme.medal_color(medal)
	var ink: Color = UiTheme.INK
	var alpha: float = clampf(stamp * 2.0, 0.0, 1.0)
	# Ribbon tails.
	if medal != Scoring.Medal.NONE:
		for s: float in [-1.0, 1.0]:
			var tail := PackedVector2Array(
				[
					c + Vector2(s * r * 0.25, r * 0.4),
					c + Vector2(s * r * 0.7, r * 1.25),
					c + Vector2(s * r * 0.48, r * 1.12),
					c + Vector2(s * r * 0.36, r * 1.32),
					c + Vector2(s * r * -0.05, r * 0.55),
				]
			)
			draw_colored_polygon(tail, Color(UiTheme.ACCENT, alpha))
			draw_polyline(tail + PackedVector2Array([tail[0]]), Color(ink, alpha), 3.0, true)
	# Scalloped wax rim.
	var rim := PackedVector2Array()
	for i: int in 72:
		var a: float = TAU * i / 72.0
		var rr: float = r * (1.0 + 0.05 * sin(a * 12.0))
		rim.append(c + Vector2.from_angle(a) * rr)
	draw_colored_polygon(rim, Color(col.darkened(0.1), alpha))
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(ink, alpha), 4.0, true)
	draw_circle(c, r * 0.74, Color(col.lightened(0.18), alpha))
	draw_arc(c, r * 0.74, 0.0, TAU, 64, Color(ink, alpha * 0.8), 3.0, true)
	match medal:
		Scoring.Medal.GOLD:
			var w: float = r * 0.5
			var crown := PackedVector2Array(
				[
					c + Vector2(-w, w * 0.45),
					c + Vector2(-w * 1.05, -w * 0.45),
					c + Vector2(-w * 0.5, -w * 0.05),
					c + Vector2(0, -w * 0.7),
					c + Vector2(w * 0.5, -w * 0.05),
					c + Vector2(w * 1.05, -w * 0.45),
					c + Vector2(w, w * 0.45),
				]
			)
			draw_colored_polygon(crown, Color(ink, alpha))
		Scoring.Medal.SILVER:
			for k: int in 2:
				draw_rect(
					Rect2(
						c + Vector2(-r * 0.36, -r * 0.24 + k * r * 0.3), Vector2(r * 0.72, r * 0.17)
					),
					Color(ink, alpha)
				)
		Scoring.Medal.BRONZE:
			draw_rect(
				Rect2(c + Vector2(-r * 0.36, -r * 0.085), Vector2(r * 0.72, r * 0.17)),
				Color(ink, alpha)
			)
		_:
			draw_arc(c, r * 0.35, 0.0, TAU, 32, Color(ink, alpha * 0.6), 5.0, true)
