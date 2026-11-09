# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Campaign progression and input remapping.

var _saved: SaveGame


func before_each() -> void:
	_saved = Game.save
	Game.save = SaveGame.new()
	Settings.path_override = "user://test-settings.cfg"


func after_each() -> void:
	Game.save = _saved
	Settings.path_override = ""


func test_campaign_has_three_realms_of_twelve() -> void:
	assert_eq(Data.realms.size(), 3)
	for r: Dictionary in Data.realms:
		assert_eq((r["levels"] as Array).size(), 12, str(r["id"]))
	assert_eq(Data.campaign_levels().size(), 36)


func test_levels_unlock_in_order() -> void:
	var all: PackedStringArray = Data.campaign_levels()
	assert_true(Game.is_level_unlocked(all[0]))
	assert_false(Game.is_level_unlocked(all[1]))
	Game.save.record_win(all[0], 3, Scoring.Medal.BRONZE, 100)
	assert_true(Game.is_level_unlocked(all[1]))
	assert_false(Game.is_level_unlocked(all[2]))
	assert_eq(Game.next_unfinished_level(), all[1])


func test_realm_unlocks_after_previous_finale() -> void:
	var g: Array = Data.realm("greenmantle")["levels"]
	assert_false(Game.is_realm_unlocked("saffron"))
	Game.save.record_win(str(g[g.size() - 1]), 1, Scoring.Medal.GOLD, 1)
	assert_true(Game.is_realm_unlocked("saffron"))


func test_ammo_unlocks_by_campaign_order() -> void:
	var newly: PackedStringArray = Game.record_win("greenmantle-03", 1, Scoring.Medal.GOLD, 10)
	assert_has(newly, "scatter")
	assert_true(Game.is_ammo_unlocked("scatter"))
	assert_false(Game.is_ammo_unlocked("void"))


func test_rebinding_round_trips() -> void:
	var saved: Dictionary = Settings.bindings.duplicate(true)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	Controls.rebind("fire", k)
	var data: Array = Controls.serialize("fire")
	assert_has(data, ["key", KEY_F])
	assert_false(data.has(["key", KEY_SPACE]), "the old key binding is replaced")
	assert_true(data.has(["joy", JOY_BUTTON_A]), "other devices keep their binding")
	Controls.reset_all()
	assert_has(Controls.serialize("fire"), ["key", KEY_SPACE])
	Settings.bindings = saved
	Settings.save_settings()
