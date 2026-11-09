# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Hud
extends CanvasLayer
## In-level HUD, built in code: shots and par strip, ammo chip, swing gauge,
## restart/pause buttons, hint, and the win and pause cards.

signal restart_pressed
signal pause_pressed
signal resume_pressed
signal menu_pressed
signal next_pressed
signal ammo_cycle(direction: int)

var _root: Control
var _margin: MarginContainer
var _shots: Label
var _par_chips: Array[Label] = []
var _par: Dictionary = {}
var _ammo_btn: Button
var _hint: Label
var _gauge: SwingGauge
var _win: Control = null
var _pause: Control = null
var _title: Label
var _intro: Control = null


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build(Settings.text_scale)
	add_child(_root)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_margin)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_margin.add_child(top)

	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 2)
	top.add_child(left)
	_title = Label.new()
	_title.theme_type_variation = "HudLabel"
	_title.add_theme_font_size_override("font_size", roundi(20 * Settings.text_scale))
	left.add_child(_title)
	_shots = Label.new()
	_shots.theme_type_variation = "HudLabel"
	left.add_child(_shots)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(chips)
	for m: Scoring.Medal in [Scoring.Medal.GOLD, Scoring.Medal.SILVER, Scoring.Medal.BRONZE]:
		var chip := Label.new()
		chip.theme_type_variation = "HudLabel"
		chip.add_theme_font_size_override("font_size", roundi(18 * Settings.text_scale))
		chip.add_theme_constant_override("outline_size", 0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.medal_color(m)
		sb.border_color = UiTheme.INK
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		chip.add_theme_stylebox_override("normal", sb)
		chips.add_child(chip)
		_par_chips.append(chip)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(buttons)
	buttons.add_child(_icon_button("res://art/ui/restart.svg", tr("Restart"), restart_pressed.emit))
	buttons.add_child(_icon_button("res://art/ui/pause.svg", tr("Pause"), pause_pressed.emit))

	_ammo_btn = Button.new()
	_ammo_btn.theme_type_variation = "HudButton"
	_ammo_btn.focus_mode = Control.FOCUS_NONE
	_ammo_btn.pressed.connect(func() -> void: ammo_cycle.emit(1))
	_ammo_btn.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24
	)
	_ammo_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_ammo_btn)

	_gauge = SwingGauge.new()
	_gauge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge.offset_left = -190
	_gauge.offset_right = 190
	_gauge.offset_top = -64
	_gauge.offset_bottom = -30
	_gauge.visible = Settings.show_swing_gauge
	_root.add_child(_gauge)

	_hint = Label.new()
	_hint.theme_type_variation = "HudLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.offset_top = -120
	_hint.offset_bottom = -76
	_root.add_child(_hint)
	_wire_clicks(_root)


