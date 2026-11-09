# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node2D
## The castle editor. Pick a shape, material or person on the left and click
## to place it; things settle onto what is below them. Select to drag,
## turn, resize, copy or delete; "Ground" edits the terrain. Castles save
## themselves to user://levels as you work, test-play with one button, and
## share as a short code or a .json file. All of it works offline.
##
## Mouse: left = place/select/drag, wheel = zoom, right or middle drag =
## pan, right click = back to Select. Touch: tap/drag, two fingers pan and
## pinch. Keys: Q/E turn, Del delete, Ctrl+D copy, F flip, arrows nudge,
## Ctrl+Z/Ctrl+Y undo/redo, Home frames the castle, F5 test-plays.

enum Tool { SELECT, PLACE, TERRAIN }

const ZOOM_MIN: float = 0.16
const ZOOM_MAX: float = 1.6
const SAVE_DELAY: float = 0.8
const DRAG_THRESHOLD: float = 6.0
const NUDGE: float = 0.05
const TIMES: Array[String] = ["dawn", "morning", "noon", "afternoon", "golden", "dusk", "night"]
const STYLES: Array[String] = ["grass", "sand", "snow", "rock"]

## Camera kept across test-play: {"id", "pos", "zoom"}.
static var _cam_memory: Dictionary = {}

var model: EditorModel
var view: EditorView
var cam: Camera2D
var ui: Control
var palette: EditorPalette
var tool: Tool = Tool.SELECT
var place_preset: Dictionary = {}
var place_person: String = ""
var sel: Dictionary = {}

var _drag: String = ""
var _drag_started: bool = false
var _drag_offset := Vector2.ZERO
var _press_screen := Vector2.ZERO
var _pan_moved: bool = false
var _touches: Dictionary = {}
var _pinch_dist: float = 0.0
var _pinch_center := Vector2.ZERO
var _save_t: float = -1.0

var _undo_btn: Button
var _redo_btn: Button
var _title_btn: Button
var _status: Label
var _toast: Label
var _toast_tw: Tween = null
var _sel_bar: PanelContainer
var _sel_buttons: Dictionary = {}
var _modal: Control = null
var _modal_error: Label = null
var _dialog: FileDialog = null


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if Game.editor == null:
		Game.editor = EditorModel.new()
		var saved: Array[Dictionary] = CustomLevels.list()
		var doc: Dictionary = (
			CustomLevels.load_level(str(saved[0]["id"])) if not saved.is_empty() else {}
		)
		Game.editor.load_doc(doc if not doc.is_empty() else EditorModel.new_level())
	model = Game.editor
	Game.custom_from_editor = false
	if Game.cli.has("edit") and not Game.cli.has("_edit_loaded"):
		# Dev/screenshot hook: open a campaign level as a new castle.
		Game.cli["_edit_loaded"] = true
		var lv: Dictionary = Data.load_level(str(Game.cli["edit"])).source.duplicate(true)
		if not lv.is_empty():
			lv["id"] = CustomLevels.unique_id()
			model.load_doc(lv)
	view = EditorView.new()
	view.model = model
	add_child(view)
	cam = Camera2D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.make_current()
	_build_ui()
	model.changed.connect(_on_changed)
	view.refresh()
	if str(_cam_memory.get("id", "")) == str(model.doc.get("id", "-")):
		cam.position = _cam_memory["pos"]
		cam.zoom = _cam_memory["zoom"]
	else:
		_frame_all.call_deferred()
	_update_ui()
	if model.blocks().is_empty() and model.enemies().is_empty():
		_toast_msg(tr("Pick a block on the left, then click to place it."), 5.0)
	_dev_options.call_deferred()


## Screenshot hooks: --edit-select=N (block N), --edit-tool=terrain,
## --edit-dialog=share|castles|settings, --edit-test (test-play at once).
func _dev_options() -> void:
	if Game.cli.has("edit-select"):
		_select({"kind": "block", "i": int(str(Game.cli["edit-select"]))})
	if str(Game.cli.get("edit-tool", "")) == "terrain":
		palette.show_mode("terrain", "")
		_on_tool("terrain")
	if Game.cli.has("edit-test") and not Game.cli.has("_edit_tested"):
		Game.cli["_edit_tested"] = true
		_test_play()
	match str(Game.cli.get("edit-dialog", "")):
		"share":
			_open_share()
		"castles":
			_open_castles()
		"settings":
			_open_settings()


func _exit_tree() -> void:
	_save_now()
	_cam_memory = {"id": str(model.doc.get("id", "")), "pos": cam.position, "zoom": cam.zoom}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_now()


func _process(delta: float) -> void:
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_now()


