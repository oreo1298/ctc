# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## A real level: the pause menu works while the game is paused, and a press
## after a shot goes back to the trebuchet.

var lv: Level


func before_each() -> void:
	Game.cli["no-save"] = "true"
	Game.custom_level = {}
	Game.custom_from_editor = false
	Game.current_level_id = "greenmantle-01"
	lv = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	add_child_autofree(lv)
	await wait_physics_frames(3)


func after_each() -> void:
	get_tree().paused = false
	Game.cli.erase("no-save")
	Effects.reset_time()


func _pause_keys(menu: Control) -> Node:
	for c: Node in menu.get_children():
		if not c is Control:
			return c
	return null


func test_pause_menu_works_while_paused() -> void:
	lv.toggle_pause()
	assert_true(get_tree().paused, "the game is paused")
	var menu: Control = lv.hud._pause
	assert_not_null(menu, "a pause menu is shown")
	assert_true(menu.can_process(), "the pause menu still runs (input, fade-in) while paused")
	var labels: Array[String] = []
	for b: Node in menu.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
		assert_true(b.can_process(), "%s can be pressed while paused" % (b as Button).text)
	for want: String in [tr("Resume"), tr("Restart"), tr("Choose level"), tr("Main menu")]:
		assert_has(labels, want)
	assert_true(lv.hud.main_menu_pressed.is_connected(Game.goto_menu), "Main menu leads home")
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	_pause_keys(menu)._unhandled_input(esc)
	assert_false(get_tree().paused, "Esc / Start resumes")
	assert_null(lv.hud._pause, "the menu is gone")


func test_resume_button_unpauses() -> void:
	lv.toggle_pause()
	var resume: Button = null
	for b: Node in lv.hud._pause.find_children("*", "Button", true, false):
		if (b as Button).text == tr("Resume"):
			resume = b
	resume.pressed.emit()
	assert_false(get_tree().paused)


func test_press_after_a_shot_goes_back_to_the_trebuchet() -> void:
	lv.on_fire()  # skip the intro
	await wait_physics_frames(2)
	assert_eq(lv.state, Level.State.READY)
	lv.on_fire()  # swing
	await wait_until(func() -> bool: return lv.trebuchet.current_phase() >= 0.32, 5.0)
	lv.on_fire()  # let go (a lob that lands behind the trebuchet)
	assert_eq(lv.state, Level.State.FLYING)
	lv.on_fire()
	assert_eq(lv.state, Level.State.FLYING, "a quick double tap does not throw the shot away")
	await wait_seconds(0.7)
	lv.on_fire()
	assert_eq(lv.state, Level.State.SETTLING, "the press skips the rest of the shot")
	assert_eq(lv.trebuchet.state, Trebuchet.State.REWINDING, "and reloads straight away")
	await wait_until(func() -> bool: return lv.state == Level.State.READY, 6.0)
	assert_eq(lv.state, Level.State.READY, "ready for the next shot")
	assert_eq(lv.shots, 1)


func _shoot(phase: float) -> void:
	lv.on_fire()  # skip the intro
	await wait_physics_frames(2)
	lv.on_fire()  # swing
	await wait_until(func() -> bool: return lv.trebuchet.current_phase() >= phase, 5.0)
	lv.on_fire()  # let go


func test_camera_comes_back_on_its_own() -> void:
	await _shoot(0.32)
	await wait_until(func() -> bool: return lv.state == Level.State.READY, 12.0)
	assert_eq(lv.state, Level.State.READY, "the shot settled and the trebuchet reloaded")
	await wait_physics_frames(30)
	assert_eq(lv.camera.mode, CameraRig.Mode.AIM, "the camera aims at the trebuchet again")
	assert_almost_eq(lv.camera.target_center, lv.camera.aim_center, Vector2.ONE)


func test_camera_stays_home_after_a_skip() -> void:
	await _shoot(0.32)
	await wait_seconds(0.7)
	lv.on_fire()
	for i: int in 8:
		await wait_physics_frames(15)
		assert_eq(lv.camera.mode, CameraRig.Mode.AIM, "nothing pulls the camera away (%d)" % i)
