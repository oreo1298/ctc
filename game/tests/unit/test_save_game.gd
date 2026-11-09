# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Saves are versioned; every historical version must keep loading.


func test_round_trip() -> void:
	var s := SaveGame.new()
	s.record_win("greenmantle-01", 2, Scoring.Medal.SILVER, 3000)
	s.unlocked_ammo.append("scatter")
	var errs := PackedStringArray()
	var back := SaveGame.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errs)
	assert_true(errs.is_empty(), "; ".join(errs))
	assert_eq(back.medal("greenmantle-01"), Scoring.Medal.SILVER)
	assert_true(back.unlocked_ammo.has("scatter"))


func test_v1_fixture_loads() -> void:
	var v1: Dictionary = {
		"format": "siegefall-save",
		"version": 1,
		"levels": {"greenmantle-01": {"medal": "gold", "best_shots": 1, "best_score": 4570}},
		"unlocked_ammo": ["boulder"],
		"last_level": "greenmantle-01",
	}
	var errs := PackedStringArray()
	var s := SaveGame.from_dict(v1, errs)
	assert_true(errs.is_empty())
	assert_eq(s.medal("greenmantle-01"), Scoring.Medal.GOLD)
	assert_eq(int(s.levels["greenmantle-01"]["best_shots"]), 1)


func test_rejects_future_and_garbage() -> void:
	var errs := PackedStringArray()
	SaveGame.from_dict({"version": 999}, errs)
	assert_false(errs.is_empty(), "newer saves are not silently truncated")
	errs.clear()
	var s := SaveGame.from_dict({"nonsense": true}, errs)
	assert_false(errs.is_empty())
	assert_true(s.unlocked_ammo.has("boulder"), "fresh save still playable")


func test_record_win_keeps_best() -> void:
	var s := SaveGame.new()
	s.record_win("l", 3, Scoring.Medal.BRONZE, 100)
	s.record_win("l", 1, Scoring.Medal.GOLD, 900)
	s.record_win("l", 5, Scoring.Medal.NONE, 50)
	assert_eq(s.medal("l"), Scoring.Medal.GOLD, "medal never downgrades")
	assert_eq(int(s.levels["l"]["best_shots"]), 1)
	assert_eq(int(s.levels["l"]["best_score"]), 900)


func test_boulder_always_unlocked() -> void:
	var errs := PackedStringArray()
	var s := SaveGame.from_dict({"version": 1, "unlocked_ammo": []}, errs)
	assert_true(s.unlocked_ammo.has("boulder"))