# ------------------------------------------------------------------- UI ---
func _build_ui() -> void:
	var s: float = minf(Settings.text_scale, 1.25)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UiTheme.build(Settings.text_scale)
	layer.add_child(ui)
	UiTheme.fit_safe_area(ui)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top"]:
		top_margin.add_theme_constant_override("margin_" + side, 12)
	ui.add_child(top_margin)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top)
	top.add_child(_button(tr("Back"), _go_back, tr("Back to the main menu (your castle is saved)")))
	_undo_btn = _button(tr("Undo"), model.undo, tr("Undo (Ctrl+Z)"))
	top.add_child(_undo_btn)
	_redo_btn = _button(tr("Redo"), model.redo, tr("Redo (Ctrl+Y)"))
	top.add_child(_redo_btn)
	top.add_child(_spacer())
	_title_btn = _button("", _open_settings, tr("Name, sky, scenery and size"))
	_title_btn.theme_type_variation = "HudButton"
	_title_btn.clip_text = true
	_title_btn.custom_minimum_size.x = 200 * s
	top.add_child(_title_btn)
	top.add_child(_spacer())
	top.add_child(
		_button(tr("Castles"), _open_castles, tr("Your castles, and opening shared ones"))
	)
	top.add_child(_button(tr("Share"), _open_share, tr("A code or file for friends")))
	var play := _button(tr("Test"), _test_play, tr("Play your castle (F5)"))
	play.theme_type_variation = "BigButton"
	top.add_child(play)

	palette = EditorPalette.new()
	palette.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	palette.offset_left = 12
	palette.offset_top = 84 * s
	palette.offset_bottom = -12
	palette.custom_minimum_size.x = 290 * s
	var pal_style: StyleBoxFlat = UiTheme.panel_style(UiTheme.PAPER, 3, 18)
	pal_style.set_content_margin_all(14)
	palette.add_theme_stylebox_override("panel", pal_style)
	ui.add_child(palette)
	palette.tool_chosen.connect(_on_tool)
	palette.preset_chosen.connect(_on_preset)
	palette.person_chosen.connect(_on_person)
	palette.material_chosen.connect(_on_material)

	# The free area right of the palette holds the toast and the piece bar.
	var free := Control.new()
	free.set_anchors_preset(Control.PRESET_FULL_RECT)
	free.offset_left = 12 + palette.custom_minimum_size.x + 12
	free.offset_top = 84 * s
	free.offset_right = -12
	free.offset_bottom = -12
	free.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(free)

	_sel_bar = PanelContainer.new()
	_sel_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sel_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sel_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sel_bar.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.PAPER, 3, 16))
	free.add_child(_sel_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_sel_bar.add_child(row)
	for spec: Array in [
		["ccw", "rotate_left", _rotate.bind(1), tr("Turn left (Q)")],
		["cw", "rotate_right", _rotate.bind(-1), tr("Turn right (E)")],
		["wider", "wider", _resize.bind(0, 0.1), tr("Wider")],
		["narrower", "narrower", _resize.bind(0, -0.1), tr("Narrower")],
		["taller", "taller", _resize.bind(1, 0.1), tr("Taller")],
		["shorter", "shorter", _resize.bind(1, -0.1), tr("Shorter")],
		["bigger", "bigger", _resize.bind(0, 0.1), tr("Bigger")],
		["smaller", "smaller", _resize.bind(0, -0.1), tr("Smaller")],
		["flip", "flip", _flip, tr("Face the other way (F)")],
		["anchor", "anchor", _toggle_anchor, tr("Anchor: never moves or breaks (A)")],
		["copy", "copy", _duplicate, tr("Copy (Ctrl+D)")],
		["delete", "delete", _delete, tr("Delete (Del)")],
	]:
		var b := _button("", spec[2], str(spec[3]))
		b.theme_type_variation = "ToolButton"
		b.icon = load("res://art/ui/editor/%s.svg" % spec[1]) as Texture2D
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(56, 56) * s
		row.add_child(b)
		_sel_buttons[spec[0]] = b
	(_sel_buttons["anchor"] as Button).toggle_mode = true

	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override(
		"panel", UiTheme.panel_style(Color(UiTheme.PAPER, 0.92), 2, 12)
	)
	free.add_child(status_panel)
	_status = Label.new()
	_status.theme_type_variation = "SmallLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 330 * s
	status_panel.add_child(_status)

	_toast = Label.new()
	_toast.theme_type_variation = "HudLabel"
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = -160 * s
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	free.add_child(_toast)


func _button(text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: Sfx.play_ui("ui_click", -8.0))
	b.pressed.connect(cb)
	return b


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _toast_msg(text: String, secs: float = 2.6) -> void:
	_toast.text = text
	if _toast_tw != null:
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(secs)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _update_ui() -> void:
	_validate_sel()
	_undo_btn.disabled = not model.can_undo()
	_redo_btn.disabled = not model.can_redo()
	_title_btn.text = str(model.doc.get("name", ""))
	var kind: String = str(sel.get("kind", ""))
	_sel_bar.visible = kind == "block" or kind == "enemy"
	var round_block: bool = false
	var b: Dictionary = {}
	if kind == "block":
		b = model.blocks()[int(sel["i"])]
		round_block = str(b.get("shape", "")) == "circle"
	var shown: Dictionary = {
		"ccw": kind == "block" and not round_block,
		"cw": kind == "block" and not round_block,
		"wider": kind == "block" and not round_block,
		"narrower": kind == "block" and not round_block,
		"taller": kind == "block" and not round_block,
		"shorter": kind == "block" and not round_block,
		"bigger": round_block,
		"smaller": round_block,
		"flip": kind == "enemy",
		"anchor": kind == "block",
		"copy": true,
		"delete": true,
	}
	for k: String in shown:
		(_sel_buttons[k] as Button).visible = bool(shown[k])
	(_sel_buttons["anchor"] as Button).set_pressed_no_signal(bool(b.get("static", false)))
	_update_status()
	view.selection = sel
	view.show_points = tool == Tool.TERRAIN
	view.redraw_overlay()


func _update_status() -> void:
	var pr: Dictionary = model.problems()
	var blocking: PackedStringArray = pr["blocking"]
	var warnings: PackedStringArray = pr["warnings"]
	if tool == Tool.TERRAIN and blocking.is_empty():
		_status.text = tr("Drag a point to shape the ground. Click the ground to add a point.")
		_status.add_theme_color_override("font_color", UiTheme.INK)
		return
	if not blocking.is_empty():
		_status.text = blocking[0]
		_status.add_theme_color_override("font_color", UiTheme.ACCENT)
		return
	var text: String = (
		tr("Ready to test. Blocks: %d · People: %d")
		% [model.blocks().size(), model.enemies().size()]
	)
	var par: Dictionary = model.doc.get("par", {})
	if not par.is_empty():
		var g: int = int(par.get("gold", 0))
		text += "\n" + tr_n("Your record: %d shot", "Your record: %d shots", g) % g
	else:
		text += "\n" + tr("Beat it in Test to set its medals.")
	if not warnings.is_empty():
		text += "\n" + warnings[0]
	_status.text = text
	_status.add_theme_color_override("font_color", UiTheme.INK)


func _validate_sel() -> void:
	var kind: String = str(sel.get("kind", ""))
	var ok: bool = true
	if kind == "block":
		ok = int(sel["i"]) < model.blocks().size()
	elif kind == "enemy":
		ok = int(sel["i"]) < model.enemies().size()
	elif kind == "point":
		var terrain: Array = model.doc.get("terrain", [])
		ok = (
			int(sel["i"]) < terrain.size()
			and int(sel["j"]) < ((terrain[int(sel["i"])] as Dictionary)["points"] as Array).size()
		)
	if not ok:
		sel = {}


# -------------------------------------------------------------- changes ---
func _on_changed() -> void:
	view.refresh()
	_update_ui()
	_save_t = SAVE_DELAY


func _save_now() -> void:
	_save_t = -1.0
	if model == null or (model.blocks().is_empty() and model.enemies().is_empty()):
		return
	if Game.cli.has("no-save"):
		return
	CustomLevels.save_level(model.doc)


func _select(s: Dictionary) -> void:
	sel = s
	_update_ui()


# ---------------------------------------------------------------- tools ---
func _on_tool(t: String) -> void:
	tool = Tool.TERRAIN if t == "terrain" else Tool.SELECT
	place_preset = {}
	place_person = ""
	view.ghost = {}
	if tool == Tool.TERRAIN:
		sel = {}
	_update_ui()


func _on_preset(preset: Dictionary) -> void:
	tool = Tool.PLACE
	place_preset = preset
	place_person = ""
	view.hover = {}
	_update_ui()


func _on_person(type: String) -> void:
	tool = Tool.PLACE
	place_preset = {}
	place_person = type
	view.hover = {}
	_update_ui()


func _on_material(id: String) -> void:
	if str(sel.get("kind", "")) == "block":
		model.set_material(sel, id)
	if tool == Tool.PLACE:
		view.ghost = {}
		view.redraw_overlay()


func _back_to_select() -> void:
	palette.show_mode("select", "")
	_on_tool("select")


func _rotate(steps: int) -> void:
	model.rotate(sel, steps)


func _resize(axis: int, delta: float) -> void:
	model.resize(sel, axis, delta)


func _flip() -> void:
	model.flip(sel)


func _toggle_anchor() -> void:
	model.toggle_static(sel)


func _duplicate() -> void:
	_select(model.duplicate_sel(sel))


func _delete() -> void:
	var s: Dictionary = sel
	sel = {}
	model.delete(s)
	_update_ui()


func _nudge(d: Vector2) -> void:
	var kind: String = str(sel.get("kind", ""))
	if kind.is_empty():
		cam.position += Vector2(d.x, -d.y) * 40.0 / cam.zoom.x
		_clamp_cam()
		return
	model.checkpoint()
	model.move(sel, _item_pos(sel) + d * NUDGE, false)


func _item_pos(s: Dictionary) -> Vector2:
	match str(s.get("kind", "")):
		"block":
			return Units.vec2(model.blocks()[int(s["i"])]["pos"])
		"enemy":
			return Units.vec2(model.enemies()[int(s["i"])]["pos"])
		"point":
			return Units.vec2(model.doc["terrain"][int(s["i"])]["points"][int(s["j"])])
	return Vector2.ZERO


func _place(m: Vector2) -> void:
	if not place_preset.is_empty():
		_select(model.add_block(place_preset, palette.current_material, m))
		Sfx.play_ui(palette.current_material + "_hit", -10.0)
	elif not place_person.is_empty():
		_select(model.add_enemy(place_person, m))
		Sfx.play_ui("thud", -10.0)


func _update_ghost(m: Vector2) -> void:
	if not place_preset.is_empty():
		view.ghost = {"block": model.preview_block(place_preset, palette.current_material, m)}
	elif not place_person.is_empty():
		view.ghost = {"enemy": place_person, "pos": model.preview_enemy(place_person, m)}
	view.redraw_overlay()


# ---------------------------------------------------------------- input ---
func _to_m(screen: Vector2) -> Vector2:
	return Units.to_m(get_viewport().get_canvas_transform().affine_inverse() * screen)


func _point_radius() -> float:
	return 22.0 / cam.zoom.x / Units.PX_PER_M


func _unhandled_input(event: InputEvent) -> void:
	if _modal != null:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_modal()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch(event)
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, g.factor)
	elif event is InputEventPanGesture:
		cam.position += (event as InputEventPanGesture).delta * 24.0 / cam.zoom.x
		_clamp_cam()
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.is_pressed():
		_key(event as InputEventKey)


