# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name MenuBase
extends Node2D
## Shared frame for menu screens: a living storybook backdrop, a themed
## full-screen UI root, "back" on Esc / gamepad B, and one-button scanning
## (Settings.one_button: focus steps through the buttons by itself and any
## press activates the focused one).

const SCAN_INTERVAL: float = 1.3

var ui: Control
var _cam: Camera2D
var _t: float = 0.0
var _scan_t: float = 0.0


## Build the backdrop for `realm_id` and return the content root (a
## full-rect Control with the game theme).
func build_frame(realm_id: String = "", time: String = "golden") -> Control:
	var realm: Dictionary = Data.realm(realm_id) if not realm_id.is_empty() else {}
	if realm.is_empty() and not Data.realms.is_empty():
		realm = Data.realms[0]
	var backdrop := Backdrop.new()
	add_child(backdrop)
	backdrop.build(realm.get("palette", {}), Data.grade(time), realm.get("backdrop", {}), 60.0, 7)
	_cam = Camera2D.new()
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_cam.zoom = Vector2(0.5, 0.5)
	add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.build(Settings.text_scale)
	layer.add_child(ui)
	UiTheme.fit_safe_area(ui)
	Music.play("menu")
	return ui


## Panel centred on screen with a heading; returns its VBox.
func card(title: String, min_width: float = 560.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0) * minf(Settings.text_scale, 1.25)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = "HeadingLabel"
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	return box


func button(text: String, cb: Callable, variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: Sfx.play_ui("ui_click", -8.0))
	b.pressed.connect(cb)
	return b


## Override to handle "back" (Esc, gamepad B/Back).
func go_back() -> void:
	Game.goto_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
	elif Settings.one_button and event.is_action_pressed("fire"):
		var f: Control = get_viewport().gui_get_focus_owner()
		if f is BaseButton:
			get_viewport().set_input_as_handled()
			(f as BaseButton).pressed.emit()


func _physics_process(delta: float) -> void:
	_t += delta
	if _cam != null:
		_cam.position = Vector2(_t * 60.0, -300.0)
	if Settings.one_button and ui != null:
		_scan_t += delta
		if _scan_t >= SCAN_INTERVAL:
			_scan_t = 0.0
			_scan_next()


func _scan_next() -> void:
	var buttons: Array[BaseButton] = []
	_collect(ui, buttons)
	if buttons.is_empty():
		return
	var cur: Control = get_viewport().gui_get_focus_owner()
	var i: int = buttons.find(cur as BaseButton) if cur is BaseButton else -1
	buttons[(i + 1) % buttons.size()].grab_focus()


func _collect(n: Node, out: Array[BaseButton]) -> void:
	for c: Node in n.get_children():
		if c is BaseButton and (c as BaseButton).visible and not (c as BaseButton).disabled:
			out.append(c)
		_collect(c, out)
