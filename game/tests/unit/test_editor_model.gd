# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Castle editor operations.

const PLANK: Dictionary = {"shape": "rect", "size": [2.0, 0.3]}
const PILLAR: Dictionary = {"shape": "rect", "size": [0.3, 1.6]}

var m: EditorModel


func before_each() -> void:
	m = EditorModel.new()
	m.load_doc(EditorModel.new_level())


func test_blocks_settle_on_the_ground_and_on_each_other() -> void:
	var a: Dictionary = m.add_block(PILLAR, "stone", Vector2(30, 5))
	assert_almost_eq(
		EditorModel.aabb_m(m.blocks()[a["i"]]).position.y, 0.0, 0.002, "pillar on the ground"
	)
	var b: Dictionary = m.add_block(PLANK, "wood", Vector2(30, 9))
	assert_almost_eq(
		EditorModel.aabb_m(m.blocks()[b["i"]]).position.y, 1.6, 0.002, "plank on the pillar"
	)


func test_people_stand_on_surfaces() -> void:
	m.add_block({"shape": "rect", "size": [3.0, 1.0]}, "stone", Vector2(30, 0))
	var k: Dictionary = m.add_enemy("king", Vector2(30, 4))
	assert_almost_eq(Units.vec2(m.enemies()[k["i"]]["pos"]).y, 1.0 + 0.55, 0.002)


func test_undo_redo() -> void:
	m.add_block(PLANK, "wood", Vector2(25, 0))
	m.add_block(PLANK, "wood", Vector2(28, 0))
	assert_eq(m.blocks().size(), 2)
	m.undo()
	assert_eq(m.blocks().size(), 1)
	m.redo()
	assert_eq(m.blocks().size(), 2)


func test_rotate_resize_duplicate_delete() -> void:
	var s: Dictionary = m.add_block(PLANK, "wood", Vector2(30, 0))
	m.rotate(s, 2)
	assert_almost_eq(float(m.blocks()[0]["rot"]), 30.0, 0.001)
	m.rotate(s, -2)
	assert_false(m.blocks()[0].has("rot"), "back to zero")
	m.resize(s, 0, 0.5)
	assert_almost_eq(float(m.blocks()[0]["size"][0]), 2.5, 0.001)
	var d: Dictionary = m.duplicate_sel(s)
	assert_eq(m.blocks().size(), 2)
	m.delete(d)
	assert_eq(m.blocks().size(), 1)


func test_pick_prefers_people_over_blocks() -> void:
	m.add_block({"shape": "rect", "size": [3.0, 2.0]}, "stone", Vector2(30, 0))
	var k: Dictionary = m.add_enemy("knight", Vector2(30, 3))
	var pos: Vector2 = Units.vec2(m.enemies()[k["i"]]["pos"])
	assert_eq(m.pick(pos)["kind"], "enemy")
	assert_eq(m.pick(Vector2(29.0, 1.0))["kind"], "block")
	assert_true(m.pick(Vector2(10, 10)).is_empty())


func test_terrain_points_insert_and_stay_ordered() -> void:
	var p: Dictionary = m.insert_point(Vector2(20, 0.2))
	assert_eq(p["kind"], "point")
	m.move(p, Vector2(-100, 3.0))
	var pts: Array = m.doc["terrain"][0]["points"]
	assert_gt(float(pts[1][0]), float(pts[0][0]), "points cannot cross their neighbours")


func test_validation_requires_a_target() -> void:
	m.add_block(PLANK, "wood", Vector2(30, 0))
	assert_false(m.validate().is_empty())
	m.add_enemy("king", Vector2(30, 1))
	assert_true(m.validate().is_empty(), "; ".join(m.validate()))


func test_stacking_on_the_upper_half_of_a_block() -> void:
	m.add_block({"shape": "rect", "size": [2.0, 1.0]}, "stone", Vector2(30, 0))
	# Dropped with its centre inside the top half of the block: it stacks.
	var c: Dictionary = m.add_block({"shape": "rect", "size": [0.6, 0.6]}, "wood", Vector2(30, 0.8))
	assert_almost_eq(EditorModel.aabb_m(m.blocks()[c["i"]]).position.y, 1.0, 0.002)


func test_anchors_stay_where_they_are_put() -> void:
	var s: Dictionary = m.add_block(PLANK, "stone", Vector2(30, 0))
	m.toggle_static(s)
	m.move(s, Vector2(30, 4), true)
	assert_almost_eq(Units.vec2(m.blocks()[0]["pos"]).y, 4.0, 0.001, "anchor floats")
	m.toggle_static(s)
	assert_false(m.blocks()[0].has("static"))


func test_ghost_preview_matches_placement() -> void:
	m.add_block(PILLAR, "stone", Vector2(30, 0))
	var g: Dictionary = m.preview_block(PLANK, "wood", Vector2(30, 5))
	var s: Dictionary = m.add_block(PLANK, "wood", Vector2(30, 5))
	assert_eq(Units.vec2(g["pos"]), Units.vec2(m.blocks()[s["i"]]["pos"]))
	assert_eq(m.preview_enemy("king", Vector2(10, 5)), Vector2(10, 0.55))


func test_par_is_kept_for_cosmetic_edits_and_cleared_by_real_ones() -> void:
	m.add_block(PLANK, "wood", Vector2(30, 0))
	m.add_enemy("king", Vector2(30, 1))
	assert_true(m.record_par(2))
	assert_false(m.record_par(3), "a worse run is not a record")
	assert_true(m.record_par(1))
	assert_eq(int(m.doc["par"]["gold"]), 1)
	m.set_meta_field("name", "Renamed")
	m.set_meta_field("time_of_day", "night")
	assert_true(m.doc.has("par"), "renaming keeps the record")
	m.rotate({"kind": "block", "i": 0}, 1)
	assert_false(m.doc.has("par"), "changing the castle clears it")


func test_overlaps_and_problems() -> void:
	assert_eq(
		m.problems()["blocking"][0],
		tr("Place a king, queen or knight to defeat."),
		"needs a target"
	)
	m.add_enemy("hostage", Vector2(20, 0))
	assert_false((m.problems()["blocking"] as PackedStringArray).is_empty(), "hostages don't count")
	m.add_enemy("knight", Vector2(22, 0))
	assert_true((m.problems()["blocking"] as PackedStringArray).is_empty())
	var a: Dictionary = m.add_block(PLANK, "wood", Vector2(30, 0))
	var b: Dictionary = m.add_block(PLANK, "wood", Vector2(31, 0.3))
	assert_true(m.overlaps().is_empty(), "the second plank stacked on the first")
	m.move(b, Vector2(30.5, 0.15), false)
	assert_eq(m.overlaps(), [Vector2i(a["i"], b["i"])] as Array[Vector2i])
	assert_false((m.problems()["warnings"] as PackedStringArray).is_empty())


func test_world_width_is_clamped() -> void:
	m.set_world_right(500.0)
	assert_eq(float(m.doc["world"]["right"]), EditorModel.MAX_WORLD_RIGHT)
	m.set_world_right(1.0)
	assert_eq(float(m.doc["world"]["right"]), EditorModel.MIN_WORLD_RIGHT)