func _mouse_button(e: InputEventMouseButton) -> void:
	get_viewport().set_input_as_handled()
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 1.12)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.0 / 1.12)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_drag = "pan"
				_pan_moved = false
			else:
				if e.button_index == MOUSE_BUTTON_RIGHT and not _pan_moved:
					_cancel()
				_drag = ""
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press(e.position)
			else:
				_release(e.position)


func _press(screen: Vector2) -> void:
	if _touches.size() >= 2:
		return
	var m: Vector2 = _to_m(screen)
	_press_screen = screen
	_drag_started = false
	_pan_moved = false
	match tool:
		Tool.PLACE:
			_place(m)
			_drag = ""
		Tool.TERRAIN:
			var hit: Dictionary = model.pick(m, _point_radius(), true)
			if str(hit.get("kind", "")) != "point":
				hit = model.insert_point(m)
				_drag_started = not hit.is_empty()
			if hit.is_empty():
				_select({})
				_drag = "pan"
			else:
				_select(hit)
				_drag = "item"
				_drag_offset = _item_pos(hit) - m
		Tool.SELECT:
			var hit: Dictionary = model.pick(m)
			if hit.is_empty():
				_select({})
				_drag = "pan"
			else:
				_select(hit)
				_drag = "item"
				_drag_offset = _item_pos(hit) - m


