# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends MenuBase
## Realm tabs with a grid of level cards (number, name, medal, best shots).
## Locked levels show a padlock; a realm unlocks when the previous realm's
## last level is completed.

const LOCK: Texture2D = preload("res://art/ui/lock.svg")

var _realm_index: int = 0
var _grid: GridContainer
var _title: Label
var _tagline: Label
var _tabs: HBoxContainer


func _ready() -> void:
	var last: String = (
		Game.save.last_level
		if not Game.save.last_level.is_empty()
		else Game.next_unfinished_level()
	)
	var realm_id: String = str(Data.level_realm.get(last, ""))
	for i: int in Data.realms.size():
		if str(Data.realms[i].get("id", "")) == realm_id:
			_realm_index = i
	_rebuild()


func _rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	var realm: Dictionary = Data.realms[_realm_index]
	var times: Array[String] = ["golden", "afternoon", "night"]
	build_frame(str(realm.get("id", "")), times[_realm_index % times.size()])
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	ui.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	top.add_child(button(tr("Back"), go_back))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_tabs)
	for i: int in Data.realms.size():
		var r: Dictionary = Data.realms[i]
		var open: bool = Game.is_realm_unlocked(str(r.get("id", "")))
		var tab := button(tr(str(r.get("name", ""))), _select_realm.bind(i))
		tab.disabled = not open
		if not open:
			tab.icon = LOCK
			tab.expand_icon = false
		tab.toggle_mode = true
		tab.button_pressed = i == _realm_index
		_tabs.add_child(tab)
	var medals := Label.new()
	medals.theme_type_variation = "HudLabel"
	medals.text = (
		"%d ● %d ● %d"
		% [
			Game.medal_count(Scoring.Medal.GOLD),
			Game.medal_count(Scoring.Medal.SILVER),
			Game.medal_count(Scoring.Medal.BRONZE)
		]
	)
	medals.tooltip_text = tr("Gold · Silver · Bronze medals")
	top.add_child(medals)

	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.add_theme_font_size_override("font_size", roundi(60 * Settings.text_scale))
	_title.text = tr(str(realm.get("name", "")))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_tagline = Label.new()
	_tagline.theme_type_variation = "HudLabel"
	_tagline.add_theme_font_size_override("font_size", roundi(20 * Settings.text_scale))
	_tagline.text = tr(str(realm.get("tagline", "")))
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_tagline)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_grid.columns = clampi(int(vp_w / (230.0 * Settings.text_scale)), 2, 6)
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	center.add_child(_grid)
	var levels: Array = realm.get("levels", [])
	var first_open: Button = null
	for i: int in levels.size():
		var card_btn := _level_card(str(levels[i]), i + 1)
		_grid.add_child(card_btn)
		if (
			first_open == null
			and not card_btn.disabled
			and not Game.save.is_completed(str(levels[i]))
		):
			first_open = card_btn
	if first_open != null:
		first_open.grab_focus.call_deferred()


func _level_card(id: String, number: int) -> Button:
	var open: bool = Game.is_level_unlocked(id)
	var lv: LevelData = Data.load_level(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(210, 150) * Settings.text_scale
	b.disabled = not open
	b.pressed.connect(func() -> void: Sfx.play_ui("ui_click", -8.0))
	b.pressed.connect(Game.play_level.bind(id))
	b.tooltip_text = lv.grievance
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 6
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(box)
	if open:
		var num := Label.new()
		num.theme_type_variation = "HeadingLabel"
		num.add_theme_font_size_override("font_size", roundi(34 * Settings.text_scale))
		num.text = str(number)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(num)
	else:
		var lock := TextureRect.new()
		lock.texture = LOCK
		lock.custom_minimum_size = Vector2(40, 40) * Settings.text_scale
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(lock)
	var name_l := Label.new()
	name_l.text = tr(lv.name) if open else "—"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", roundi(17 * Settings.text_scale))
	box.add_child(name_l)
	if Game.save.is_completed(id):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var stamp := MedalStamp.new()
		stamp.medal = Game.save.medal(id)
		stamp.custom_minimum_size = Vector2(38, 44) * Settings.text_scale
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stamp)
		var best := Label.new()
		best.theme_type_variation = "SmallLabel"
		var shots: int = int(Game.save.levels[id].get("best_shots", 0))
		best.text = tr_n("%d shot", "%d shots", shots) % shots
		row.add_child(best)
	for c: Node in box.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _select_realm(i: int) -> void:
	_realm_index = i
	_rebuild()
