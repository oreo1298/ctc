# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## The castle editor driven with real input events: place, select, drag,
## undo, keyboard shortcuts and autosave.

const DIR: String = "user://test-editor-scene"

var ed: Node2D


func before_each() -> void:
	CustomLevels.dir_override = DIR
	_wipe()
	Game.editor = null
	ed = (load("res://scenes/editor/editor.tscn") as PackedScene).instantiate()
	add_child_autofree(ed)
	await wait_physics_frames(2)


func after_each() -> void:
	Game.editor = null
	_wipe()
	CustomLevels.dir_override = ""


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(DIR)


func _screen(m: Vector2) -> Vector2:
	return ed.get_viewport().get_canvas_transform() * Units.to_px(m)


func _click(m: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = _screen(m)
		ed._unhandled_input(e)


func _drag(from_m: Vector2, to_m: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = _screen(from_m)
	ed._unhandled_input(e)
	var last: Vector2 = e.position
	for k: int in range(1, 6):
		var mv := InputEventMouseMotion.new()
		mv.position = _screen(from_m.lerp(to_m, k / 5.0))
		mv.relative = mv.position - last
		last = mv.position
		ed._unhandled_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = last
	ed._unhandled_input(up)


func _key(code: Key, ctrl: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	ed._unhandled_input(e)


func _preset(id: String) -> Dictionary:
	for p: Variant in Data.editor.get("presets", []):
		if str((p as Dictionary).get("id", "")) == id:
			return p
	return {}


func test_starts_with_an_empty_hill() -> void:
	var model: EditorModel = Game.editor
	assert_not_null(model)
	assert_true(model.blocks().is_empty())
	assert_false((model.problems()["blocking"] as PackedStringArray).is_empty())


func test_place_stack_and_people() -> void:
	var model: EditorModel = Game.editor
	ed.palette.preset_chosen.emit(_preset("block"))
	_click(Vector2(30, 3))
	assert_eq(model.blocks().size(), 1, "placed a block")
	var top: float = EditorModel.aabb_m(model.blocks()[0]).end.y
	ed.palette.person_chosen.emit("king")
	_click(Vector2(30, top - 0.1))
	assert_eq(model.enemies().size(), 1)
	assert_almost_eq(Units.vec2(model.enemies()[0]["pos"]).y, top + 0.55, 0.01, "king on top")
	assert_true((model.problems()["blocking"] as PackedStringArray).is_empty(), "playable")


func test_select_drag_undo_and_keys() -> void:
	var model: EditorModel = Game.editor
	ed.palette.preset_chosen.emit(_preset("plank"))
	_click(Vector2(30, 1))
	_click(Vector2(0, 0), MOUSE_BUTTON_RIGHT)
	assert_eq(ed.tool, ed.Tool.SELECT, "right click returns to Select")
	_drag(Vector2(30, 0.15), Vector2(34, 2))
	var p: Vector2 = Units.vec2(model.blocks()[0]["pos"])
	assert_almost_eq(p.x, 34.0, 0.06, "dragged")
	assert_almost_eq(p.y, 0.15, 0.01, "and settled back onto the ground")
	_key(KEY_Z, true)
	assert_almost_eq(Units.vec2(model.blocks()[0]["pos"]).x, 30.0, 0.06, "undo")
	_click(Vector2(30, 0.15))
	assert_eq(str(ed.sel.get("kind", "")), "block")
	_key(KEY_Q)
	assert_almost_eq(float(model.blocks()[0].get("rot", 0.0)), 15.0, 0.001, "Q turns")
	_key(KEY_D, true)
	assert_eq(model.blocks().size(), 2, "Ctrl+D copies")
	_key(KEY_DELETE)
	assert_eq(model.blocks().size(), 1, "Del deletes")


func test_ground_tool_adds_and_moves_points() -> void:
	var model: EditorModel = Game.editor
	ed.palette.tool_chosen.emit("terrain")
	var before: int = (model.doc["terrain"][0]["points"] as Array).size()
	_drag(Vector2(20, 0), Vector2(20, 3))
	var pts: Array = model.doc["terrain"][0]["points"]
	assert_eq(pts.size(), before + 1, "a click on the ground adds a point")
	assert_almost_eq(Units.vec2(pts[1]).y, 3.0, 0.06, "and dragging raises it")
	assert_true(Data.parse_level(model.doc).errors.size() <= 1, "terrain stays valid")


func test_autosave_and_share_round_trip() -> void:
	var model: EditorModel = Game.editor
	ed.palette.preset_chosen.emit(_preset("pillar"))
	_click(Vector2(30, 1))
	ed.palette.person_chosen.emit("knight")
	_click(Vector2(32, 1))
	ed._save_now()
	assert_eq(CustomLevels.list().size(), 1, "saved to the castle folder")
	var r: Dictionary = ShareCode.decode(ShareCode.encode(model.doc))
	assert_true(r["ok"])
	assert_eq((r["level"]["blocks"] as Array).size(), 1)
	assert_true(Data.parse_level(r["level"]).is_valid())