func _release(screen: Vector2) -> void:
	if _drag == "item" and _drag_started:
		model.move(sel, _to_m(screen) + _drag_offset, true)
	_drag = ""


func _mouse_motion(e: InputEventMouseMotion) -> void:
	var m: Vector2 = _to_m(e.position)
	if _drag == "pan":
		cam.position -= e.relative / cam.zoom.x
		_pan_moved = _pan_moved or e.relative.length() > 0.5
		_clamp_cam()
	elif _drag == "item":
		if not _drag_started:
			if e.position.distance_to(_press_screen) < DRAG_THRESHOLD:
				return
			_drag_started = true
			model.checkpoint()
		model.move(sel, m + _drag_offset, false)
	elif tool == Tool.PLACE:
		_update_ghost(m)
	else:
		var h: Dictionary = model.pick(m, _point_radius(), tool == Tool.TERRAIN)
		if h != view.hover:
			view.hover = h
			view.redraw_overlay()


func _touch(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() == 2:
			if _drag == "item" and _drag_started:
				model.undo()
			_drag = "pinch"
			_pinch_reset()
		elif _drag == "pinch":
			_drag = ""
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() == 2 and _drag == "pinch":
			var pts: Array = _touches.values()
			var dist: float = (pts[0] as Vector2).distance_to(pts[1])
			var center: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			if _pinch_dist > 1.0:
				_zoom_at(center, dist / _pinch_dist)
			cam.position -= (center - _pinch_center) / cam.zoom.x
			_clamp_cam()
			_pinch_dist = dist
			_pinch_center = center


func _pinch_reset() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	_pinch_center = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _key(e: InputEventKey) -> void:
	var ctrl: bool = e.is_command_or_control_pressed()
	var handled: bool = true
	match e.keycode:
		KEY_Z when ctrl:
			if e.shift_pressed:
				model.redo()
			else:
				model.undo()
		KEY_Y when ctrl:
			model.redo()
		KEY_D when ctrl:
			_duplicate()
		KEY_DELETE, KEY_BACKSPACE:
			_delete()
		KEY_Q:
			_rotate(1)
		KEY_E:
			_rotate(-1)
		KEY_F:
			_flip()
		KEY_V:
			_back_to_select()
		KEY_G:
			palette.show_mode("terrain", "")
			_on_tool("terrain")
		KEY_HOME:
			_frame_all(e.shift_pressed)
		KEY_A when not ctrl:
			_toggle_anchor()
		KEY_F5:
			_test_play()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.2)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 / 1.2)
		KEY_LEFT:
			_nudge(Vector2.LEFT * (10.0 if e.shift_pressed else 1.0))
		KEY_RIGHT:
			_nudge(Vector2.RIGHT * (10.0 if e.shift_pressed else 1.0))
		KEY_UP:
			_nudge(Vector2.UP * -1.0 * (10.0 if e.shift_pressed else 1.0))
		KEY_DOWN:
			_nudge(Vector2.DOWN * -1.0 * (10.0 if e.shift_pressed else 1.0))
		KEY_ESCAPE:
			_cancel(true)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Right click / Esc: leave placing, then drop the selection, then (Esc
## only) leave the editor.
func _cancel(may_leave: bool = false) -> void:
	if tool != Tool.SELECT:
		_back_to_select()
	elif not sel.is_empty():
		_select({})
	elif may_leave:
		_go_back()


# --------------------------------------------------------------- camera ---
func _zoom_at(screen: Vector2, factor: float) -> void:
	var before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen
	var z: float = clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.force_update_scroll()
	var after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen
	cam.position += before - after
	_clamp_cam()
	view.redraw_overlay()


func _clamp_cam() -> void:
	var right: float = view.world_right() * Units.PX_PER_M
	cam.position.x = clampf(cam.position.x, -2500.0, right + 2500.0)
	cam.position.y = clampf(cam.position.y, -4000.0, -view.kill_y() * Units.PX_PER_M)
	cam.force_update_scroll()


## Fit the castle (or, with `whole`, the trebuchet and the whole field) in
## the free area right of the palette.
func _frame_all(whole: bool = false) -> void:
	var r := Rect2()
	var any: bool = false
	for b: Variant in model.blocks():
		r = r.merge(EditorModel.aabb_m(b)) if any else EditorModel.aabb_m(b)
		any = true
	for e: Variant in model.enemies():
		var p: Vector2 = Units.vec2((e as Dictionary).get("pos"))
		r = r.expand(p) if any else Rect2(p, Vector2.ZERO)
		any = true
	if whole or not any:
		r = Rect2(Vector2(-5.0, -1.0), Vector2(view.world_right() + 8.0, 10.0))
		if not whole:
			r = Rect2(
				Vector2(view.world_right() * 0.4, -1.0), Vector2(view.world_right() * 0.6, 9.0)
			)
	else:
		r = r.grow_individual(4.0, 1.0, 4.0, 3.0)
		r = r.expand(Vector2(r.position.x, -1.0))
		if r.size.x < 18.0:
			r = r.grow_individual((18.0 - r.size.x) * 0.5, 0.0, (18.0 - r.size.x) * 0.5, 0.0)
		r.size.y = maxf(r.size.y, 8.0)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var s: float = minf(Settings.text_scale, 1.25)
	var left: float = 24.0 + palette.custom_minimum_size.x + 12.0
	var top: float = 84.0 * s
	var avail := Vector2(vp.x - left - 12.0, vp.y - top - 84.0 * s)
	var z: float = clampf(
		minf(avail.x / (r.size.x * 100.0), avail.y / (r.size.y * 100.0)), ZOOM_MIN, ZOOM_MAX
	)
	cam.zoom = Vector2(z, z)
	var center_px: Vector2 = Units.to_px(r.get_center())
	# Shift so the rect sits in the middle of the free area, not the screen.
	var free_center := Vector2(left + avail.x * 0.5, top + avail.y * 0.5)
	cam.position = center_px - (free_center - vp * 0.5) / z
	cam.force_update_scroll()
	view.redraw_overlay()


# ------------------------------------------------------------ test-play ---
func _test_play() -> void:
	var blocking: PackedStringArray = model.problems()["blocking"]
	if not blocking.is_empty():
		_toast_msg(blocking[0])
		return
	_save_now()
	Game.play_custom(model.doc, true)


func _go_back() -> void:
	_save_now()
	Game.goto_menu()


# --------------------------------------------------------------- modals ---
func _open_modal(title: String, min_width: float = 580.0) -> VBoxContainer:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_modal)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.12, 0.09, 0.07, 0.45)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width * minf(Settings.text_scale, 1.25)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = "HeadingLabel"
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	_modal_error = null
	return box


