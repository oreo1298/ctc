# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name EditorPalette
extends PanelContainer
## The editor's left-hand panel: tools (select, ground), block shapes,
## materials and people, all from game/data/editor.json. Exactly one mode
## button is down at a time; the material is a separate choice.

signal tool_chosen(tool: String)
signal preset_chosen(preset: Dictionary)
signal person_chosen(type: String)
signal material_chosen(id: String)

const MATERIAL_ORDER: Array[String] = ["wood", "stone", "glass", "ice", "iron", "thatch", "cloth"]

var current_material: String = "wood"
var _modes := ButtonGroup.new()
var _materials := ButtonGroup.new()
var _tool_buttons: Dictionary = {}
var _preset_buttons: Dictionary = {}
var _person_buttons: Dictionary = {}
var _material_buttons: Dictionary = {}
var _icons: Array[_ShapeIcon] = []


func _ready() -> void:
	var s: float = minf(Settings.text_scale, 1.25)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	col.add_child(tools)
	for pair: Array in [
		["select", tr("Select"), tr("Pick, drag and edit pieces (V)")],
		["terrain", tr("Ground"), tr("Drag the ground's points; click the ground to add one (G)")],
	]:
		var b := Button.new()
		b.text = str(pair[1])
		b.tooltip_text = str(pair[2])
		b.toggle_mode = true
		b.button_group = _modes
		b.theme_type_variation = "ToolButton"
		b.custom_minimum_size.y = 44 * s
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tool.bind(str(pair[0])))
		tools.add_child(b)
		_tool_buttons[pair[0]] = b

	col.add_child(_heading(tr("Blocks")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for p: Variant in Data.editor.get("presets", []):
		var preset: Dictionary = p
		var icon := _ShapeIcon.new()
		icon.poly = ShapeGeometry.polygon_for(EditorModel.spec_of(preset))
		_icons.append(icon)
		var b := _tile(tr(str(preset.get("name", ""))), icon, Vector2(58, 58) * s)
		b.pressed.connect(_on_preset.bind(preset))
		grid.add_child(b)
		_preset_buttons[preset.get("id", "")] = b

	col.add_child(_heading(tr("Material")))
	var mats := GridContainer.new()
	mats.columns = 4
	mats.add_theme_constant_override("h_separation", 6)
	mats.add_theme_constant_override("v_separation", 6)
	col.add_child(mats)
	for id: String in MATERIAL_ORDER:
		var def: Dictionary = Data.material(id)
		if def.is_empty():
			continue
		var sw := TextureRect.new()
		sw.texture = _swatch(def)
		sw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var b := _tile(tr(str(def.get("name", id))), sw, Vector2(58, 52) * s, _materials)
		b.pressed.connect(_on_material.bind(id))
		mats.add_child(b)
		_material_buttons[id] = b

	col.add_child(_heading(tr("People")))
	var people := GridContainer.new()
	people.columns = 4
	people.add_theme_constant_override("h_separation", 4)
	col.add_child(people)
	for t: Variant in Data.editor.get("people", []):
		var type: String = str(t)
		var def: Dictionary = Data.enemy(type)
		var tex := TextureRect.new()
		tex.texture = load(str(def.get("art", ""))) as Texture2D
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var b := _tile(tr(str(def.get("name", type))), tex, Vector2(58, 64) * s)
		b.pressed.connect(_on_person.bind(type))
		people.add_child(b)
		_person_buttons[type] = b

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var tips := Label.new()
	tips.theme_type_variation = "SmallLabel"
	tips.add_theme_font_size_override("font_size", roundi(15 * s))
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# One tr() per sentence: the catalogue extractor needs whole literals.
	var lines: PackedStringArray = []
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		lines = [
			tr("Tap a piece, then tap to place it."),
			tr("Drag empty space to move around; pinch to zoom."),
			tr("Tap Select to pick up and drag pieces."),
		]
	else:
		lines = [
			tr("Right-click or Esc: back to Select."),
			tr("Wheel: zoom. Right-drag: pan."),
			tr("Q/E: turn. Del: delete. Ctrl+Z: undo."),
			tr("Home: frame the castle."),
		]
	tips.text = " ".join(lines)
	col.add_child(tips)

	show_material(current_material)
	show_mode("select", "")


## Press the button for a mode without emitting anything.
func show_mode(kind: String, value: String) -> void:
	var b: Button = null
	match kind:
		"select", "terrain":
			b = _tool_buttons.get(kind)
		"preset":
			b = _preset_buttons.get(value)
		"person":
			b = _person_buttons.get(value)
	# set_pressed_no_signal does not release the rest of a ButtonGroup.
	for other: BaseButton in _modes.get_buttons():
		other.set_pressed_no_signal(other == b)


func show_material(id: String) -> void:
	current_material = id
	var b: Button = _material_buttons.get(id)
	for other: BaseButton in _materials.get_buttons():
		other.set_pressed_no_signal(other == b)
	var col: Color = Units.color(Data.material(id).get("colors", {}).get("base"), Color.TAN)
	for icon: _ShapeIcon in _icons:
		icon.fill = col
		icon.queue_redraw()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "SmallLabel"
	return l


func _tile(label: String, art: Control, min_size: Vector2, group: ButtonGroup = null) -> Button:
	var s: float = minf(Settings.text_scale, 1.25)
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group if group != null else _modes
	b.theme_type_variation = "ToolButton"
	b.tooltip_text = label
	b.custom_minimum_size = min_size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 7 * s
	art.offset_right = -7 * s
	art.offset_top = 6 * s
	art.offset_bottom = -20 * s
	b.add_child(art)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = "SmallLabel"
	l.add_theme_font_size_override("font_size", roundi(13 * s))
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -21 * s
	l.offset_bottom = -3 * s
	b.add_child(l)
	return b


static func _swatch(def: Dictionary) -> Texture2D:
	var colors: Dictionary = def.get("colors", {})
	var base: Color = Units.color(colors.get("base"), Color.TAN)
	var dark: Color = Units.color(colors.get("dark"), base.darkened(0.3))
	var img := Image.create(40, 28, false, Image.FORMAT_RGBA8)
	img.fill(UiTheme.INK)
	img.fill_rect(Rect2i(3, 3, 34, 22), base)
	img.fill_rect(Rect2i(3, 18, 34, 7), dark)
	return ImageTexture.create_from_image(img)


func _on_tool(tool: String) -> void:
	tool_chosen.emit(tool)


func _on_preset(preset: Dictionary) -> void:
	preset_chosen.emit(preset)


func _on_person(type: String) -> void:
	person_chosen.emit(type)


func _on_material(id: String) -> void:
	show_material(id)
	material_chosen.emit(id)


## A block shape drawn to fit its tile, in the chosen material's colour.
class _ShapeIcon:
	extends Control

	var poly := PackedVector2Array()
	var fill := Color.TAN

	func _draw() -> void:
		if poly.size() < 3:
			return
		var r := Rect2(poly[0], Vector2.ZERO)
		for p: Vector2 in poly:
			r = r.expand(p)
		var k: float = minf(size.x / maxf(r.size.x, 1.0), size.y / maxf(r.size.y, 1.0))
		k = minf(k, size.y / 80.0)
		var off: Vector2 = size * 0.5 - r.get_center() * k
		var pts := PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(p * k + off)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, UiTheme.INK, 2.0, true)
