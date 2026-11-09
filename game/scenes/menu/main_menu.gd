# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends MenuBase
## Title screen over a living backdrop.


func _ready() -> void:
	build_frame("", "golden")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = str(ProjectSettings.get_setting("application/config/name"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tag := Label.new()
	tag.theme_type_variation = "HudLabel"
	tag.text = tr("A petty king. A trebuchet. Your timing.")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)
	var started: bool = not Game.save.levels.is_empty()
	var play := button(tr("Continue") if started else tr("Play"), _on_play, "BigButton")
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(play)
	for pair: Array in [
		[tr("Choose level"), Game.goto_levels],
		[tr("Castle editor"), Game.goto_editor],
		[tr("Settings"), Game.goto_settings],
	]:
		var b := button(str(pair[0]), pair[1] as Callable)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(260, 0) * Settings.text_scale
		box.add_child(b)
	if not OS.has_feature("ios") and not OS.has_feature("web"):
		var quit := button(tr("Quit"), func() -> void: get_tree().quit())
		quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quit.custom_minimum_size = Vector2(260, 0) * Settings.text_scale
		box.add_child(quit)
	var ver := Label.new()
	ver.theme_type_variation = "SmallLabel"
	ver.text = "v%s" % str(ProjectSettings.get_setting("application/config/version"))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	ui.add_child(ver)
	play.grab_focus.call_deferred()


func _on_play() -> void:
	var id: String = Game.next_unfinished_level()
	if not id.is_empty():
		Game.play_level(id)


func go_back() -> void:
	pass