func _close_modal() -> void:
	if _modal != null:
		_modal.queue_free()
		_modal = null


func _modal_buttons(box: VBoxContainer, buttons: Array[Button]) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for b: Button in buttons:
		row.add_child(b)


func _field(box: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 150 * minf(Settings.text_scale, 1.25)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _error_line(box: VBoxContainer) -> Label:
	_modal_error = Label.new()
	_modal_error.add_theme_color_override("font_color", UiTheme.ACCENT)
	_modal_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_modal_error)
	return _modal_error


func _time_name(id: String) -> String:
	match id:
		"dawn":
			return tr("Dawn")
		"morning":
			return tr("Morning")
		"noon":
			return tr("Noon")
		"afternoon":
			return tr("Afternoon")
		"golden":
			return tr("Golden hour")
		"dusk":
			return tr("Dusk")
		"night":
			return tr("Night")
	return id


func _style_name(id: String) -> String:
	match id:
		"grass":
			return tr("Grass")
		"sand":
			return tr("Sand")
		"snow":
			return tr("Snow")
		"rock":
			return tr("Rock")
	return id


# Castle settings: name, grievance, sky, scenery, ground and width.
func _open_settings() -> void:
	var box: VBoxContainer = _open_modal(tr("Castle"))
	var name_edit := LineEdit.new()
	name_edit.max_length = 60
	name_edit.text = str(model.doc.get("name", ""))
	name_edit.text_changed.connect(func(t: String) -> void: _set_meta("name", t.strip_edges()))
	_field(box, tr("Name"), name_edit)
	var grievance := LineEdit.new()
	grievance.max_length = 200
	grievance.placeholder_text = tr("Why must this castle fall?")
	grievance.text = str(model.doc.get("grievance", ""))
	grievance.text_changed.connect(func(t: String) -> void: _set_meta("grievance", t.strip_edges()))
	_field(box, tr("Grievance"), grievance)

	var times := OptionButton.new()
	for id: String in TIMES:
		times.add_item(_time_name(id))
	times.selected = maxi(0, TIMES.find(str(model.doc.get("time_of_day", "noon"))))
	times.item_selected.connect(func(i: int) -> void: model.set_meta_field("time_of_day", TIMES[i]))
	_field(box, tr("Sky"), times)

	var realms := OptionButton.new()
	var realm_ids: Array[String] = []
	for r: Dictionary in Data.realms:
		realm_ids.append(str(r.get("id", "")))
		realms.add_item(tr(str(r.get("name", ""))))
	realms.selected = maxi(0, realm_ids.find(str(model.doc.get("realm", ""))))
	realms.item_selected.connect(func(i: int) -> void: model.set_meta_field("realm", realm_ids[i]))
	_field(box, tr("Scenery"), realms)

	var ground := OptionButton.new()
	for id: String in STYLES:
		ground.add_item(_style_name(id))
	var terrain: Array = model.doc.get("terrain", [])
	var style: String = (
		str((terrain[0] as Dictionary).get("style", "grass")) if not terrain.is_empty() else "grass"
	)
	ground.selected = maxi(0, STYLES.find(style))
	ground.item_selected.connect(func(i: int) -> void: model.set_terrain_style(STYLES[i]))
	_field(box, tr("Ground"), ground)

	var width_row := HBoxContainer.new()
	width_row.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = EditorModel.MIN_WORLD_RIGHT
	slider.max_value = EditorModel.MAX_WORLD_RIGHT
	slider.step = 1.0
	slider.value = view.world_right()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := Label.new()
	value.custom_minimum_size.x = 70
	value.text = tr("%d m") % int(slider.value)
	slider.value_changed.connect(func(v: float) -> void: value.text = tr("%d m") % int(v))
	slider.drag_ended.connect(func(_changed: bool) -> void: model.set_world_right(slider.value))
	width_row.add_child(slider)
	width_row.add_child(value)
	_field(box, tr("Width"), width_row)

	_modal_buttons(
		box,
		[
			_button(tr("New castle"), _new_castle),
			_button(tr("Delete castle"), _confirm_delete),
			_button(tr("Done"), _close_settings.bind(slider)),
		]
	)


