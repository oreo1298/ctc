# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends MenuBase
## Settings: audio, accessibility, graphics and remappable controls.
## Every change is saved immediately (Settings.save_settings).

var _tabs: TabContainer
var _waiting_action: String = ""
var _waiting_button: Button = null


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	build_frame("", "morning")
	var box := card(tr("Settings"), 720.0)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 420) * minf(Settings.text_scale, 1.3)
	box.add_child(_tabs)
	_tabs.add_child(_page(tr("Play"), _play_page))
	_tabs.add_child(_page(tr("Access"), _access_page))
	_tabs.add_child(_page(tr("Sound"), _sound_page))
	_tabs.add_child(_page(tr("Video"), _video_page))
	_tabs.add_child(_page(tr("Controls"), _controls_page))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var back := button(tr("Back"), go_back, "BigButton")
	row.add_child(back)
	back.grab_focus.call_deferred()


func _page(title: String, fill: Callable) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	fill.call(v)
	return scroll


func _row(parent: Control, label: String, control: Control, hint: String = "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.tooltip_text = hint
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	h.add_child(control)
	parent.add_child(h)


func _toggle(
	parent: Control, label: String, key: String, hint: String = "", rebuild: bool = false
) -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Settings.get(key))
	cb.toggled.connect(
		func(on: bool) -> void:
			Settings.set(key, on)
			Settings.save_settings()
			if rebuild:
				_rebuild.call_deferred()
	)
	_row(parent, label, cb, hint)


func _slider(
	parent: Control,
	label: String,
	key: String,
	lo: float,
	hi: float,
	step: float,
	rebuild: bool = false
) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get(key))
	s.custom_minimum_size = Vector2(220, 32)
	var commit := func(v: float) -> void:
		Settings.set(key, v)
		Settings.save_settings()
	if rebuild:
		s.drag_ended.connect(
			func(_changed: bool) -> void:
				commit.call(s.value)
				_rebuild.call_deferred()
		)
	else:
		s.value_changed.connect(commit)
	_row(parent, label, s)


func _choice(parent: Control, label: String, key: String, options: Array, names: Array) -> void:
	var o := OptionButton.new()
	for i: int in options.size():
		o.add_item(str(names[i]), i)
		if options[i] == Settings.get(key):
			o.select(i)
	o.item_selected.connect(
		func(i: int) -> void:
			Settings.set(key, options[i])
			Settings.save_settings()
	)
	_row(parent, label, o)


func _play_page(v: VBoxContainer) -> void:
	_choice(
		v, tr("Swing speed"), "swing_speed", [1.0, 0.75, 0.5], [tr("Normal"), tr("75%"), tr("50%")]
	)
	_toggle(
		v,
		tr("Swing gauge"),
		"show_swing_gauge",
		tr("A meter showing the arm's position and your last release.")
	)
	_toggle(v, tr("Ghost of last shot"), "show_ghost_trail")
	_toggle(v, tr("Vibration (phones)"), "haptics")


func _access_page(v: VBoxContainer) -> void:
	_toggle(
		v,
		tr("One-button mode"),
		"one_button",
		tr("One button does everything: tap to shoot, hold to change ammo.")
	)
	_toggle(v, tr("Screen shake"), "screen_shake")
	_toggle(v, tr("Slow motion on big hits"), "slow_motion")
	_toggle(v, tr("Reduce flashing"), "reduce_flashing")
	_toggle(
		v,
		tr("Material patterns"),
		"material_glyphs",
		tr("Stamps a pattern on each material so they can be told apart without colour.")
	)
	_slider(v, tr("Text size"), "text_scale", 0.8, 1.6, 0.1, true)


func _sound_page(v: VBoxContainer) -> void:
	_slider(v, tr("Master volume"), "master_volume", 0.0, 1.0, 0.05)
	_slider(v, tr("Effects volume"), "sfx_volume", 0.0, 1.0, 0.05)
	_slider(v, tr("Music volume"), "music_volume", 0.0, 1.0, 0.05)


func _video_page(v: VBoxContainer) -> void:
	_choice(
		v,
		tr("Quality"),
		"quality",
		["auto", "low", "high"],
		[tr("Automatic"), tr("Low"), tr("High")]
	)
	if not OS.has_feature("mobile"):
		var fs := CheckButton.new()
		fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fs.toggled.connect(
			func(on: bool) -> void:
				DisplayServer.window_set_mode(
					(
						DisplayServer.WINDOW_MODE_FULLSCREEN
						if on
						else DisplayServer.WINDOW_MODE_WINDOWED
					)
				)
		)
		_row(v, tr("Fullscreen"), fs)
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	if locales.size() > 1:
		var names: Array = []
		for l: String in locales:
			names.append(TranslationServer.get_locale_name(l))
		_choice(v, tr("Language"), "locale", Array(locales), names)
	var info := Label.new()
	info.theme_type_variation = "SmallLabel"
	info.text = tr("Renderer: %s") % RenderingServer.get_current_rendering_method()
	v.add_child(info)


func _controls_page(v: VBoxContainer) -> void:
	var names: Dictionary = {
		"fire": tr("Swing / release / ability"),
		"restart": tr("Restart level"),
		"pause": tr("Pause"),
		"ammo_next": tr("Next ammo"),
		"ammo_prev": tr("Previous ammo"),
	}
	for action: String in Controls.REMAPPABLE:
		var b := Button.new()
		b.text = Controls.describe(action)
		b.tooltip_text = tr(
			"Press, then press the new key or gamepad button (replaces the binding of that device type)."
		)
		b.pressed.connect(_start_rebind.bind(action, b))
		_row(v, str(names.get(action, action)), b)
	v.add_child(button(tr("Reset controls"), _reset_controls))


func _reset_controls() -> void:
	Controls.reset_all()
	_rebuild.call_deferred()


func _start_rebind(action: String, b: Button) -> void:
	_waiting_action = action
	_waiting_button = b
	b.text = tr("Press a key…")


func _input(event: InputEvent) -> void:
	if _waiting_action.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_button.text = Controls.describe(_waiting_action)
		else:
			Controls.rebind(_waiting_action, event)
			_waiting_button.text = Controls.describe(_waiting_action)
		_waiting_action = ""
		get_viewport().set_input_as_handled()


func go_back() -> void:
	if not _waiting_action.is_empty():
		return
	Game.goto_menu()
