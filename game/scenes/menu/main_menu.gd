# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node2D
## Title screen over a living backdrop. Milestone 3 adds the realm map,
## settings and the castle editor entry.

var _cam: Camera2D
var _t: float = 0.0


func _ready() -> void:
	var realm: Dictionary = Data.realms[0] if not Data.realms.is_empty() else {}
	var backdrop := Backdrop.new()
	add_child(backdrop)
	backdrop.build(
		realm.get("palette", {}), Data.grade("golden"), realm.get("backdrop", {}), 60.0, 7
	)
	_cam = Camera2D.new()
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_cam.zoom = Vector2(0.5, 0.5)
	add_child(_cam)
	_cam.make_current()

	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.build(Settings.text_scale)
	ui.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
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
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)
	var play := Button.new()
	play.theme_type_variation = "BigButton"
	play.text = tr("Play")
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(_on_play)
	box.add_child(play)
	if not OS.has_feature("ios") and not OS.has_feature("web"):
		var quit := Button.new()
		quit.text = tr("Quit")
		quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quit.pressed.connect(func() -> void: get_tree().quit())
		box.add_child(quit)
	var ver := Label.new()
	ver.theme_type_variation = "SmallLabel"
	ver.text = "v%s" % str(ProjectSettings.get_setting("application/config/version"))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	root.add_child(ver)
	play.grab_focus.call_deferred()


func _on_play() -> void:
	var levels: PackedStringArray = Data.campaign_levels()
	if levels.is_empty():
		return
	var target: String = levels[0]
	for id: String in levels:
		if not Game.save.is_completed(id):
			target = id
			break
	Game.play_level(target)


func _physics_process(delta: float) -> void:
	_t += delta
	_cam.position = Vector2(_t * 60.0, -300.0)