## Name and grievance edits: one undo step per editing session, not per key.
func _set_meta(key: String, value: String) -> void:
	if value.is_empty() and key == "name":
		return
	model.doc[key] = value
	_title_btn.text = str(model.doc.get("name", ""))
	_save_t = SAVE_DELAY


func _close_settings(slider: HSlider) -> void:
	model.set_world_right(slider.value)
	_close_modal()
	_update_ui()


func _new_castle() -> void:
	_save_now()
	_close_modal()
	sel = {}
	model.load_doc(EditorModel.new_level())
	_frame_all()
	_toast_msg(tr("A fresh hill. Pick a block on the left to start."))


func _confirm_delete() -> void:
	var box: VBoxContainer = _open_modal(tr("Delete castle?"), 480.0)
	var l := Label.new()
	l.text = tr("“%s” will be gone for good.") % str(model.doc.get("name", ""))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	var del := _button(tr("Delete"), _delete_castle)
	del.add_theme_color_override("font_color", UiTheme.ACCENT)
	_modal_buttons(box, [_button(tr("Keep it"), _close_modal), del])


func _delete_castle() -> void:
	CustomLevels.delete_level(str(model.doc.get("id", "")))
	_close_modal()
	sel = {}
	var saved: Array[Dictionary] = CustomLevels.list()
	var doc: Dictionary = (
		CustomLevels.load_level(str(saved[0]["id"])) if not saved.is_empty() else {}
	)
	model.load_doc(doc if not doc.is_empty() else EditorModel.new_level())
	_frame_all()
	_toast_msg(tr("Castle deleted."))


