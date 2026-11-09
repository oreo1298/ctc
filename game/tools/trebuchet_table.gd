# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends SceneTree
## Prints launch angle / speed / ideal range against swing phase, for tuning
## game/data/trebuchet.json. Run:
##   scripts/godot.sh --headless --path game -s tools/trebuchet_table.gd


func _init() -> void:
	var model := TrebuchetModel.new()
	if FileAccess.file_exists("res://data/trebuchet.json"):
		var d: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/trebuchet.json")
		)
		if d is Dictionary:
			model = TrebuchetModel.from_dict(d)
	print("   p   time  angle  speed   height  range")
	var p: float = 0.30
	while p <= 1.0001:
		var v: Vector2 = model.launch_velocity(p)
		print(
			(
				"%5.3f %5.2fs %6.1f %6.1f %7.2f %7.1f"
				% [
					p,
					p * model.swing_duration,
					rad_to_deg(v.angle()),
					v.length(),
					model.projectile_pos(p).y,
					model.ideal_range(p),
				]
			)
		)
		p += 0.025
	quit()
