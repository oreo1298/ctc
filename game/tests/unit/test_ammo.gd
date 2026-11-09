# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Ammo data and scripted-shot parsing (used by autoplay and the validator).


func test_shot_syntax() -> void:
	var s: Dictionary = Level.parse_shot("keg:0.61@0.9")
	assert_eq(s["ammo"], "keg")
	assert_almost_eq(float(s["phase"]), 0.61, 1e-6)
	assert_almost_eq(float(s["tap"]), 0.9, 1e-6)
	s = Level.parse_shot("0.65")
	assert_eq(s["ammo"], "")
	assert_lt(float(s["tap"]), 0.0, "no tap")


func test_every_ammo_has_a_look_and_valid_tap() -> void:
	assert_eq(Data.ammo.size(), 8, "eight ammo types")
	var taps: Array[String] = ["none", "burst", "detonate", "snap", "open"]
	for a: Dictionary in Data.ammo:
		assert_true(a.has("look"), str(a.get("id")))
		assert_has(taps, str(a.get("tap_action", "none")), str(a.get("id")))
		assert_not_null(autofree(Projectile.make_visual(a)), "visual for %s" % a.get("id"))


func test_boulder_is_always_available() -> void:
	assert_null(Data.ammo_def("boulder").get("unlock_after"))


func test_unlocks_reference_campaign_levels() -> void:
	var levels: PackedStringArray = Data.campaign_levels()
	for a: Dictionary in Data.ammo:
		var after: Variant = a.get("unlock_after")
		if after == null:
			continue
		if levels.size() < 36:
			pending("campaign not complete yet")
			return
		assert_has(levels, str(after), "%s unlocks after an existing level" % a.get("id"))