func _icon_button(icon_path: String, tooltip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "HudButton"
	b.icon = load(icon_path) as Texture2D
	b.expand_icon = true
	b.custom_minimum_size = Vector2(60, 60) * Settings.text_scale
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _apply_safe_area() -> void:
	var m: float = 20.0
	var left: float = m
	var top: float = m
	var right: float = m
	var bottom: float = m
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		var vp: Vector2 = _root.get_viewport_rect().size
		if screen.x > 0 and screen.y > 0:
			var sx: float = vp.x / screen.x
			var sy: float = vp.y / screen.y
			left += safe.position.x * sx
			top += safe.position.y * sy
			right += (screen.x - safe.end.x) * sx
			bottom += (screen.y - safe.end.y) * sy
	_margin.add_theme_constant_override("margin_left", roundi(left))
	_margin.add_theme_constant_override("margin_top", roundi(top))
	_margin.add_theme_constant_override("margin_right", roundi(right))
	_margin.add_theme_constant_override("margin_bottom", roundi(bottom))


func setup(level_name: String, par: Dictionary) -> void:
	_title.text = level_name
	_par = par
	_par_chips[0].text = tr("Gold ≤ %d") % int(par.get("gold", 1))
	_par_chips[1].text = tr("Silver ≤ %d") % int(par.get("silver", 2))
	_par_chips[2].text = tr("Bronze ≤ %d") % int(par.get("bronze", 4))
	set_shots(0)


## Level intro: name and King Grumbold's grievance on a parchment banner.
func show_intro(title: String, grievance: String) -> void:
	if grievance.is_empty():
		return
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style(UiTheme.PAPER, 3, 16)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(620, 0) * minf(Settings.text_scale, 1.2)
	panel.offset_left = -310 * minf(Settings.text_scale, 1.2)
	panel.offset_top = 150
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var h := Label.new()
	h.theme_type_variation = "HeadingLabel"
	h.add_theme_font_size_override("font_size", roundi(30 * Settings.text_scale))
	h.text = title
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var g := Label.new()
	g.text = "“%s”" % grievance
	g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	v.add_child(g)
	var sig := Label.new()
	sig.theme_type_variation = "SmallLabel"
	sig.text = tr("— King Grumbold the Petty")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(sig)
	_root.add_child(panel)
	_intro = panel
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(4.0)
	tw.tween_callback(hide_intro)


func hide_intro() -> void:
	if _intro == null or not is_instance_valid(_intro):
		return
	var p: Control = _intro
	_intro = null
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


func set_shots(n: int) -> void:
	_shots.text = tr("Shots: %d") % n
	var keys: Array[String] = ["gold", "silver", "bronze"]
	for i: int in 3:
		var reachable: bool = n < int(_par.get(keys[i], 1)) or (n == 0)
		_par_chips[i].modulate.a = 1.0 if reachable or n <= int(_par.get(keys[i], 1)) else 0.35


func set_ammo(ammo_def: Dictionary, count: int) -> void:
	_ammo_btn.text = tr(str(ammo_def.get("name", "?")))
	_ammo_btn.disabled = count <= 1
	_ammo_btn.tooltip_text = tr(str(ammo_def.get("description", "")))


func set_hint(text: String) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0 if not text.is_empty() else 0.0


func fade_hint() -> void:
	var tw := create_tween()
	tw.tween_property(_hint, "modulate:a", 0.0, 0.6)


func update_gauge(p: float, last_p: float, active: bool) -> void:
	_gauge.phase = p
	_gauge.last_phase = last_p
	_gauge.active = active
	_gauge.queue_redraw()


# ------------------------------------------------------------- win card ---
func show_win(
	medal: Scoring.Medal,
	shots: int,
	par: Dictionary,
	score: int,
	best: bool,
	unlocked: PackedStringArray,
	has_next: bool
) -> void:
	_gauge.visible = false
	_win = _card()
	var box: VBoxContainer = _win.get_meta("box")
	var head := Label.new()
	head.theme_type_variation = "HeadingLabel"
	head.text = tr("Castle flattened!")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var stamp := MedalStamp.new()
	stamp.medal = medal
	stamp.stamp = 0.0
	stamp.custom_minimum_size = Vector2(170, 190) * Settings.text_scale
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(stamp)
	var medal_names: Array[String] = [tr("No medal"), tr("Bronze"), tr("Silver"), tr("Gold")]
	var line := Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var shot_text: String = tr_n("%d shot", "%d shots", shots) % shots
	var par_text: String = tr("%s (gold ≤ %d)") % [shot_text, int(par.get("gold", 1))]
	line.text = "%s · %s" % [medal_names[medal], par_text]
	box.add_child(line)
	var pts := Label.new()
	pts.theme_type_variation = "SmallLabel"
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.text = tr("Score %d") % score + ("  ·  " + tr("New best!") if best else "")
	box.add_child(pts)
	for id: String in unlocked:
		var u := Label.new()
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u.add_theme_color_override("font_color", UiTheme.ACCENT)
		u.text = tr("New ammo unlocked: %s") % tr(str(Data.ammo_def(id).get("name", id)))
		box.add_child(u)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var menu := Button.new()
	menu.text = tr("Menu")
	menu.pressed.connect(menu_pressed.emit)
	row.add_child(menu)
	var retry := Button.new()
	retry.text = tr("Retry")
	retry.pressed.connect(restart_pressed.emit)
	row.add_child(retry)
	var focus_target: Button = retry
	if has_next:
		var nxt := Button.new()
		nxt.theme_type_variation = "BigButton"
		nxt.text = tr("Next")
		nxt.pressed.connect(next_pressed.emit)
		row.add_child(nxt)
		focus_target = nxt
	focus_target.grab_focus.call_deferred()
	_wire_clicks(_win)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(stamp, "stamp", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)


func show_pause() -> void:
	if _pause != null:
		return
	_pause = _card()
	var box: VBoxContainer = _pause.get_meta("box")
	var head := Label.new()
	head.theme_type_variation = "HeadingLabel"
	head.text = tr("Paused")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for pair: Array in [
		[tr("Resume"), resume_pressed], [tr("Restart"), restart_pressed], [tr("Menu"), menu_pressed]
	]:
		var b := Button.new()
		b.text = str(pair[0])
		var sig: Signal = pair[1]
		b.pressed.connect(sig.emit)
		box.add_child(b)
	(box.get_child(1) as Button).grab_focus.call_deferred()
	_wire_clicks(_pause)


func hide_pause() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null


## Every button in the HUD clicks.
func _wire_clicks(node: Node) -> void:
	for c: Node in node.get_children():
		if c is BaseButton and not (c as BaseButton).pressed.is_connected(_click):
			(c as BaseButton).pressed.connect(_click)
		_wire_clicks(c)


func _click() -> void:
	Sfx.play_ui("ui_click", -8.0)


func _card() -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.08, 0.05, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0) * Settings.text_scale
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	shade.set_meta("box", box)
	var tw := create_tween()
	tw.tween_property(shade, "color:a", 0.35, 0.2)
	panel.pivot_offset = Vector2(230, 200)
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	(
		tw
		. parallel()
		. tween_property(panel, "scale", Vector2.ONE, 0.25)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.18)
	return shade


## Thin swing meter: track, live needle, and a notch at the last release.
class SwingGauge:
	extends Control
	const P0: float = 0.3
	const P1: float = 1.0
	var phase: float = 0.0
	var last_phase: float = -1.0
	var active: bool = false

	func _x(p: float) -> float:
		return clampf((p - P0) / (P1 - P0), 0.0, 1.0) * size.x

	func _draw() -> void:
		var h: float = size.y
		var track := Rect2(Vector2(0, h * 0.35), Vector2(size.x, h * 0.3))
		draw_rect(track, Color(UiTheme.PAPER, 0.85))
		draw_rect(track, UiTheme.INK, false, 2.0)
		if last_phase >= 0.0:
			var lx: float = _x(last_phase)
			draw_line(Vector2(lx, 0), Vector2(lx, h), UiTheme.INK, 3.0)
		if active:
			var x: float = _x(phase)
			var tri := PackedVector2Array(
				[Vector2(x - 9, 0), Vector2(x + 9, 0), Vector2(x, h * 0.5)]
			)
			draw_colored_polygon(tri, UiTheme.ACCENT)
			draw_line(Vector2(x, h * 0.3), Vector2(x, h), UiTheme.ACCENT, 4.0)