# My castles, and opening shared ones (code or file).
func _open_castles() -> void:
	_save_now()
	var box: VBoxContainer = _open_modal(tr("Castles"), 680.0)
	var paste_row := HBoxContainer.new()
	paste_row.add_theme_constant_override("separation", 8)
	box.add_child(paste_row)
	var code := LineEdit.new()
	code.placeholder_text = tr("Paste a castle code (SF1.…)")
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.text_submitted.connect(func(t: String) -> void: _open_code(t))
	paste_row.add_child(code)
	paste_row.add_child(
		_button(tr("Paste"), func() -> void: code.text = DisplayServer.clipboard_get())
	)
	paste_row.add_child(_button(tr("Open code"), func() -> void: _open_code(code.text)))
	_error_line(box)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 300 * minf(Settings.text_scale, 1.25)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var saved: Array[Dictionary] = CustomLevels.list()
	if saved.is_empty():
		var none := Label.new()
		none.text = tr("No castles yet. Everything you build is kept here.")
		none.theme_type_variation = "SmallLabel"
		list.add_child(none)
	for info: Dictionary in saved:
		list.add_child(_castle_row(info))

	_modal_buttons(
		box,
		[
			_button(tr("New castle"), _new_castle),
			_button(tr("Open file…"), _open_file_dialog),
			_button(tr("Done"), _close_modal),
		]
	)


func _castle_row(info: Dictionary) -> Control:
	var current: bool = str(info["id"]) == str(model.doc.get("id", ""))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", UiTheme.panel_style(UiTheme.PAPER if current else UiTheme.PAPER_DEEP, 2, 12)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var n := Label.new()
	n.text = str(info["name"]) + ("  ·  " + tr("open now") if current else "")
	n.clip_text = true
	text.add_child(n)
	var meta := Label.new()
	meta.theme_type_variation = "SmallLabel"
	var par: Dictionary = info.get("par", {})
	meta.text = tr("Blocks: %d · People: %d") % [int(info["blocks"]), int(info["enemies"])]
	if not par.is_empty():
		meta.text += "  ·  " + tr("Gold in %d") % int(par.get("gold", 0))
	text.add_child(meta)
	if not current:
		row.add_child(_button(tr("Edit"), _edit_castle.bind(str(info["id"]))))
	row.add_child(_button(tr("Play"), _play_castle.bind(str(info["id"]))))
	return panel


