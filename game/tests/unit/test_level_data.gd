# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## LevelData is the gatekeeper for campaign, editor and shared levels, so it
## must accept good data and reject bad data with a message, never crash.


func _minimal() -> Dictionary:
	return {
		"format": "level",
		"version": 1,
		"id": "test-level",
		"name": "Test",
		"time_of_day": "noon",
		"realm": "greenmantle",
		"world": {"right": 40, "kill_y": -10},
		"trebuchet": {"x": 0, "y": 0},
		"terrain": [{"points": [[-10, 0], [50, 0]], "style": "grass"}],
		"blocks": [{"shape": "rect", "material": "wood", "pos": [20, 1], "size": [0.3, 2]}],
		"enemies": [{"type": "king", "pos": [20, 3]}],
	}


func _parse(d: Dictionary) -> LevelData:
	return Data.parse_level(d)


func test_minimal_level_is_valid() -> void:
	var lv := _parse(_minimal())
	assert_true(lv.is_valid(), "; ".join(lv.errors))
	assert_eq(lv.blocks.size(), 1)
	assert_eq(lv.blocks[0]["pos"], Vector2(20, 1))
	assert_eq(int(lv.par["gold"]), 1, "default par when missing")


func test_every_campaign_level_is_valid() -> void:
	var ids: PackedStringArray = Data.campaign_levels()
	assert_gt(ids.size(), 0)
	for id: String in ids:
		var lv: LevelData = Data.load_level(id)
		assert_true(lv.is_valid(), "%s: %s" % [id, "; ".join(lv.errors)])
		assert_eq(lv.id, id, "file id must match its realm entry")


func test_rejects_wrong_format_and_version() -> void:
	var d := _minimal()
	d["format"] = "save"
	assert_false(_parse(d).is_valid())
	d = _minimal()
	d["version"] = 99
	var lv := _parse(d)
	assert_false(lv.is_valid())
	assert_string_contains(lv.errors[0], "version")


func test_rejects_unknown_material_and_enemy() -> void:
	var d := _minimal()
	(d["blocks"] as Array)[0]["material"] = "cheese"
	assert_false(_parse(d).is_valid())
	d = _minimal()
	(d["enemies"] as Array)[0]["type"] = "dragon"
	assert_false(_parse(d).is_valid())


func test_rejects_level_without_targets() -> void:
	var d := _minimal()
	d["enemies"] = [{"type": "hostage", "pos": [20, 3]}]
	var lv := _parse(d)
	assert_false(lv.is_valid())


func test_rejects_concave_poly_and_bad_sizes() -> void:
	var d := _minimal()
	d["blocks"] = [
		{
			"shape": "poly",
			"material": "stone",
			"pos": [20, 1],
			"points": [[0, 0], [2, 0], [1, 0.2], [2, 2], [0, 2]]
		}
	]
	assert_false(_parse(d).is_valid(), "concave polygon")
	d = _minimal()
	(d["blocks"] as Array)[0]["size"] = [0.0, 2]
	assert_false(_parse(d).is_valid(), "zero width")


func test_rejects_unordered_terrain() -> void:
	var d := _minimal()
	d["terrain"] = [{"points": [[10, 0], [5, 0]]}]
	assert_false(_parse(d).is_valid())


func test_rejects_bad_par_order() -> void:
	var d := _minimal()
	d["par"] = {"gold": 3, "silver": 2, "bronze": 4}
	assert_false(_parse(d).is_valid())


func test_survives_garbage_types() -> void:
	var d := _minimal()
	d["blocks"] = "lots"
	d["enemies"] = [42, null, {"type": "king"}]
	d["terrain"] = [{"points": "flat"}]
	var lv := _parse(d)
	assert_false(lv.is_valid())
	assert_gt(lv.errors.size(), 1)