func _edit_castle(id: String) -> void:
	var lv: Dictionary = CustomLevels.load_level(id)
	if lv.is_empty():
		return
	_save_now()
	_close_modal()
	sel = {}
	model.load_doc(lv)
	_frame_all()


func _play_castle(id: String) -> void:
	var lv: Dictionary = CustomLevels.load_level(id)
	var parsed: LevelData = Data.parse_level(lv)
	if not parsed.is_valid():
		if _modal_error != null:
			_modal_error.text = tr("That castle can't be played yet: %s") % parsed.errors[0]
		return
	_save_now()
	if id == str(model.doc.get("id", "")):
		Game.play_custom(model.doc, true)
	else:
		_edit_castle(id)
		Game.play_custom(model.doc, true)


func _open_code(text: String) -> void:
	var r: Dictionary = ShareCode.decode(text)
	if not r["ok"]:
		if _modal_error != null:
			_modal_error.text = tr(str(r["error"]))
		return
	_import(r["level"])


func _import(level: Dictionary) -> void:
	var lv: Dictionary = CustomLevels.import_level(level)
	_save_now()
	_close_modal()
	sel = {}
	model.load_doc(lv)
	_frame_all()
	_toast_msg(tr("Added “%s” to your castles.") % str(lv.get("name", "")))


func _open_file_dialog() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "", _on_file_opened)


func _on_file_opened(path: String) -> void:
	var r: Dictionary = CustomLevels.read_file(path)
	if not r["ok"]:
		if _modal_error != null:
			_modal_error.text = tr(str(r["error"]))
		return
	_import(r["level"])


func _file_dialog(mode: FileDialog.FileMode, file_name: String, cb: Callable) -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.json ; " + tr("Siegefall castle")])
	_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not file_name.is_empty():
		_dialog.current_file = file_name
	_dialog.file_selected.connect(cb)
	add_child(_dialog)
	_dialog.popup_centered_ratio(0.7)


# Share: the code, copy to clipboard, or save a .json file.
func _open_share() -> void:
	var blocking: PackedStringArray = model.problems()["blocking"]
	if not blocking.is_empty():
		_toast_msg(blocking[0])
		return
	_save_now()
	var box: VBoxContainer = _open_modal(tr("Share"), 640.0)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = tr(
		"Send this code to a friend. They open it with Castles, then Open code. No internet needed."
	)
	box.add_child(info)
	var par: Dictionary = model.doc.get("par", {})
	var note := Label.new()
	note.theme_type_variation = "SmallLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var g: int = int(par.get("gold", 0))
	note.text = (
		(
			tr_n(
				"Your record goes with it: gold in %d shot.",
				"Your record goes with it: gold in %d shots.",
				g
			)
			% g
		)
		if not par.is_empty()
		else tr("Tip: beat your castle in Test first, so friends get medals to aim for.")
	)
	box.add_child(note)
	var code_box := TextEdit.new()
	code_box.text = ShareCode.encode(model.doc)
	code_box.editable = false
	code_box.add_theme_color_override("font_readonly_color", UiTheme.INK)
	var code_style: StyleBoxFlat = UiTheme.panel_style(Color.WHITE, 2, 10)
	code_style.set_content_margin_all(10)
	code_box.add_theme_stylebox_override("read_only", code_style)
	code_box.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	code_box.add_theme_font_size_override("font_size", roundi(18 * Settings.text_scale))
	code_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_box.custom_minimum_size.y = 130 * minf(Settings.text_scale, 1.25)
	box.add_child(code_box)
	var len_label := Label.new()
	len_label.theme_type_variation = "SmallLabel"
	len_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	len_label.text = tr("%d characters") % code_box.text.length()
	box.add_child(len_label)
	_modal_buttons(
		box,
		[
			_button(tr("Copy code"), _copy_code.bind(code_box.text)),
			_button(tr("Save file…"), _save_file_dialog),
			_button(tr("Done"), _close_modal),
		]
	)


func _copy_code(code: String) -> void:
	DisplayServer.clipboard_set(code)
	_toast_msg(tr("Code copied."))


func _save_file_dialog() -> void:
	var file_name: String = ShareCode.slug(str(model.doc.get("name", "castle"))) + ".json"
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, file_name, _on_file_saved)


func _on_file_saved(path: String) -> void:
	var p: String = path if path.ends_with(".json") else path + ".json"
	if CustomLevels.write_file(p, model.doc):
		_toast_msg(tr("Saved %s") % p.get_file())
	else:
		_toast_msg(tr("Couldn't save there. Try another folder?"))
